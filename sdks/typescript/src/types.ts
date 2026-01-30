/** Cost data for a single AI vendor call. */
export interface VendorCost {
  vendorName: string;
  aiModelName: string;
  inputTokens: number;
  outputTokens: number;
  unitCount?: number;
  unitType?: string;
  amountInCents?: number;
}

/** Payload passed to `NanoProfit.track()`. */
export interface EventPayload {
  customerExternalId: string;
  revenueAmountInCents: number;
  vendorCosts: VendorCost[];
  uniqueRequestToken?: string;
  customerName?: string;
  eventType?: string;
  occurredAt?: string;
  metadata?: Record<string, unknown>;
}

/** Error information surfaced via the `onError` callback. */
export interface NanoProfitError {
  message: string;
  cause?: unknown;
  events?: WireEvent[];
}

/** Per-event result returned by the batch API. */
export interface BatchResult {
  id: number;
  status: string;
  errors?: string[];
}

/** SDK configuration options. */
export interface NanoProfitConfig {
  apiKey: string;
  baseUrl?: string;
  flushIntervalMs?: number;
  maxQueueSize?: number;
  batchSize?: number;
  maxRetries?: number;
  defaultEventType?: string;
  onError?: (error: NanoProfitError) => void;
  handleSignals?: boolean;
}

/** Internal wire format for vendor costs (snake_case). */
export interface WireVendorCost {
  vendor_name: string;
  ai_model_name: string;
  input_tokens: number;
  output_tokens: number;
  unit_count?: number;
  unit_type?: string;
  amount_in_cents?: number;
}

/** Internal wire format for events (snake_case). */
export interface WireEvent {
  customer_external_id: string;
  revenue_amount_in_cents: number;
  vendor_costs: WireVendorCost[];
  unique_request_token: string;
  customer_name?: string;
  event_type: string;
  occurred_at: string;
  metadata?: Record<string, unknown>;
}
