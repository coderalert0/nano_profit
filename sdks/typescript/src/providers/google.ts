import type { VendorCost } from "../types.js";

/**
 * Extract token usage from a Google Gemini response object.
 *
 * @param response - The raw response from the Google AI SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"gemini"`).
 */
export function extractGoogle(
  response: any,
  vendorName?: string,
): VendorCost {
  return {
    vendorName: vendorName ?? "gemini",
    aiModelName: response.modelVersion ?? "",
    inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
  };
}
