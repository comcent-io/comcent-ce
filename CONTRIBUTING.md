# Contributing to Comcent CE

Thanks for your interest in contributing!

## Tech stack

- **Backend**: Elixir + Phoenix
- **Frontend**: SvelteKit
- **SBC**: Go
- **Media**: FreeSWITCH
- **Infra**: Postgres, Redis, RabbitMQ

## Run locally (development)

```bash
git clone https://github.com/comcent-io/comcent-ce.git
cd comcent-ce
cp .env.example .env          # fill in secrets / API keys you have
docker compose up             # pulls prebuilt images and starts the stack
```

Open <http://localhost:6173>, sign up, and start playing.

## CLA

A CLA signature is required before your PR is merged. The CLA bot will
comment on your PR with a link to sign.

## License

Contributions are accepted under the project's AGPL-3.0 license. See
`LICENSE`.
