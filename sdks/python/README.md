# MarginDash Python SDK

Track AI usage and revenue with the MarginDash platform.

## Installation

```bash
pip install margindash
```

## Quick Start

```python
import asyncio
from openai import AsyncOpenAI
from margindash import MarginDash, Event, Usage

async def main():
    openai = AsyncOpenAI()

    async with MarginDash(api_key="np_your_api_key") as np:
        response = await openai.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": "Hello!"}],
        )

        np.add_usage("openai", Usage(
            model=response.model,
            input_tokens=response.usage.prompt_tokens,
            output_tokens=response.usage.completion_tokens,
        ))
        np.track(Event(
            customer_external_id="cust_123",
            revenue_amount_in_cents=500,
        ))

    # Events are automatically flushed when exiting the context manager.

asyncio.run(main())
```

Only the model name and token counts are sent to MarginDash — no request
or response content ever leaves your infrastructure.

## Tracking events

Record usage from each AI API call with `add_usage()`, then call
`track()` to flush them into an event.

```python
# Single call
r1 = await openai.chat.completions.create(model="gpt-4o", messages=messages)
np.add_usage("openai", Usage(
    model=r1.model,
    input_tokens=r1.usage.prompt_tokens,
    output_tokens=r1.usage.completion_tokens,
))
np.track(Event(
    customer_external_id="cust_123",
    revenue_amount_in_cents=500,
))

# Agent session with multiple AI calls
r2 = await openai.chat.completions.create(model="gpt-4o", messages=messages)
np.add_usage("openai", Usage(
    model=r2.model,
    input_tokens=r2.usage.prompt_tokens,
    output_tokens=r2.usage.completion_tokens,
))

r3 = await anthropic.messages.create(model="claude-3-opus-20240229", messages=messages)
np.add_usage("anthropic", Usage(
    model=r3.model,
    input_tokens=r3.usage.input_tokens,
    output_tokens=r3.usage.output_tokens,
))

r4 = await google.generate_content(model="gemini-1.5-pro", contents=contents)
np.add_usage("google", Usage(
    model="gemini-1.5-pro",
    input_tokens=r4.usage_metadata.prompt_token_count,
    output_tokens=r4.usage_metadata.candidates_token_count,
))

np.track(Event(
    customer_external_id="cust_456",
    revenue_amount_in_cents=1200,
))
```

### Supported vendors

Any vendor name works with `add_usage()` as long as you have a matching
vendor rate configured in MarginDash. Common names: `openai`, `anthropic`,
`google`, `groq`, `azure`, `bedrock`, `together`, `fireworks`, `mistral`.

## Configuration

```python
MarginDash(
    api_key="np_...",               # required
    base_url="https://...",         # default: https://margindash.com/api/v1
    flush_interval=5.0,             # default: 5.0 seconds
    max_queue_size=1000,            # default: 1000
    batch_size=25,                  # default: 25
    max_retries=3,                  # default: 3
    default_event_type="ai_request",# default: "ai_request"
    on_error=lambda err: print(err.message),  # optional error callback
)
```

## Manual Flush and Shutdown

If you are not using the async context manager, call `shutdown()` before
your application exits to ensure all buffered events are sent:

```python
np = MarginDash(api_key="np_your_api_key")
try:
    np.add_usage("openai", Usage(
        model="gpt-4o",
        input_tokens=100,
        output_tokens=50,
    ))
    np.track(event)
    await np.flush()   # flush immediately if needed
finally:
    await np.shutdown()
```

## License

MIT
