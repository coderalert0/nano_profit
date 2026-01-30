import type {
  EventPayload,
  VendorCost,
  WireEvent,
  WireVendorCost,
} from "./types.js";

/** Convert a camelCase `VendorCost` to the snake_case wire format. */
export function toWireVendorCost(vc: VendorCost): WireVendorCost {
  const wire: WireVendorCost = {
    vendor_name: vc.vendorName,
    ai_model_name: vc.aiModelName,
    input_tokens: vc.inputTokens,
    output_tokens: vc.outputTokens,
  };
  if (vc.unitCount !== undefined) wire.unit_count = vc.unitCount;
  if (vc.unitType !== undefined) wire.unit_type = vc.unitType;
  if (vc.amountInCents !== undefined) wire.amount_in_cents = vc.amountInCents;
  return wire;
}

/** Convert a camelCase `EventPayload` to the snake_case wire format. */
export function toWireEvent(
  event: EventPayload,
  defaultEventType: string,
): WireEvent {
  const wire: WireEvent = {
    customer_external_id: event.customerExternalId,
    revenue_amount_in_cents: event.revenueAmountInCents,
    vendor_costs: event.vendorCosts.map(toWireVendorCost),
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
