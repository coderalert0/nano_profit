from __future__ import annotations

from typing import Any

from nanoprofit.types import VendorCost


def extract_google(response: Any, vendor_name: str | None = None) -> VendorCost:
    """Extract token usage from a Google Gemini / Vertex AI response object.

    Handles both snake_case (Python SDK) and camelCase (REST / proto-plus)
    attribute names for maximum compatibility.
    """
    model_version = (
        getattr(response, "model_version", None)
        or getattr(response, "modelVersion", "")
        or ""
    )

    usage = getattr(response, "usage_metadata", None) or getattr(
        response, "usageMetadata", None
    )

    input_tokens = 0
    output_tokens = 0
    if usage is not None:
        input_tokens = (
            getattr(usage, "prompt_token_count", 0)
            or getattr(usage, "promptTokenCount", 0)
            or 0
        )
        output_tokens = (
            getattr(usage, "candidates_token_count", 0)
            or getattr(usage, "candidatesTokenCount", 0)
            or 0
        )

    return VendorCost(
        vendor_name=vendor_name or "gemini",
        ai_model_name=model_version,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
    )
