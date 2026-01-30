from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Event:
    customer_external_id: str
    revenue_amount_in_cents: int
    unique_request_token: str | None = None
    customer_name: str | None = None
    event_type: str | None = None
    occurred_at: str | None = None
    metadata: dict[str, Any] | None = None


@dataclass
class NanoProfitError:
    message: str
    cause: Exception | None = None
    events: list | None = None
