from __future__ import annotations

import asyncio
import dataclasses
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

import httpx

from nanoprofit.queue import EventQueue
from nanoprofit.retry import with_retry
from nanoprofit.types import Event

logger = logging.getLogger("nanoprofit")


class NanoProfit:
    """Async client for the NanoProfit event-tracking API.

    Usage::

        async with NanoProfit(api_key="np_...") as np:
            np.track(Event(
                customer_external_id="cust_123",
                revenue_amount_in_cents=500,
                vendor_costs=[cost],
            ))
        # Events are automatically flushed on exit.

    Parameters
    ----------
    api_key:
        Your NanoProfit API key.
    base_url:
        API base URL.  Defaults to the production endpoint.
    flush_interval:
        Seconds between automatic background flushes.
    max_queue_size:
        Maximum events to buffer before the oldest are dropped.
    batch_size:
        Maximum events per HTTP request.
    max_retries:
        Number of attempts for each HTTP request (including the first try).
    default_event_type:
        Default ``event_type`` applied when :pyattr:`Event.event_type` is
        ``None``.
    """

    def __init__(
        self,
        *,
        api_key: str,
        base_url: str = "https://app.nanoprofit.dev/api/v1",
        flush_interval: float = 5.0,
        max_queue_size: int = 1000,
        batch_size: int = 25,
        max_retries: int = 3,
        default_event_type: str = "ai_request",
    ) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._max_retries = max_retries
        self._default_event_type = default_event_type

        self._http = httpx.AsyncClient(
            base_url=self._base_url,
            headers={
                "Authorization": f"Bearer {self._api_key}",
                "Content-Type": "application/json",
                "User-Agent": "nanoprofit-python/0.1.0",
            },
            timeout=httpx.Timeout(30.0),
        )

        self._queue = EventQueue(
            send_fn=self._send_batch,
            flush_interval=flush_interval,
            max_size=max_queue_size,
            batch_size=batch_size,
        )

    # ------------------------------------------------------------------
    # Context manager
    # ------------------------------------------------------------------

    async def __aenter__(self) -> NanoProfit:
        self._queue.start()
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: Any,
    ) -> None:
        await self.shutdown()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def track(self, event: Event) -> None:
        """Enqueue an event for batch sending.

        This method is **synchronous** and never raises.  Events are buffered
        internally and sent in the background.
        """
        try:
            payload = self._event_to_dict(event)
            self._queue.enqueue(payload)
        except Exception:
            logger.exception("nanoprofit: failed to enqueue event")

    async def flush(self) -> None:
        """Immediately flush all buffered events."""
        await self._queue.flush()

    async def shutdown(self) -> None:
        """Flush remaining events and close the HTTP client."""
        await self._queue.shutdown()
        await self._http.aclose()

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _event_to_dict(self, event: Event) -> dict[str, Any]:
        """Convert an :class:`Event` dataclass into the wire-format dict."""
        d = dataclasses.asdict(event)

        # Apply defaults for optional fields
        if d.get("unique_request_token") is None:
            d["unique_request_token"] = str(uuid.uuid4())
        if d.get("occurred_at") is None:
            d["occurred_at"] = datetime.now(timezone.utc).isoformat()
        if d.get("event_type") is None:
            d["event_type"] = self._default_event_type

        # Remove None values to keep payloads clean
        d = {k: v for k, v in d.items() if v is not None}

        # Clean None values from vendor_costs list entries
        if "vendor_costs" in d:
            d["vendor_costs"] = [
                {k: v for k, v in vc.items() if v is not None}
                for vc in d["vendor_costs"]
            ]

        return d

    async def _send_batch(self, events: list[dict[str, Any]]) -> None:
        """Send a batch of events to the API with retry logic."""
        results = await asyncio.gather(
            *(self._safe_send(e) for e in events),
            return_exceptions=True,
        )
        for r in results:
            if isinstance(r, Exception):
                logger.warning("nanoprofit: failed to send event: %s", r)

    async def _safe_send(self, event: dict[str, Any]) -> None:
        """Send a single event with retry."""

        async def _post() -> None:
            response = await self._http.post(
                "/events",
                json={"event": event},
            )
            response.raise_for_status()

        await with_retry(_post, max_retries=self._max_retries)
