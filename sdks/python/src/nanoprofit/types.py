from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class VendorCost:
    vendor_name: str
    ai_model_name: str
    input_tokens: int
    output_tokens: int
    unit_count: int | None = None
    unit_type: str | None = None
    amount_in_cents: float | None = None


@dataclass
class Event:
    customer_external_id: str
    revenue_amount_in_cents: int
    vendor_costs: list[VendorCost]
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
