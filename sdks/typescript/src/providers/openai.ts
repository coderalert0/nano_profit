import type { VendorCost } from "../types.js";

/**
 * Extract token usage from an OpenAI chat/completion response object.
 *
 * @param response - The raw response from the OpenAI SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"openai"`).
 */
export function extractOpenAI(
  response: any,
  vendorName?: string,
): VendorCost {
  return {
    vendorName: vendorName ?? "openai",
    aiModelName: response.model,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
  };
}
