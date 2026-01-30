from __future__ import annotations

import logging
from typing import Any, Callable

import httpx

from nanoprofit.queue import EventQueue
from nanoprofit.retry import with_retry
from nanoprofit.serializer import event_to_dict
from nanoprofit.types import Event, NanoProfitError

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
    on_error:
        Optional callback invoked when a batch fails or partially fails.
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
        on_error: Callable[[NanoProfitError], None] | None = None,
    ) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._max_retries = max_retries
        self._default_event_type = default_event_type
        self._on_error = on_error

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
            payload = event_to_dict(event, self._default_event_type)
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

    async def _send_batch(self, events: list[dict[str, Any]]) -> None:
        """Send a batch of events to the API with retry logic."""
        try:
            async def _post() -> httpx.Response:
                response = await self._http.post(
                    "/events",
                    json={"events": events},
                )
                # Retry on 5xx server errors.
                if response.status_code >= 500:
                    response.raise_for_status()
                return response

            response = await with_retry(_post, max_retries=self._max_retries)

            # Handle partial failure (207 Multi-Status).
            if response.status_code == 207:
                body = response.json()
                failed = [r for r in body.get("results", []) if r.get("status") == "error"]
                if failed:
                    self._report_error(NanoProfitError(
                        message=f"Batch partially failed: {len(failed)} of {len(body['results'])} events had errors",
                        events=events,
                    ))
                return

            # Total failure (4xx).
            if response.status_code >= 400:
                error_message = f"Batch request failed with status {response.status_code}"
                try:
                    body = response.json()
                    if body.get("error"):
                        error_message = body["error"]
                except Exception:
                    pass
                self._report_error(NanoProfitError(
                    message=error_message,
                    events=events,
                ))

        except Exception as exc:
            self._report_error(NanoProfitError(
                message="Batch request failed after retries",
                cause=exc,
                events=events,
            ))

    def _report_error(self, error: NanoProfitError) -> None:
        """Log a warning and call the on_error callback if configured."""
        logger.warning("nanoprofit: %s", error.message)
        if self._on_error is None:
            return
        try:
            self._on_error(error)
        except Exception:
            logger.exception("nanoprofit: on_error callback raised")
