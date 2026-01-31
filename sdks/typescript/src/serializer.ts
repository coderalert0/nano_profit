import type {
  EventPayload,
  UsageData,
  WireEvent,
} from "./types.js";

/** Pending usage entry collected via `addUsage()`. */
export interface PendingUsage {
  vendorName: string;
  usage: UsageData;
}

/** Convert a camelCase `EventPayload` + accumulated usage entries to the snake_case wire format. */
export function toWireEvent(
  event: EventPayload,
  usages: PendingUsage[],
  defaultEventType: string,
): WireEvent {
  const wire: WireEvent = {
    customer_external_id: event.customerExternalId,
    revenue_amount_in_cents: event.revenueAmountInCents,
    vendor_responses: usages.map((u) => ({
      vendor_name: u.vendorName,
      raw_response: {
        ai_model_name: u.usage.model,
        input_tokens: u.usage.inputTokens,
        output_tokens: u.usage.outputTokens,
      },
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
