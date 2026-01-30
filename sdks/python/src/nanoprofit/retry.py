from __future__ import annotations

import asyncio
import random
from typing import Awaitable, Callable, TypeVar

import httpx

T = TypeVar("T")


class NonRetryableError(Exception):
    """Raised for errors that should not be retried (e.g. 401, 422)."""

    pass


async def with_retry(
    fn: Callable[[], Awaitable[T]],
    *,
    max_retries: int = 3,
) -> T:
    """Execute *fn* with exponential back-off and jitter.

    Strategy:
    - Up to *max_retries* attempts (default 3).
    - Delay between attempts: ``min(1s * 2^attempt, 30s)`` plus up to 1 s of
      random jitter.
    - Retries on 5xx HTTP status codes and network-level errors.
    - Immediately raises :class:`NonRetryableError` for 4xx responses that
      indicate a permanent client error (401 Unauthorized, 422 Unprocessable
      Entity).
    """

    last_exc: BaseException | None = None

    for attempt in range(max_retries):
        try:
            return await fn()
        except NonRetryableError:
            raise
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            if status in (401, 422):
                raise NonRetryableError(
                    f"Non-retryable HTTP {status}: {exc}"
                ) from exc
            # 5xx and other server errors are retryable
            last_exc = exc
        except (httpx.TransportError, OSError) as exc:
            # Network-level failures are retryable
            last_exc = exc

        if attempt < max_retries - 1:
            base_delay = min(1.0 * (2**attempt), 30.0)
            jitter = random.uniform(0, 1.0)
            await asyncio.sleep(base_delay + jitter)

    # All retries exhausted
    raise last_exc  # type: ignore[misc]
