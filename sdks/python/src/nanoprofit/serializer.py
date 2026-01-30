from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from nanoprofit.types import Event


def _serialize_raw_response(raw: Any) -> Any:
    """Serialize a raw_response value to a JSON-compatible structure."""
    if isinstance(raw, dict):
        return raw
    # Pydantic models
    if hasattr(raw, "model_dump"):
        return raw.model_dump()
    # Objects with __dict__ (e.g. SDK response objects)
    if hasattr(raw, "__dict__"):
        return vars(raw)
    return raw


def event_to_dict(
    event: Event,
    responses: list[tuple[str, Any]],
    default_event_type: str,
) -> dict[str, Any]:
    """Convert an :class:`Event` dataclass + accumulated responses into
    the wire-format dict."""
    d: dict[str, Any] = {
        "customer_external_id": event.customer_external_id,
        "revenue_amount_in_cents": event.revenue_amount_in_cents,
        "vendor_responses": [
            {
                "vendor_name": vendor_name,
                "raw_response": _serialize_raw_response(raw_response),
            }
            for vendor_name, raw_response in responses
        ],
    }

    d["unique_request_token"] = (
        event.unique_request_token
        if event.unique_request_token is not None
        else str(uuid.uuid4())
    )
    d["occurred_at"] = (
        event.occurred_at
        if event.occurred_at is not None
        else datetime.now(timezone.utc).isoformat()
    )
    d["event_type"] = (
        event.event_type
        if event.event_type is not None
        else default_event_type
    )

    if event.customer_name is not None:
        d["customer_name"] = event.customer_name
    if event.metadata is not None:
        d["metadata"] = event.metadata

    return d
