import { EventQueue } from "./queue.js";
import { withRetry } from "./retry.js";
import type {
  EventPayload,
  NanoProfitConfig,
  VendorCost,
  WireEvent,
  WireVendorCost,
} from "./types.js";

const DEFAULT_BASE_URL = "https://app.nanoprofit.dev/api/v1";
const DEFAULT_FLUSH_INTERVAL_MS = 5_000;
const DEFAULT_MAX_QUEUE_SIZE = 1_000;
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_MAX_RETRIES = 3;
const DEFAULT_EVENT_TYPE = "ai_request";

/** Convert a camelCase `VendorCost` to the snake_case wire format. */
function toWireVendorCost(vc: VendorCost): WireVendorCost {
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
function toWireEvent(
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

/**
 * NanoProfit client.
 *
 * Queues events in memory and flushes them to the NanoProfit API in
 * batches on a timer. Call {@link shutdown} when your process is about
 * to exit so that remaining events are delivered.
 */
export class NanoProfit {
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly maxRetries: number;
  private readonly defaultEventType: string;
  private readonly queue: EventQueue;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private flushTimer: any = null;

  constructor(config: NanoProfitConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.maxRetries = config.maxRetries ?? DEFAULT_MAX_RETRIES;
    this.defaultEventType = config.defaultEventType ?? DEFAULT_EVENT_TYPE;

    this.queue = new EventQueue(
      config.maxQueueSize ?? DEFAULT_MAX_QUEUE_SIZE,
      config.batchSize ?? DEFAULT_BATCH_SIZE,
    );

    const intervalMs = config.flushIntervalMs ?? DEFAULT_FLUSH_INTERVAL_MS;
    this.flushTimer = setInterval(() => {
      void this.flush();
    }, intervalMs);

    // Allow the Node.js process to exit even if the timer is still running.
    if (this.flushTimer && typeof this.flushTimer.unref === "function") {
      this.flushTimer.unref();
    }
  }

  /**
   * Enqueue an event for delivery. This method is synchronous and will
   * never throw -- errors are silently swallowed so that tracking can
   * never crash the host application.
   */
  track(event: EventPayload): void {
    try {
      const wire = toWireEvent(event, this.defaultEventType);
      this.queue.enqueue(wire);
    } catch {
      // Intentionally swallowed -- tracking must never throw.
    }
  }

  /**
   * Flush all queued events to the API immediately.
   *
   * Each batch is sent independently via `Promise.allSettled`, so one
   * failing batch does not block the others.
   */
  async flush(): Promise<void> {
    const batches = this.queue.drain();
    if (batches.length === 0) return;

    await Promise.allSettled(
      batches.map((batch) => this.sendBatch(batch)),
    );
  }

  /**
   * Flush remaining events and stop the background timer.
   * Call this before your process exits.
   */
  async shutdown(): Promise<void> {
    if (this.flushTimer !== null) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flush();
  }

  /** Send a single batch of events to the API with retry. */
  private async sendBatch(events: WireEvent[]): Promise<void> {
    await Promise.allSettled(
      events.map((wireEvent) =>
        withRetry(
          async () => {
            const response = await fetch(`${this.baseUrl}/events`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${this.apiKey}`,
              },
              body: JSON.stringify({ event: wireEvent }),
            });

            if (!response.ok) {
              // Throw the Response so the retry logic can inspect the status.
              throw response;
            }
          },
          { maxRetries: this.maxRetries },
        ),
      ),
    );
  }
}
