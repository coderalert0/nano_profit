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

// src/client.ts
var DEFAULT_BASE_URL = "https://app.nanoprofit.dev/api/v1";
var DEFAULT_FLUSH_INTERVAL_MS = 5e3;
var DEFAULT_MAX_QUEUE_SIZE = 1e3;
var DEFAULT_BATCH_SIZE2 = 25;
var DEFAULT_MAX_RETRIES = 3;
var DEFAULT_EVENT_TYPE = "ai_request";
function toWireVendorCost(vc) {
  const wire = {
    vendor_name: vc.vendorName,
    ai_model_name: vc.aiModelName,
    input_tokens: vc.inputTokens,
    output_tokens: vc.outputTokens
  };
  if (vc.unitCount !== void 0) wire.unit_count = vc.unitCount;
  if (vc.unitType !== void 0) wire.unit_type = vc.unitType;
  if (vc.amountInCents !== void 0) wire.amount_in_cents = vc.amountInCents;
  return wire;
}
function toWireEvent(event, defaultEventType) {
  const wire = {
    customer_external_id: event.customerExternalId,
    revenue_amount_in_cents: event.revenueAmountInCents,
    vendor_costs: event.vendorCosts.map(toWireVendorCost),
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
var NanoProfit = class {
  apiKey;
  baseUrl;
  maxRetries;
  defaultEventType;
  queue;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  flushTimer = null;
  constructor(config) {
    this.apiKey = config.apiKey;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.maxRetries = config.maxRetries ?? DEFAULT_MAX_RETRIES;
    this.defaultEventType = config.defaultEventType ?? DEFAULT_EVENT_TYPE;
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
  }
  /**
   * Enqueue an event for delivery. This method is synchronous and will
   * never throw -- errors are silently swallowed so that tracking can
   * never crash the host application.
   */
  track(event) {
    try {
      const wire = toWireEvent(event, this.defaultEventType);
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
    if (this.flushTimer !== null) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
    await this.flush();
  }
  /** Send a single batch of events to the API with retry. */
  async sendBatch(events) {
    await Promise.allSettled(
      events.map(
        (wireEvent) => withRetry(
          async () => {
            const response = await fetch(`${this.baseUrl}/events`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${this.apiKey}`
              },
              body: JSON.stringify({ event: wireEvent })
            });
            if (!response.ok) {
              throw response;
            }
          },
          { maxRetries: this.maxRetries }
        )
      )
    );
  }
};

// src/providers/openai.ts
function extractOpenAI(response, vendorName) {
  return {
    vendorName: vendorName ?? "openai",
    aiModelName: response.model,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0
  };
}

// src/providers/anthropic.ts
function extractAnthropic(response, vendorName) {
  return {
    vendorName: vendorName ?? "anthropic",
    aiModelName: response.model,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0
  };
}

// src/providers/google.ts
function extractGoogle(response, vendorName) {
  return {
    vendorName: vendorName ?? "gemini",
    aiModelName: response.modelVersion ?? "",
    inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
    outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0
  };
}
export {
  NanoProfit,
  extractAnthropic,
  extractGoogle,
  extractOpenAI
};
