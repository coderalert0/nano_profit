/** Payload passed to `NanoProfit.track()`. */
interface EventPayload {
    customerExternalId: string;
    revenueAmountInCents: number;
    uniqueRequestToken?: string;
    customerName?: string;
    eventType?: string;
    occurredAt?: string;
    metadata?: Record<string, unknown>;
}
/** Error information surfaced via the `onError` callback. */
interface NanoProfitError {
    message: string;
    cause?: unknown;
    events?: WireEvent[];
}
/** Per-event result returned by the batch API. */
interface BatchResult {
    id: number;
    status: string;
    errors?: string[];
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
    onError?: (error: NanoProfitError) => void;
    handleSignals?: boolean;
}
/** Internal wire format for events (snake_case). */
interface WireEvent {
    customer_external_id: string;
    revenue_amount_in_cents: number;
    vendor_responses: {
        vendor_name: string;
        raw_response: Record<string, unknown>;
    }[];
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
    private readonly onError?;
    private readonly queue;
    private flushTimer;
    private shutdownPromise;
    private signalHandlers;
    private pendingResponses;
    constructor(config: NanoProfitConfig);
    /**
     * Append a raw AI provider response for inclusion in the next
     * {@link track} call. Call this once per AI API call — if an agent
     * session makes three calls, call `addResponse` three times, then
     * call `track` once to attach them all to a single event.
     */
    addResponse(vendorName: string, rawResponse: Record<string, unknown>): void;
    /**
     * Enqueue an event for delivery. This method is synchronous and will
     * never throw -- errors are silently swallowed so that tracking can
     * never crash the host application.
     *
     * All responses previously added via {@link addResponse} are drained
     * and attached to the event.
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
    /** Call the onError callback if configured, swallowing any errors from the callback. */
    private reportError;
}

export { type BatchResult, type EventPayload, NanoProfit, type NanoProfitConfig, type NanoProfitError, type WireEvent };
