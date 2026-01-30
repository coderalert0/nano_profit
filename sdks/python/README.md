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
from nanoprofit import NanoProfit, Event, VendorCost

async def main():
    openai = AsyncOpenAI()

    async with NanoProfit(api_key="np_your_api_key") as np:
        response = await openai.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": "Hello!"}],
        )

        np.track(Event(
            customer_external_id="cust_123",
            revenue_amount_in_cents=500,
            vendor_costs=[
                VendorCost(
                    vendor_name="openai",
                    ai_model_name=response.model,
                    input_tokens=response.usage.prompt_tokens,
                    output_tokens=response.usage.completion_tokens,
                )
            ],
        ))

    # Events are automatically flushed when exiting the context manager.

asyncio.run(main())
```

## Tracking events

Pass vendor cost data directly from your AI provider's response:

```python
# OpenAI
np.track(Event(
    customer_external_id="cust_123",
    revenue_amount_in_cents=500,
    vendor_costs=[
        VendorCost(
            vendor_name="openai",
            ai_model_name=response.model,
            input_tokens=response.usage.prompt_tokens,
            output_tokens=response.usage.completion_tokens,
        )
    ],
))

# Anthropic
np.track(Event(
    customer_external_id="cust_123",
    revenue_amount_in_cents=500,
    vendor_costs=[
        VendorCost(
            vendor_name="anthropic",
            ai_model_name=response.model,
            input_tokens=response.usage.input_tokens,
            output_tokens=response.usage.output_tokens,
        )
    ],
))
```

For Groq, Azure OpenAI, or AWS Bedrock, use the same fields — just set
`vendor_name` to `"groq"`, `"azure"`, or `"bedrock"` accordingly.

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
    np.track(event)
    await np.flush()   # flush immediately if needed
finally:
    await np.shutdown()
```

## License

MIT
