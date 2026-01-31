import type {
  EventPayload,
  WireEvent,
} from "./types.js";

/** Pending response collected via `addResponse()`. */
export interface PendingResponse {
  vendorName: string;
  rawResponse: Record<string, unknown>;
}

/**
 * Top-level keys the server-side parser reads from raw responses.
 * Keep in sync with VendorResponseParser on the server.
 * Anything not in this list is stripped before sending to reduce payload size.
 */
const USAGE_KEYS = [
  "model",            // OpenAI, Anthropic, Google fallback
  "usage",            // OpenAI (prompt_tokens, completion_tokens), Anthropic (input_tokens, output_tokens)
  "modelVersion",     // Google (camelCase)
  "model_version",    // Google (snake_case)
  "usageMetadata",    // Google (camelCase)
  "usage_metadata",   // Google (snake_case)
];

/** Strip a raw AI response down to only the keys needed for cost calculation. */
function stripToUsage(raw: Record<string, unknown>): Record<string, unknown> {
  const stripped: Record<string, unknown> = {};
  for (const key of USAGE_KEYS) {
    if (key in raw) {
      stripped[key] = raw[key];
    }
  }
  return stripped;
}

/** Convert a camelCase `EventPayload` + accumulated responses to the snake_case wire format. */
export function toWireEvent(
  event: EventPayload,
  responses: PendingResponse[],
  defaultEventType: string,
): WireEvent {
  const wire: WireEvent = {
    customer_external_id: event.customerExternalId,
    revenue_amount_in_cents: event.revenueAmountInCents,
    vendor_responses: responses.map((r) => ({
      vendor_name: r.vendorName,
      raw_response: stripToUsage(r.rawResponse),
    })),
    unique_request_token:
      event.uniqueRequestToken ?? crypto.randomUUID(),
    event_type: event.eventType ?? defaultEventType,
    occurred_at: event.occurredAt ?? new Date().toISOString(),
  };
  if (event.customerName !== undefined) {
    wire.customer_name = event.customerName;
  }
  if (event.metadata !== undefined) {
    wire.metadata = event.metadata;
  }
  return wire;
}
