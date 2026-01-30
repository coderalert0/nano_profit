# nanoprofit

Track AI usage and revenue with [NanoProfit](https://nanoprofit.dev).

## Install

```bash
npm install nanoprofit
```

## Quick start

```typescript
import { NanoProfit, extractOpenAI } from "nanoprofit";
import OpenAI from "openai";

const np = new NanoProfit({ apiKey: process.env.NANOPROFIT_API_KEY! });
const openai = new OpenAI();

const response = await openai.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "Hello!" }],
});

np.track({
  customerExternalId: "cust_123",
  revenueAmountInCents: 5,
  vendorCosts: [extractOpenAI(response)],
});

// Before your process exits:
await np.shutdown();
```

## Configuration

```typescript
const np = new NanoProfit({
  apiKey: "np_...",          // required
  baseUrl: "https://...",    // default: https://app.nanoprofit.dev/api/v1
  flushIntervalMs: 5000,     // default: 5000
  maxQueueSize: 1000,        // default: 1000
  batchSize: 25,             // default: 25
  maxRetries: 3,             // default: 3
  defaultEventType: "ai_request", // default: "ai_request"
});
```

## Provider helpers

Extract token usage from popular AI provider responses:

```typescript
import { extractOpenAI, extractAnthropic, extractGoogle } from "nanoprofit";

// OpenAI
const openaiCost = extractOpenAI(openaiResponse);

// Anthropic
const anthropicCost = extractAnthropic(anthropicResponse);

// Google Gemini
const googleCost = extractGoogle(geminiResponse);
```

### Groq, Azure, and Bedrock

Groq and Azure OpenAI use the same response shape as OpenAI. AWS Bedrock
(with Anthropic models) uses the same shape as Anthropic. Pass a vendor name
override to attribute costs to the correct provider:

```typescript
// Groq (OpenAI-compatible)
const groqCost = extractOpenAI(groqResponse, "groq");

// Azure OpenAI
const azureCost = extractOpenAI(azureResponse, "azure");

// AWS Bedrock (Anthropic models)
const bedrockCost = extractAnthropic(bedrockResponse, "bedrock");
```

## License

MIT
