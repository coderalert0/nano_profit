/** Cost data for a single AI vendor call. */
interface VendorCost {
    vendorName: string;
    aiModelName: string;
    inputTokens: number;
    outputTokens: number;
    unitCount?: number;
    unitType?: string;
    amountInCents?: number;
}
/** Payload passed to `NanoProfit.track()`. */
interface EventPayload {
    customerExternalId: string;
    revenueAmountInCents: number;
    vendorCosts: VendorCost[];
    uniqueRequestToken?: string;
    customerName?: string;
    eventType?: string;
    occurredAt?: string;
    metadata?: Record<string, unknown>;
}
/** SDK configuration options. */
interface NanoProfitConfig {
    apiKey: string;
    baseUrl?: string;
    flushIntervalMs?: number;
    maxQueueSize?: number;
    batchSize?: number;
    maxRetries?: number;
    defaultEventType?: string;
}
/** Internal wire format for vendor costs (snake_case). */
interface WireVendorCost {
    vendor_name: string;
    ai_model_name: string;
    input_tokens: number;
    output_tokens: number;
    unit_count?: number;
    unit_type?: string;
    amount_in_cents?: number;
}
/** Internal wire format for events (snake_case). */
interface WireEvent {
    customer_external_id: string;
    revenue_amount_in_cents: number;
    vendor_costs: WireVendorCost[];
    unique_request_token: string;
    customer_name?: string;
    event_type: string;
    occurred_at: string;
    metadata?: Record<string, unknown>;
}

/**
 * NanoProfit client.
 *
 * Queues events in memory and flushes them to the NanoProfit API in
 * batches on a timer. Call {@link shutdown} when your process is about
 * to exit so that remaining events are delivered.
 */
declare class NanoProfit {
    private readonly apiKey;
    private readonly baseUrl;
    private readonly maxRetries;
    private readonly defaultEventType;
    private readonly queue;
    private flushTimer;
    constructor(config: NanoProfitConfig);
    /**
     * Enqueue an event for delivery. This method is synchronous and will
     * never throw -- errors are silently swallowed so that tracking can
     * never crash the host application.
     */
    track(event: EventPayload): void;
    /**
     * Flush all queued events to the API immediately.
     *
     * Each batch is sent independently via `Promise.allSettled`, so one
     * failing batch does not block the others.
     */
    flush(): Promise<void>;
    /**
     * Flush remaining events and stop the background timer.
     * Call this before your process exits.
     */
    shutdown(): Promise<void>;
    /** Send a single batch of events to the API with retry. */
    private sendBatch;
}

/**
 * Extract token usage from an OpenAI chat/completion response object.
 *
 * @param response - The raw response from the OpenAI SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"openai"`).
 */
declare function extractOpenAI(response: any, vendorName?: string): VendorCost;

/**
 * Extract token usage from an Anthropic message response object.
 *
 * @param response - The raw response from the Anthropic SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"anthropic"`).
 */
declare function extractAnthropic(response: any, vendorName?: string): VendorCost;

/**
 * Extract token usage from a Google Gemini response object.
 *
 * @param response - The raw response from the Google AI SDK.
 * @param vendorName - Optional override for the vendor name (defaults to `"gemini"`).
 */
declare function extractGoogle(response: any, vendorName?: string): VendorCost;

export { type EventPayload, NanoProfit, type NanoProfitConfig, type VendorCost, type WireEvent, type WireVendorCost, extractAnthropic, extractGoogle, extractOpenAI };
