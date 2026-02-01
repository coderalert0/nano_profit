from __future__ import annotations

import asyncio
import logging
from collections import deque
from typing import Any, Awaitable, Callable

logger = logging.getLogger("margindash.queue")


class EventQueue:
    """Internal async queue that batches events and flushes them periodically.

    Parameters
    ----------
    send_fn:
        An async callable that receives a list of event dicts and sends them
        to the MarginDash API.
    flush_interval:
        Seconds between automatic flushes.  Defaults to ``5.0``.
    max_size:
        Maximum number of events to buffer.  Oldest events are dropped when
        this limit is exceeded.  Defaults to ``1000``.
    batch_size:
        Maximum number of events per batch sent to *send_fn*.
        Defaults to ``25``.
    """

    def __init__(
        self,
        send_fn: Callable[[list[dict[str, Any]]], Awaitable[None]],
        *,
        flush_interval: float = 5.0,
        max_size: int = 1000,
        batch_size: int = 25,
    ) -> None:
        self._send_fn = send_fn
        self._flush_interval = flush_interval
        self._max_size = max_size
        self._batch_size = batch_size
        self._buffer: deque[dict[str, Any]] = deque(maxlen=max_size)
        self._flush_task: asyncio.Task[None] | None = None

    # ------------------------------------------------------------------
    # Public helpers
    # ------------------------------------------------------------------

    def enqueue(self, event: dict[str, Any]) -> None:
        """Add *event* to the buffer.  Never raises."""
        try:
            self._buffer.append(event)
        except Exception:
            logger.exception("margindash: failed to enqueue event")

    def drain(self) -> list[list[dict[str, Any]]]:
        """Remove all buffered events and return them split into batches of
        up to :pyattr:`_batch_size` items each."""
        batches: list[list[dict[str, Any]]] = []
        batch: list[dict[str, Any]] = []

        while self._buffer:
            batch.append(self._buffer.popleft())
            if len(batch) >= self._batch_size:
                batches.append(batch)
                batch = []

        if batch:
            batches.append(batch)
        return batches

    # ------------------------------------------------------------------
    # Flush loop
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the periodic flush loop as a background task."""
        if self._flush_task is None or self._flush_task.done():
            self._flush_task = asyncio.ensure_future(self._flush_loop())

    async def _flush_loop(self) -> None:
        """Periodically flush buffered events."""
        try:
            while True:
                await asyncio.sleep(self._flush_interval)
                await self.flush()
        except asyncio.CancelledError:
            # Final flush on cancellation
            await self.flush()

    async def flush(self) -> None:
        """Immediately flush all buffered events by sending them in batches."""
        batches = self.drain()
        if not batches:
            return

        tasks = [asyncio.ensure_future(self._safe_send(batch)) for batch in batches]
        await asyncio.gather(*tasks)

    async def _safe_send(self, batch: list[dict[str, Any]]) -> None:
        """Send a single batch, swallowing exceptions so one failure does not
        prevent other batches from being sent."""
        try:
            await self._send_fn(batch)
        except Exception:
            logger.exception("margindash: failed to send batch of %d events", len(batch))

    async def shutdown(self) -> None:
        """Cancel the flush loop and perform a final flush."""
        if self._flush_task is not None and not self._flush_task.done():
            self._flush_task.cancel()
            try:
                await self._flush_task
            except asyncio.CancelledError:
                pass
        # Final flush to send any remaining events
        await self.flush()
