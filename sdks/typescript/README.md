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

np.addResponse("openai", response);
np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 500,
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

Append raw AI provider responses with `addResponse()`, then call
`track()` to flush them into an event. The server extracts model names
and token counts automatically.

```typescript
// Single call
const r1 = await openai.chat.completions.create({ model: "gpt-4o", messages });
np.addResponse("openai", r1);
np.track({ customerExternalId: "cust_123", revenueAmountInCents: 500 });

// Agent session with multiple AI calls
const r2 = await openai.chat.completions.create({ model: "gpt-4o", messages });
np.addResponse("openai", r2);

const r3 = await anthropic.messages.create({ model: "claude-3-opus-20240229", messages });
np.addResponse("anthropic", r3);

const r4 = await openai.chat.completions.create({ model: "gpt-4o", messages });
np.addResponse("openai", r4);

np.track({ customerExternalId: "cust_456", revenueAmountInCents: 1200 });
```

For Groq, Azure OpenAI, or AWS Bedrock, use the same pattern — just set
the vendor name to `"groq"`, `"azure"`, or `"bedrock"` accordingly.

## Shutdown

The SDK automatically flushes pending events on `SIGTERM` and `SIGINT`.
You can disable this with `handleSignals: false` and call `shutdown()`
manually:

```typescript
await np.shutdown();
```

## License

MIT
