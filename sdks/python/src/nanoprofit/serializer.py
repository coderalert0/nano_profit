from __future__ import annotations

import dataclasses
import uuid
from datetime import datetime, timezone
from typing import Any

from nanoprofit.types import Event


def event_to_dict(event: Event, default_event_type: str) -> dict[str, Any]:
    """Convert an :class:`Event` dataclass into the wire-format dict."""
    d = dataclasses.asdict(event)

    # Apply defaults for optional fields
    if d.get("unique_request_token") is None:
        d["unique_request_token"] = str(uuid.uuid4())
    if d.get("occurred_at") is None:
        d["occurred_at"] = datetime.now(timezone.utc).isoformat()
    if d.get("event_type") is None:
        d["event_type"] = default_event_type

    # Remove None values to keep payloads clean
    d = {k: v for k, v in d.items() if v is not None}

    # Clean None values from vendor_costs list entries
    if "vendor_costs" in d:
        d["vendor_costs"] = [
            {k: v for k, v in vc.items() if v is not None}
            for vc in d["vendor_costs"]
        ]

    return d
