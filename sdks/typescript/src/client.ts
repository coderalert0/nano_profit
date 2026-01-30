import { EventQueue } from "./queue.js";
import { withRetry } from "./retry.js";
import { toWireEvent } from "./serializer.js";
import type {
  BatchResult,
  EventPayload,
  NanoProfitConfig,
  NanoProfitError,
  WireEvent,
} from "./types.js";

const DEFAULT_BASE_URL = "https://app.nanoprofit.dev/api/v1";
const DEFAULT_FLUSH_INTERVAL_MS = 5_000;
const DEFAULT_MAX_QUEUE_SIZE = 1_000;
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_MAX_RETRIES = 3;
const DEFAULT_EVENT_TYPE = "ai_request";

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
  private readonly onError?: (error: NanoProfitError) => void;
  private readonly queue: EventQueue;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private flushTimer: any = null;
  private shutdownPromise: Promise<void> | null = null;
  private signalHandlers: Array<{ signal: string; handler: () => void }> = [];

  constructor(config: NanoProfitConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.maxRetries = config.maxRetries ?? DEFAULT_MAX_RETRIES;
    this.defaultEventType = config.defaultEventType ?? DEFAULT_EVENT_TYPE;
    this.onError = config.onError;

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

    // Register signal handlers for graceful shutdown (opt-out via handleSignals: false).
    if (config.handleSignals !== false && typeof process !== "undefined" && process.on) {
      for (const signal of ["SIGTERM", "SIGINT"] as const) {
        const handler = () => {
          void this.shutdown().then(() => {
            process.exit(0);
          });
        };
        process.on(signal, handler);
        this.signalHandlers.push({ signal, handler });
      }
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
    // Guard against double-flush: return the same promise if already shutting down.
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }

    this.shutdownPromise = (async () => {
      if (this.flushTimer !== null) {
        clearInterval(this.flushTimer);
        this.flushTimer = null;
      }

      // Remove signal handlers so we don't leak listeners.
      for (const { signal, handler } of this.signalHandlers) {
        process.removeListener(signal, handler);
      }
      this.signalHandlers = [];

      await this.flush();
    })();

    return this.shutdownPromise;
  }

  /** Send a single batch of events to the API with retry. */
  private async sendBatch(events: WireEvent[]): Promise<void> {
    try {
      const response = await withRetry(
        async () => {
          const res = await fetch(`${this.baseUrl}/events`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${this.apiKey}`,
            },
            body: JSON.stringify({ events }),
          });

          // Retry on 5xx server errors.
          if (res.status >= 500) {
            throw res;
          }

          return res;
        },
        { maxRetries: this.maxRetries },
      );

      // Handle partial failure (207 Multi-Status).
      if (response.status === 207) {
        const body = (await response.json()) as { results: BatchResult[] };
        const failed = body.results.filter((r) => r.status === "error");
        if (failed.length > 0) {
          this.reportError({
            message: `Batch partially failed: ${failed.length} of ${body.results.length} events had errors`,
            events,
          });
        }
        return;
      }

      // Total failure (4xx).
      if (!response.ok) {
        let errorMessage = `Batch request failed with status ${response.status}`;
        try {
          const body = await response.json();
          if (body.error) errorMessage = body.error;
        } catch {
          // ignore parse errors
        }
        this.reportError({ message: errorMessage, events });
      }
    } catch (err) {
      this.reportError({
        message: "Batch request failed after retries",
        cause: err,
        events,
      });
    }
  }

  /** Call the onError callback if configured, swallowing any errors from the callback. */
  private reportError(error: NanoProfitError): void {
    if (!this.onError) return;
    try {
      this.onError(error);
    } catch {
      // Never let a callback error crash the SDK.
    }
  }
}
