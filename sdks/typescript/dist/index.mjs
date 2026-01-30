// src/queue.ts
var DEFAULT_MAX_SIZE = 1e3;
var DEFAULT_BATCH_SIZE = 25;
var EventQueue = class {
  items = [];
  maxSize;
  batchSize;
  constructor(maxSize, batchSize) {
    this.maxSize = maxSize ?? DEFAULT_MAX_SIZE;
    this.batchSize = batchSize ?? DEFAULT_BATCH_SIZE;
  }
  /** Number of events currently queued. */
  get length() {
    return this.items.length;
  }
  /**
   * Add an event to the queue.
   * If the queue is full, the oldest event is dropped to make room.
   */
  enqueue(event) {
    if (this.items.length >= this.maxSize) {
      this.items.shift();
    }
    this.items.push(event);
  }
  /**
   * Drain the queue and return the events split into batches of up to
   * `batchSize` items each.
   */
  drain() {
    if (this.items.length === 0) return [];
    const all = this.items;
    this.items = [];
    const batches = [];
    for (let i = 0; i < all.length; i += this.batchSize) {
      batches.push(all.slice(i, i + this.batchSize));
    }
    return batches;
  }
};

// src/retry.ts
var NON_RETRYABLE_STATUSES = /* @__PURE__ */ new Set([401, 422]);
function isRetryableError(error) {
  if (error instanceof Response) {
    if (NON_RETRYABLE_STATUSES.has(error.status)) return false;
    return error.status >= 500;
  }
  return true;
}
function backoffMs(attempt) {
  const base = Math.min(1e3 * Math.pow(2, attempt), 3e4);
  const jitter = Math.random() * base * 0.5;
  return base + jitter;
}
async function withRetry(fn, options) {
  let lastError;
  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (!isRetryableError(error)) {
        throw error;
      }
      if (attempt < options.maxRetries) {
        const delay = backoffMs(attempt);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError;
}

// src/serializer.ts
function toWireEvent(event, responses, defaultEventType) {
  const wire = {
    customer_external_id: event.customerExternalId,
    revenue_amount_in_cents: event.revenueAmountInCents,
    vendor_responses: responses.map((r) => ({
      vendor_name: r.vendorName,
      raw_response: r.rawResponse
    })),
    unique_request_token: event.uniqueRequestToken ?? crypto.randomUUID(),
    event_type: event.eventType ?? defaultEventType,
    occurred_at: event.occurredAt ?? (/* @__PURE__ */ new Date()).toISOString()
  };
  if (event.customerName !== void 0) {
    wire.customer_name = event.customerName;
  }
  if (event.metadata !== void 0) {
    wire.metadata = event.metadata;
  }
  return wire;
}

// src/client.ts
var DEFAULT_BASE_URL = "https://app.nanoprofit.dev/api/v1";
var DEFAULT_FLUSH_INTERVAL_MS = 5e3;
var DEFAULT_MAX_QUEUE_SIZE = 1e3;
var DEFAULT_BATCH_SIZE2 = 25;
var DEFAULT_MAX_RETRIES = 3;
var DEFAULT_EVENT_TYPE = "ai_request";
var NanoProfit = class {
  apiKey;
  baseUrl;
  maxRetries;
  defaultEventType;
  onError;
  queue;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  flushTimer = null;
  shutdownPromise = null;
  signalHandlers = [];
  pendingResponses = [];
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.maxRetries = config.maxRetries ?? DEFAULT_MAX_RETRIES;
    this.defaultEventType = config.defaultEventType ?? DEFAULT_EVENT_TYPE;
    this.onError = config.onError;
    this.queue = new EventQueue(
      config.maxQueueSize ?? DEFAULT_MAX_QUEUE_SIZE,
      config.batchSize ?? DEFAULT_BATCH_SIZE2
    );
    const intervalMs = config.flushIntervalMs ?? DEFAULT_FLUSH_INTERVAL_MS;
    this.flushTimer = setInterval(() => {
      void this.flush();
    }, intervalMs);
    if (this.flushTimer && typeof this.flushTimer.unref === "function") {
      this.flushTimer.unref();
    }
    if (config.handleSignals !== false && typeof process !== "undefined" && process.on) {
      for (const signal of ["SIGTERM", "SIGINT"]) {
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
   * Append a raw AI provider response for inclusion in the next
   * {@link track} call. Call this once per AI API call — if an agent
   * session makes three calls, call `addResponse` three times, then
   * call `track` once to attach them all to a single event.
   */
  addResponse(vendorName, rawResponse) {
    this.pendingResponses.push({ vendorName, rawResponse });
  }
  /**
   * Enqueue an event for delivery. This method is synchronous and will
   * never throw -- errors are silently swallowed so that tracking can
   * never crash the host application.
   *
   * All responses previously added via {@link addResponse} are drained
   * and attached to the event.
   */
  track(event) {
    try {
      const responses = this.pendingResponses;
      this.pendingResponses = [];
      const wire = toWireEvent(event, responses, this.defaultEventType);
      this.queue.enqueue(wire);
    } catch {
    }
  }
  /**
   * Flush all queued events to the API immediately.
   *
   * Each batch is sent independently via `Promise.allSettled`, so one
   * failing batch does not block the others.
   */
  async flush() {
    const batches = this.queue.drain();
    if (batches.length === 0) return;
    await Promise.allSettled(
      batches.map((batch) => this.sendBatch(batch))
    );
  }
  /**
   * Flush remaining events and stop the background timer.
   * Call this before your process exits.
   */
  async shutdown() {
    if (this.shutdownPromise !== null) {
      return this.shutdownPromise;
    }
    this.shutdownPromise = (async () => {
      if (this.flushTimer !== null) {
        clearInterval(this.flushTimer);
        this.flushTimer = null;
      }
      for (const { signal, handler } of this.signalHandlers) {
        process.removeListener(signal, handler);
      }
      this.signalHandlers = [];
      await this.flush();
    })();
    return this.shutdownPromise;
  }
  /** Send a single batch of events to the API with retry. */
  async sendBatch(events) {
    try {
      const response = await withRetry(
        async () => {
          const res = await fetch(`${this.baseUrl}/events`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${this.apiKey}`
            },
            body: JSON.stringify({ events })
          });
          if (res.status >= 500) {
            throw res;
          }
          return res;
        },
        { maxRetries: this.maxRetries }
      );
      if (response.status === 207) {
        const body = await response.json();
        const failed = body.results.filter((r) => r.status === "error");
        if (failed.length > 0) {
          this.reportError({
            message: `Batch partially failed: ${failed.length} of ${body.results.length} events had errors`,
            events
          });
        }
        return;
      }
      if (!response.ok) {
        let errorMessage = `Batch request failed with status ${response.status}`;
        try {
          const body = await response.json();
          if (body.error) errorMessage = body.error;
        } catch {
        }
        this.reportError({ message: errorMessage, events });
      }
    } catch (err) {
      this.reportError({
        message: "Batch request failed after retries",
        cause: err,
        events
      });
    }
  }
  /** Call the onError callback if configured, swallowing any errors from the callback. */
  reportError(error) {
    if (!this.onError) return;
    try {
      this.onError(error);
    } catch {
    }
  }
};
export {
  NanoProfit
};
