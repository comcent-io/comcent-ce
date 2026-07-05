# Comcent Community Edition

Run your own call center on a single Linux box. Bring your own SIP trunk
(Twilio, Telnyx, …), run one install script, and you get:

- Voice calls with browser-based dialers for agents
- Phone numbers, queues, call recording
- Call transcription, AI summaries, sentiment, semantic search
- A real-time AI voice bot
- Multi-tenant orgs, API keys, webhooks

> 🎬 **[Placeholder: under-a-minute video — from blank server to first call]**

## Minimum requirements

- A Linux host with a public IPv4 — Ubuntu 22.04+ / Debian 12+ (a $12/mo
  DigitalOcean droplet with 2 vCPU / 4 GB RAM is plenty)
- A domain name you can point at it
- A SIP trunk (Twilio, Telnyx, Bandwidth, …) if you want to make/receive
  real phone calls

## Install

### 1. Open the firewall

| Port | Protocol | What |
| --- | --- | --- |
| 80, 443 | TCP | HTTP / HTTPS — app + Let's Encrypt cert issuance |
| 5060 | UDP + TCP | SIP signaling |
| 5063 | TCP | SIP-over-WSS (browser dialer) |
| 19000–19100 | UDP | RTP media |

### 2. Point a domain at the host

Create a DNS **A record** (e.g. `cpaas.yourdomain.com`) pointing at the
host's public IPv4. Verify with `dig +short cpaas.yourdomain.com` before
continuing — the HTTPS certificate can't be issued until DNS resolves.

### 3. Run the installer

SSH into the host and run:

```bash
curl -fsSL https://raw.githubusercontent.com/comcent-io/comcent-ce/main/install.sh | bash
```

Takes ~30 seconds: installs Docker if missing, generates secrets, and
writes `docker-compose.yaml` + `.env` into `~/comcent-ce/`. It does **not**
start anything yet.

### 4. Fill in `.env`

```bash
nano ~/comcent-ce/.env
```

Search for `replaceMe` and fill every one in:

| Variable | What |
| --- | --- |
| `COMCENT_DOMAIN` | Your hostname from step 2 |
| `LETSENCRYPT_EMAIL` | Email for cert-renewal alerts |
| `SOURCE_EMAIL` | Sender for invites / password resets |
| `SMTP_URL` | `smtp://user:pass@host:port` — any provider works. Leave blank to disable email. |
| `STORAGE_BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | S3 (or S3-compatible) bucket for recordings & uploads |

Optional (leave blank to disable): `DEEPGRAM_API_KEY` (transcription,
voice bot), `OPENAI_API_KEY` (AI summaries, voice bot), Sentry DSNs.

### 5. Start it and claim your instance

```bash
cd ~/comcent-ce
docker compose up -d
```

First run pulls ≈800 MB of images and takes 5–10 minutes — that's normal.
The HTTPS certificate is issued about a minute after start.

Once up, the server prints a one-time **setup token** for creating the
first admin account. Grab it from the logs:

```bash
docker compose logs server | grep -A 10 "FIRST-RUN SETUP"
```

Then open `https://cpaas.yourdomain.com/setup`, enter the token along with
your name, email, password, and organization details. Done — you're the
super-admin.

(Lost the token? It's re-printed on every server start until claimed —
`docker compose restart server`, then grep again.)

### 6. Connect your SIP trunk

To make and receive real phone calls, open **Sip Trunk** in the sidebar,
hit **Create**, and fill in:

- **Name** — anything, e.g. `twilio`.
- **Provide Outbound Credentials** — tick only if your trunk uses
  username/password auth instead of IP-based auth.
- **SIP Proxy Address** — your provider's termination URI
  (e.g. `mytrunk.pstn.twilio.com`).
- **Inbound IPs to whitelist** — comma-separated IPs/domains your provider
  sends calls from.

On the trunk provider's side:

- Whitelist your host's public IP (`<YOUR_IP>/32`) — e.g. Twilio's
  **IP Access Control Lists** on an Elastic SIP Trunk.
- Point inbound calls (Origination) at `sip:<YOUR_DOMAIN>?transport=udp`.
- Route your phone number to the trunk, so calls to it reach this server.
  Every provider names this differently — on Twilio you assign the number
  to the Elastic SIP Trunk.

### 7. Add the number and build its inbound flow

Routing the number to the trunk on the provider's side isn't enough —
Comcent also needs to know the number and what to do with calls to it.
Open **Numbers** in the sidebar, hit **Add**, and fill in:

- **Name** — a friendly label.
- **Number (E.164)** — the number you bought, e.g. `+15551234567`.
- **SIP Trunk** — pick the trunk from step 6.
- **Allow Outbound if destination matches regex** — optional; restrict
  which destinations can be dialed from this number
  (e.g. `^\+1[0-9]{10}$` for US only).

Then build the **inbound flow** in the graph editor below — it decides
what happens when someone calls the number:

1. **Add step** and pick a node: **Queue** (route to agents in a queue —
   create one under **Queues** first), **Dial** / **DialGroup** (ring
   specific agents), **Menu** (IVR keypad menu), **Play** (play audio),
   **WeekTime** (business-hours branching), or **VoiceBot** (AI voice
   bot — needs the Deepgram/OpenAI keys from step 4).
2. Drag it into place.
3. Connect **Start** to the first node, and node outlets onward.

The simplest working flow is **Start → Dial** with **To** set to your own
username (the SIP username you chose during setup). Hit **Add** to save,
then call your number — it rings in your browser dialer.

## Upgrade

```bash
cd ~/comcent-ce
docker compose pull
docker compose up -d
```

Migrations run automatically on every server start.

## Troubleshooting

**Sign-up email never arrives.** `SMTP_URL` is unset or wrong. For one-off
testing you can run a [Mailhog](https://github.com/mailhog/MailHog)
container and set `SMTP_URL=smtp://mailhog:1025`.

**`https://...` shows a Traefik default cert.** Let's Encrypt couldn't
issue. Check `docker compose logs traefik` — usually DNS not yet pointing
at the host, or port 80 blocked.

**SIP trunk returns 403 on outbound.** Your host's public IP is not on the
trunk's IP allow list. Add `<your-IP>/32`.

**Browser dialer can't register.** The dialer connects to
`wss://<COMCENT_DOMAIN>:5063/sip-ws`. Confirm port 5063/TCP is open and
serving a valid Let's Encrypt cert:

```bash
echo | openssl s_client -connect cpaas.yourdomain.com:5063 -servername cpaas.yourdomain.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

## Enterprise Edition

Billing & metered usage, GDPR workflows, audit logs, SLA tracking,
outbound campaigns, executive summaries → <https://comcent.io/enterprise>

## License

AGPL-3.0. See `LICENSE`. Commercial licenses available — contact the
maintainer.

## Contributing

Want to hack on Comcent CE itself? See [CONTRIBUTING.md](CONTRIBUTING.md).
