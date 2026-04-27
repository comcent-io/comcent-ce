# Comcent Community Edition

Open-source CPaaS / contact-center platform. Elixir + Phoenix backend,
SvelteKit frontend, Go SBC, FreeSWITCH media, Postgres + Redis + RabbitMQ.

> Self-host the whole thing on a single Linux box with one `curl | bash`,
> bring your own SIP trunk, and you have a working call center with browser
> dialers, SIP trunks, queues, recording, transcription, and an AI voice
> bot.

## Try it locally (development)

For contributors and folks just kicking the tyres on a laptop:

```bash
git clone https://github.com/comcent-io/comcent-ce.git
cd comcent-ce
cp .env.example .env          # fill in secrets / API keys you have
docker compose up             # pulls prebuilt images and starts the stack
```

Open <http://localhost:6173>, sign up, and start playing.

## Deploy on a server (production)

The supported one-shot path. Tested on a fresh DigitalOcean droplet (Ubuntu
24.04, $12/mo 4 GB / 2 vCPU is plenty), works on any cloud / bare-metal
Linux host with a public IP.

### 1. Provision a Linux host

- Ubuntu 22.04+ or Debian 12+ (any modern distro with Docker support works)
- Public IPv4
- 2 vCPU / 4 GB RAM is the practical minimum
- Open inbound on the firewall (cloud or `ufw`):

  | Port | Protocol | What |
  |---|---|---|
  | 80, 443 | TCP | HTTP / HTTPS — app + Let's Encrypt cert issuance |
  | 5060 | UDP + TCP | SIP signaling |
  | 5063 | TCP | SIP-over-WSS (browser dialer) |
  | 19000–19100 | UDP | RTP media |

  On DigitalOcean, this is the **Cloud Firewall** under Networking → Firewalls.

### 2. Point a domain at the host

Pick a hostname like `cpaas.yourdomain.com`. Create a DNS **A record** that
points it at the droplet's public IPv4. Wait for it to propagate (usually
under a minute, sometimes a few minutes — check with `dig +short
cpaas.yourdomain.com`). Let's Encrypt's HTTP-01 challenge will hit this
hostname on `:80` and fail until DNS points correctly, so don't skip this.

### 3. (Optional) Set up your SIP trunk

If you're bringing your own trunk (Twilio, Telnyx, Bandwidth, your own
Kamailio, …) this is the time:

- **Twilio Elastic SIP Trunking** (the path we test against):
  - Create a Trunk if you don't have one — note the **Termination URI**
    (e.g. `mytrunk.pstn.twilio.com`).
  - **Authentication → IP Access Control Lists** → add the droplet's
    public IP (`<YOUR_IP>/32`). Both inbound and outbound traffic gate on
    this list.
  - **Origination → Origination URIs** → add
    `sip:<YOUR_DOMAIN>?transport=udp` (priority 10, weight 10) so calls to
    your numbers reach the droplet.
  - Buy a phone number and assign it to the trunk.
- **Other trunks**: same idea — whitelist the droplet IP on the trunk
  side, point inbound calls to the droplet's public hostname over UDP/5060.

You'll plug the trunk's termination FQDN into the dashboard once the stack
is up (Settings → SIP trunks → New).

### 4. Run the installer

SSH into the host as root (or any user that can run docker without sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/comcent-io/comcent-ce/main/install.sh | bash
```

What it does (≈30 seconds, no prompts):

- Installs Docker via `https://get.docker.com` if missing.
- Auto-detects your public IP.
- Generates strong random secrets for Postgres / RabbitMQ / API / signing
  keys.
- Downloads `docker-compose.yaml` and writes `.env` (mode 600) into
  `~/comcent-ce/`.
- Stops there. **Does not start the stack** — you edit `.env` first.

### 5. Edit `.env`

```bash
nano ~/comcent-ce/.env
```

Search for the string `replaceMe` and fill every one in:

| Variable | What |
|---|---|
| `COMCENT_DOMAIN` | The hostname from step 2 (e.g. `cpaas.yourdomain.com`) |
| `LETSENCRYPT_EMAIL` | Your email for cert-renewal alerts |
| `SOURCE_EMAIL` | Sender for invites / password resets |
| `SMTP_URL` | `smtp://user:pass@host:port` — any provider works (SES, SendGrid, Postmark, Mailgun, your own postfix). Leave blank to disable email entirely (you can still sign up the first user from the CLI). |
| `STORAGE_BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | S3 (or any S3-compatible) bucket for call recordings & uploads |

Optional, leave blank to disable:
- `DEEPGRAM_API_KEY` — real-time transcription, voice bot
- `OPENAI_API_KEY` — AI summaries, voice bot
- `SERVER_SENTRY_DSN`, `PUBLIC_SENTRY_DSN` — error tracking

Don't touch the auto-detected / generated section unless you know what
you're changing.

### 6. Start the stack

```bash
cd ~/comcent-ce
docker compose up -d
docker compose logs -f server
```

First run pulls ≈800 MB of images and takes 5–10 minutes — that's normal,
not stuck. Watch the server log until it stops scrolling and you see
`Phoenix endpoint listening`.

Let's Encrypt issues the cert about a minute after first start (HTTP-01
challenge against your DNS A record from step 2). Then open
<https://cpaas.yourdomain.com> and sign up.

### 7. Verify TLS on both surfaces

```bash
# HTTPS app
echo | openssl s_client -connect cpaas.yourdomain.com:443 -servername cpaas.yourdomain.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# SIP-over-WSS (used by browser dialer)
echo | openssl s_client -connect cpaas.yourdomain.com:5063 -servername cpaas.yourdomain.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Both should show `issuer= /C=US/O=Let's Encrypt/...` and a 90-day validity
window.

### 8. Upgrade later

```bash
cd ~/comcent-ce
docker compose pull
docker compose up -d
```

Migrations run on every server start automatically.

## What's in CE

- Voice calls, queues, phone numbers, SIP trunks, recording
- Multi-tenant orgs, password + OIDC auth
- API keys, webhooks
- Real-time voice bot (Deepgram + OpenAI)
- Call transcription, AI summaries, sentiment, semantic search

## What's in EE (<https://comcent.io/enterprise>)

- Billing, wallet, metered usage
- GDPR compliance workflows
- Audit logs, SLA tracking
- Outbound campaigns, daily executive summaries

## Troubleshooting

**Sign-up email never arrives.** `SMTP_URL` is unset or wrong. Either fix
it, or for one-off testing, run a Mailhog catcher:

```bash
docker run -d --name mailhog --network comcent-network -p 8025:8025 \
  mailhog/mailhog:latest
# in ~/comcent-ce/.env: SMTP_URL=smtp://mailhog:1025
docker compose up -d server     # reload env
# open http://<host>:8025 to see captured emails
```

> ⚠ Mailhog's UI has no auth. Either bind to `127.0.0.1:8025` and SSH-tunnel,
> or only run on a one-off test droplet you're going to destroy.

**`https://...` shows a Traefik default cert.** Let's Encrypt couldn't
issue. Check `docker compose logs traefik` for the ACME error — usually
DNS not yet pointing at the host, or port 80 blocked.

**SIP trunk returns 403 on outbound.** The droplet's public IP is not on
the trunk's IP Access Control List. Add `<your-droplet-IP>/32` to the
trunk's allow list.

**Browser dialer can't register.** The agent's WebRTC client connects to
`wss://<COMCENT_DOMAIN>:5063/sip-ws`. Confirm port 5063/TCP is open in your
firewall and that step 7 above showed a valid LE cert on that port.

## License

AGPL-3.0. See `LICENSE`. Commercial licenses available — contact the
maintainer.

Contributors: a CLA signature is required before your PR is merged. The
CLA bot will comment on your PR with a link to sign.
