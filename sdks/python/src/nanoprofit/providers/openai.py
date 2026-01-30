from __future__ import annotations

from typing import Any

from nanoprofit.types import VendorCost


def extract_openai(response: Any, vendor_name: str | None = None) -> VendorCost:
    """Extract token usage from an OpenAI chat/completion response object.

    Works with both the ``openai`` Python SDK response objects and any
    duck-typed object that exposes ``.model`` and ``.usage`` attributes.
    """
    return VendorCost(
        vendor_name=vendor_name or "openai",
        ai_model_name=response.model,
        input_tokens=getattr(response.usage, "prompt_tokens", 0) or 0,
        output_tokens=getattr(response.usage, "completion_tokens", 0) or 0,
    )
