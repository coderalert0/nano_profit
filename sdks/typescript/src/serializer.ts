import type {
  EventPayload,
  WireEvent,
} from "./types.js";

/** Pending response collected via `addResponse()`. */
export interface PendingResponse {
  vendorName: string;
  rawResponse: Record<string, unknown>;
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
      raw_response: r.rawResponse,
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
