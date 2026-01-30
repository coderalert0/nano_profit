# NanoProfit Python SDK

Track AI usage and revenue with the NanoProfit platform.

## Installation

```bash
pip install nanoprofit
```

## Quick Start

```python
import asyncio
from openai import AsyncOpenAI
from nanoprofit import NanoProfit, Event

async def main():
    openai = AsyncOpenAI()

    async with NanoProfit(api_key="np_your_api_key") as np:
        response = await openai.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": "Hello!"}],
        )

        np.add_response("openai", response)
        np.track(Event(
            customer_external_id="cust_123",
            revenue_amount_in_cents=500,
        ))

    # Events are automatically flushed when exiting the context manager.

asyncio.run(main())
```

## Tracking events

Append raw AI provider responses with `add_response()`, then call
`track()` to flush them into an event. The server extracts model names
and token counts automatically.

```python
# Single call
r1 = await openai.chat.completions.create(model="gpt-4o", messages=messages)
np.add_response("openai", r1)
np.track(Event(
    customer_external_id="cust_123",
    revenue_amount_in_cents=500,
))

# Agent session with multiple AI calls
r2 = await openai.chat.completions.create(model="gpt-4o", messages=messages)
np.add_response("openai", r2)

r3 = await anthropic.messages.create(model="claude-3-opus-20240229", messages=messages)
np.add_response("anthropic", r3)

r4 = await openai.chat.completions.create(model="gpt-4o", messages=messages)
np.add_response("openai", r4)

np.track(Event(
    customer_external_id="cust_456",
    revenue_amount_in_cents=1200,
))
```

For Groq, Azure OpenAI, or AWS Bedrock, use the same pattern — just set
the vendor name to `"groq"`, `"azure"`, or `"bedrock"` accordingly.

## Configuration

```python
NanoProfit(
    api_key="np_...",               # required
    base_url="https://...",         # default: https://app.nanoprofit.dev/api/v1
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
np = NanoProfit(api_key="np_your_api_key")
try:
    np.add_response("openai", response)
    np.track(event)
    await np.flush()   # flush immediately if needed
finally:
    await np.shutdown()
```

## License

MIT
