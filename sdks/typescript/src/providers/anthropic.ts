import type { VendorCost } from "../types.js";

/**
 * Extract token usage from an Anthropic message response object.
 *
 * @param response - The raw response from the Anthropic SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"anthropic"`).
 */
export function extractAnthropic(
  response: any,
  vendorName?: string,
): VendorCost {
  return {
    vendorName: vendorName ?? "anthropic",
    aiModelName: response.model,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
  };
}
