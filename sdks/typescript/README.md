# margindash

Track AI usage and revenue with [MarginDash](https://margindash.dev).

## Install

```bash
npm install margindash
```

## Quick start

```typescript
import { MarginDash } from "margindash";
import OpenAI from "openai";

const np = new MarginDash({ apiKey: process.env.MARGIN_DASH_API_KEY! });
const openai = new OpenAI();

const response = await openai.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "Hello!" }],
});

np.addUsage("openai", {
  model: response.model,
  inputTokens: response.usage!.prompt_tokens,
  outputTokens: response.usage!.completion_tokens,
});
np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 500,
});

// Before your process exits:
await np.shutdown();
```

Only the model name and token counts are sent to MarginDash — no request
or response content ever leaves your infrastructure.

## Configuration

```typescript
const np = new MarginDash({
  apiKey: "np_...",               // required
  baseUrl: "https://...",         // default: https://margindash.com/api/v1
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

Record usage from each AI API call with `addUsage()`, then call
`track()` to flush them into an event.

```typescript
// Single call
const r1 = await openai.chat.completions.create({ model: "gpt-4o", messages });
np.addUsage("openai", {
  model: r1.model,
  inputTokens: r1.usage!.prompt_tokens,
  outputTokens: r1.usage!.completion_tokens,
});
np.track({ customerExternalId: "cust_123", revenueAmountInCents: 500 });

// Agent session with multiple AI calls
const r2 = await openai.chat.completions.create({ model: "gpt-4o", messages });
np.addUsage("openai", {
  model: r2.model,
  inputTokens: r2.usage!.prompt_tokens,
  outputTokens: r2.usage!.completion_tokens,
});

const r3 = await anthropic.messages.create({ model: "claude-3-opus-20240229", messages });
np.addUsage("anthropic", {
  model: r3.model,
  inputTokens: r3.usage.input_tokens,
  outputTokens: r3.usage.output_tokens,
});

const r4 = await google.generateContent({ model: "gemini-1.5-pro", contents });
np.addUsage("google", {
  model: "gemini-1.5-pro",
  inputTokens: r4.usageMetadata.promptTokenCount,
  outputTokens: r4.usageMetadata.candidatesTokenCount,
});

np.track({ customerExternalId: "cust_456", revenueAmountInCents: 1200 });
```

### Supported vendors

Any vendor name works with `addUsage()` as long as you have a matching
vendor rate configured in MarginDash. Common names: `openai`, `anthropic`,
`google`, `groq`, `azure`, `bedrock`, `together`, `fireworks`, `mistral`.

## Shutdown

The SDK automatically flushes pending events on `SIGTERM` and `SIGINT`.
You can disable this with `handleSignals: false` and call `shutdown()`
manually:

```typescript
await np.shutdown();
```

## License

MIT
