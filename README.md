# Comcent Community Edition

Open-source CPaaS (call center platform). Elixir + Phoenix backend,
SvelteKit frontend, Go SBC, FreeSWITCH media, Postgres + Redis + RabbitMQ.

## Quick start

```bash
cp .env.example .env         # fill in secrets
docker compose up            # pulls prebuilt images
```

Open http://localhost:5174 and sign up.

## What's in CE

- Voice calls, queues, phone numbers, SIP trunks, recording
- Multi-tenant orgs, password + OIDC auth
- API keys, webhooks
- Real-time voice bot (Deepgram + OpenAI)
- Call transcription, AI summaries, sentiment, semantic search

## What's in EE (comcent.io/enterprise)

- Billing, wallet, metered usage
- GDPR compliance workflows
- Audit logs, SLA tracking
- Outbound campaigns, daily executive summaries

## License

AGPL-3.0. See `LICENSE`. Commercial licenses available — contact the maintainer.

Contributors: a CLA signature is required before your PR is merged. The
CLA bot will comment on your PR with a link to sign.
