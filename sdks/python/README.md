# NanoProfit Python SDK

Track AI usage and revenue with the NanoProfit platform.

## Installation

```bash
pip install nanoprofit
```

## Quick Start

```python
import asyncio
from nanoprofit import NanoProfit, Event, VendorCost, extract_openai

async def main():
    async with NanoProfit(api_key="np_your_api_key") as np:
        # Track an event with manual vendor costs
        np.track(Event(
            customer_external_id="cust_123",
            revenue_amount_in_cents=500,
            vendor_costs=[
                VendorCost(
                    vendor_name="openai",
                    ai_model_name="gpt-4o",
                    input_tokens=150,
                    output_tokens=350,
                )
            ],
        ))

        # Or extract costs from an OpenAI response automatically
        # response = await openai_client.chat.completions.create(...)
        # cost = extract_openai(response)
        # np.track(Event(
        #     customer_external_id="cust_123",
        #     revenue_amount_in_cents=500,
        #     vendor_costs=[cost],
        # ))

    # Events are automatically flushed when exiting the context manager.

asyncio.run(main())
```

## Provider Extractors

The SDK includes helper functions to extract `VendorCost` objects from
popular AI provider response objects:

```python
from nanoprofit import extract_openai, extract_anthropic, extract_google

cost = extract_openai(openai_response)
cost = extract_anthropic(anthropic_response)
cost = extract_google(gemini_response)
```

### Groq, Azure, and Bedrock

Groq and Azure OpenAI use the same response shape as OpenAI. AWS Bedrock
(with Anthropic models) uses the same shape as Anthropic. Pass a vendor name
override to attribute costs to the correct provider:

```python
# Groq (OpenAI-compatible)
cost = extract_openai(groq_response, vendor_name="groq")

# Azure OpenAI
cost = extract_openai(azure_response, vendor_name="azure")

# AWS Bedrock (Anthropic models)
cost = extract_anthropic(bedrock_response, vendor_name="bedrock")
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
