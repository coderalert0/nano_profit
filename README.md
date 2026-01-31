# NanoProfit

Real-time SaaS unit economics platform. Track AI vendor costs against customer revenue to monitor per-customer and per-feature margins.

## Setup

**Requirements:** Ruby 3.3.0, PostgreSQL, Node.js

```bash
bin/setup          # installs gems, creates DB, runs migrations, seeds
bin/dev            # starts Rails + SolidQueue via Procfile.dev
```

Demo login after seeding: `demo@example.com` / `password`

## Environment Variables

Copy `.env.example` and fill in values:

```bash
cp .env.example .env
```

| Variable | Required | Description |
|----------|----------|-------------|
| `STRIPE_SECRET_KEY` | For Stripe | Stripe API secret key |
| `STRIPE_CLIENT_ID` | For Stripe | Stripe Connect OAuth client ID |
| `STRIPE_WEBHOOK_SECRET` | For Stripe | Webhook signature verification secret |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Production | 32-char encryption key |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Production | 32-char encryption key |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Production | 32-char salt |

Dev defaults are baked in for encryption keys — **do not use them in production**.

## API

Single endpoint — `POST /api/v1/events`

**Auth:** Bearer token in `Authorization` header (get your API key from Settings).

**Rate limits:** 1,000 req/min per API key, 100 req/min per IP.

**Batch limit:** Max 100 events per request.

```bash
curl -X POST http://localhost:3000/api/v1/events \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "unique_request_token": "req_abc123",
      "customer_external_id": "cust_1",
      "event_type": "chat_completion",
      "revenue_amount_in_cents": 500,
      "vendor_responses": [{
        "vendor_name": "openai",
        "raw_response": {
          "ai_model_name": "gpt-4o",
          "input_tokens": 150,
          "output_tokens": 50
        }
      }]
    }]
  }'
```

Response includes `unique_request_token` for client-side idempotency.

## SDKs

- **TypeScript:** `npm install nanoprofit` — see `sdks/typescript/README.md`
- **Python:** `pip install nanoprofit` — see `sdks/python/README.md`

SDKs send only model name and token counts — no request/response content.

## Event Processing Pipeline

1. API receives event, validates vendor/model pairs, persists with `status: pending`
2. `ProcessEventJob` links customer (`find_or_create_by external_id`), transitions to `customer_linked`
3. `EventProcessor` looks up `VendorRate` per vendor cost, calculates `amount_in_cents` from token counts and rates, creates `CostEntry` records
4. Event transitions to `processed` with `total_cost_in_cents` and `margin_in_cents`

## Margin Calculation

- **Margin BPS** = `(margin * 10,000) / revenue` — basis points, so 5000 = 50%
- **Invoice proration** — Stripe invoices spanning a period boundary are prorated by overlapping days
- **Customer revenue** = event revenue + prorated Stripe invoice revenue
- **Alert triggers** — `CheckMarginAlertsJob` runs periodically per org, creates alerts when margin BPS drops below threshold or goes negative

## Tests

```bash
bin/rails test
```

## Deployment

Kamal config in `config/deploy.yml`. Set `SOLID_QUEUE_IN_PUMA=true` to run background jobs in the web process.
