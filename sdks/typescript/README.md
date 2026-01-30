# nanoprofit

Track AI usage and revenue with [NanoProfit](https://nanoprofit.dev).

## Install

```bash
npm install nanoprofit
```

## Quick start

```typescript
import { NanoProfit } from "nanoprofit";
import OpenAI from "openai";

const np = new NanoProfit({ apiKey: process.env.NANOPROFIT_API_KEY! });
const openai = new OpenAI();

const response = await openai.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "Hello!" }],
});

np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 500,
  vendorCosts: [{
    vendorName: "openai",
    aiModelName: response.model,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
  }],
});

// Before your process exits:
await np.shutdown();
```

## Configuration

```typescript
const np = new NanoProfit({
  apiKey: "np_...",               // required
  baseUrl: "https://...",         // default: https://app.nanoprofit.dev/api/v1
  flushIntervalMs: 5000,          // default: 5000
  maxQueueSize: 1000,             // default: 1000
  batchSize: 25,                  // default: 25
  maxRetries: 3,                  // default: 3
  defaultEventType: "ai_request", // default: "ai_request"
  handleSignals: true,            // default: true — auto-flush on SIGTERM/SIGINT
  onError: (err) => {             // optional error callback
    console.error(err.message);
  },
});
```

## Tracking events

Pass vendor cost data directly from your AI provider's response:

```typescript
// OpenAI
np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 500,
  vendorCosts: [{
    vendorName: "openai",
    aiModelName: response.model,
    inputTokens: response.usage?.prompt_tokens ?? 0,
    outputTokens: response.usage?.completion_tokens ?? 0,
  }],
});

// Anthropic
np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 500,
  vendorCosts: [{
    vendorName: "anthropic",
    aiModelName: response.model,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
  }],
});
```

For Groq, Azure OpenAI, or AWS Bedrock, use the same fields — just set
`vendorName` to `"groq"`, `"azure"`, or `"bedrock"` accordingly.

## Shutdown

The SDK automatically flushes pending events on `SIGTERM` and `SIGINT`.
You can disable this with `handleSignals: false` and call `shutdown()`
manually:

```typescript
await np.shutdown();
```

## License

MIT
