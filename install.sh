#!/usr/bin/env bash
#
# Comcent CE installer — non-interactive bootstrap for a fresh Linux host.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/comcent-io/comcent-ce/main/install.sh | bash
#
# Steps (each prints status):
#   1. Verify curl + openssl, install Docker (via get.docker.com) if missing.
#   2. Verify the docker compose plugin.
#   3. Detect the host's public IP.
#   4. Generate strong random secrets for postgres / rabbit / API / signing.
#   5. Pick the version (the latest release) and download its
#      docker-compose.deploy.yaml.
#   6. Write .env (mode 600) — known values filled in, unknowns marked replaceMe,
#      COMCENT_VERSION pinned to that version.
#   7. Print clear next-steps the operator must do (edit .env, then docker compose up).
#
# Installs are pinned to the latest GitHub Release, not to main: a change
# merged to main reaches new installs only once it has been released.
# To install something else (e.g. to test an unreleased build before a
# release, see RELEASING.md):
#   curl -fsSL …/install.sh | COMCENT_VERSION=sha-1a2b3c4 bash
# COMCENT_VERSION is an image tag (a release like v2026.10.06, or main /
# sha-<7> for a tested main build); the compose file then comes from main
# unless COMCENT_BRANCH names another branch or tag.
#
# This script does NOT pull images or start the stack. The operator runs
# `docker compose up -d` themselves once .env has been edited.
#
# Re-running on a host that already has .env is refused — move it aside first.

set -euo pipefail

REPO="comcent-io/comcent-ce"
INSTALL_DIR="${INSTALL_DIR:-$HOME/comcent-ce}"

# ---------- output helpers --------------------------------------------------
if [ -t 1 ]; then
  R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; B=$'\033[1;34m'; D=$'\033[2m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi

TOTAL_STEPS=6
__step=0
step()  { __step=$((__step + 1)); printf "\n%s[%d/%d]%s %s\n" "$B" "$__step" "$TOTAL_STEPS" "$N" "$*"; }
ok()    { printf "  %s✓%s %s\n" "$G" "$N" "$*"; }
note()  { printf "  %s%s%s\n"   "$D" "$*" "$N"; }
warn()  { printf "  %s!%s %s\n" "$Y" "$N" "$*"; }
die()   { printf "\n%s✗%s %s\n" "$R" "$N" "$*" >&2; exit 1; }

# ---------- random secret helpers -------------------------------------------
rand_url() { openssl rand -base64 48 | tr -d '\n+/=' | head -c 32; }
rand_b64() { openssl rand -base64 64 | tr -d '\n'; }
rand_hex() { openssl rand -hex 32; }

# ---------- version helpers -------------------------------------------------
# The tag of the latest GitHub Release, or nothing when there is none (or
# GitHub can't be reached).
latest_release() {
  curl -fsSL --max-time 15 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
    || true
}

# Where docker-compose.deploy.yaml comes from for a version: the release's own
# tag, or main for an unreleased build, unless COMCENT_BRANCH says otherwise.
compose_ref() {
  if [ -n "${COMCENT_BRANCH:-}" ]; then
    echo "$COMCENT_BRANCH"
  elif [[ "$1" =~ ^v[0-9] ]]; then
    echo "$1"
  else
    echo "main"
  fi
}

# ---------- banner ----------------------------------------------------------
cat <<BANNER

${B}Comcent CE — installer${N}
${D}Target dir: ${INSTALL_DIR}${N}
BANNER

# ---------- step 1: prereqs + docker ---------------------------------------
step "Verifying prerequisites"

command -v curl    >/dev/null 2>&1 || die "curl not found — install it first (apt-get install curl)"
ok "curl present"
command -v openssl >/dev/null 2>&1 || die "openssl not found — install it first (apt-get install openssl)"
ok "openssl present"

if command -v docker >/dev/null 2>&1; then
  ok "docker present ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))"
else
  note "docker not found — installing via the official convenience script (https://get.docker.com)…"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh \
    || die "Failed to download get.docker.com script"
  sh /tmp/get-docker.sh >/tmp/get-docker.log 2>&1 \
    || { tail -20 /tmp/get-docker.log; die "Docker install failed — see /tmp/get-docker.log"; }
  rm -f /tmp/get-docker.sh
  ok "docker installed ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))"
fi

# ---------- step 2: compose plugin -----------------------------------------
step "Verifying docker compose plugin"

if docker compose version >/dev/null 2>&1; then
  ok "docker compose plugin present ($(docker compose version --short 2>/dev/null))"
else
  die "docker compose plugin missing. On Debian/Ubuntu: apt install docker-compose-plugin"
fi

# ---------- step 3: detect public IP ---------------------------------------
step "Detecting public IP"

detect_ip() {
  curl -fsS --max-time 5 https://api.ipify.org   2>/dev/null \
    || curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
    || curl -fsS --max-time 5 https://icanhazip.com 2>/dev/null \
    || true
}
PUBLIC_IP="$(detect_ip)"
if [ -n "$PUBLIC_IP" ]; then
  ok "public IP: ${PUBLIC_IP}"
else
  PUBLIC_IP="replaceMe"
  warn "could not auto-detect — set PUBLIC_IP in .env manually"
fi

# ---------- step 4: generate secrets ---------------------------------------
step "Generating random secrets"

POSTGRES_PASSWORD="$(rand_url)"
RABBITMQ_PASSWORD="$(rand_url)"
INTERNAL_API_PASSWORD="$(rand_url)"
RPC_API_TOKEN="$(rand_url)"
SECRET_KEY_BASE="$(rand_b64)"
SIGNING_KEY="$(rand_hex)"
ok "POSTGRES_PASSWORD, RABBITMQ_PASSWORD, INTERNAL_API_PASSWORD, RPC_API_TOKEN, SECRET_KEY_BASE, SIGNING_KEY"

# ---------- step 5: pick the version, prepare working dir, download compose -
step "Picking the version and downloading its compose file"

if [ -n "${COMCENT_VERSION:-}" ]; then
  ok "version: ${COMCENT_VERSION} (set by COMCENT_VERSION)"
  [[ "$COMCENT_VERSION" =~ ^v[0-9] ]] || warn "${COMCENT_VERSION} is not a release — use it for testing, not production"
else
  COMCENT_VERSION="$(latest_release)"
  [ -n "$COMCENT_VERSION" ] || die "Could not find a Comcent CE release at https://github.com/${REPO}/releases.
  Check this host can reach api.github.com. If no release has been published
  yet, an unreleased build can be installed for testing with
  COMCENT_VERSION=main (see RELEASING.md)."
  ok "version: ${COMCENT_VERSION} (latest release)"
fi
REPO_RAW="https://raw.githubusercontent.com/${REPO}/$(compose_ref "$COMCENT_VERSION")"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
[ -f .env ] && die ".env already exists in $INSTALL_DIR — move it aside or set INSTALL_DIR=…"
ok "working directory: ${INSTALL_DIR}"

curl -fsSL "${REPO_RAW}/docker-compose.deploy.yaml" -o docker-compose.yaml \
  || die "Failed to download docker-compose.deploy.yaml from ${REPO_RAW}"
ok "docker-compose.yaml downloaded ($(compose_ref "$COMCENT_VERSION"))"

# ---------- step 6: write .env ---------------------------------------------
step "Writing .env"

umask 077
cat > .env <<EOF
# Comcent CE — generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# Search for "replaceMe" — every occurrence MUST be replaced before you
# start the stack. Generated values (passwords / signing keys / IPs) are
# already filled in. Keep this file out of source control.

# =============================================================================
# REQUIRED — replace every "replaceMe" below
# =============================================================================

# Public domain — DNS A record for this name MUST point at PUBLIC_IP.
COMCENT_DOMAIN=replaceMe

# Email used by Let's Encrypt for cert renewal notifications.
LETSENCRYPT_EMAIL=replaceMe

# "From" address on outbound transactional email (invites, password resets).
SOURCE_EMAIL=Comcent <noreply@replaceMe>

# SMTP for outbound email. Format: smtp://user:pass@host:port
# Anything works (SES, SendGrid, Postmark, Mailgun, your own postfix).
SMTP_URL=replaceMe

# S3 (or any S3-compatible) bucket for call recordings + uploads.
STORAGE_BUCKET_NAME=replaceMe
AWS_ACCESS_KEY_ID=replaceMe
AWS_SECRET_ACCESS_KEY=replaceMe

# =============================================================================
# OPTIONAL — leave blank to disable, fill in to enable
# =============================================================================

# AI features (real-time transcription, summarization, voice bot)
DEEPGRAM_API_KEY=
OPENAI_API_KEY=

# Sentry observability
SERVER_SENTRY_DSN=
PUBLIC_SENTRY_DSN=

# OIDC SSO; default ({}) keeps password login only.
# Example: {"google":{"client_id":"…","client_secret":"…","issuer":"https://accounts.google.com"}}
AUTH_OIDC_PROVIDERS_JSON={}

# =============================================================================
# AUTO-DETECTED / GENERATED — usually no need to touch
# =============================================================================

PUBLIC_IP=${PUBLIC_IP}
SIP_WSS_PORT=5063
BUCKET_REGION=us-east-1
S3_ENDPOINT_URL=
S3_PROXY_DOWNLOADS=false
AUTH_PASSWORD_ENABLED=true

# Comcent image version, pinned to the release this was installed from.
# To upgrade: set the new release (https://github.com/${REPO}/releases),
# then docker compose pull && docker compose up -d.
COMCENT_VERSION=${COMCENT_VERSION}
FREESWITCH_VERSION=latest

# In-tree Go SBC pinned IP (matches docker-compose.yaml). Used by:
#   - dial_utils → fs_path=sip:<IP>:5065
#   - FreeSWITCH ACL deny rule (so SBC traffic uses ext-rtp-ip in SDP)
#   - SBC RPC URL (http://<IP>/rpc)
SBC_IP=172.20.0.10
# Docker subnet — added as ALLOW in FS's "private" ACL so internal peers
# stay local (rtp-ip used in SDP rather than ext-rtp-ip).
FS_LOCAL_NETWORK=172.20.0.0/16

INTERNAL_API_USERNAME=internal_api
INTERNAL_API_PASSWORD=${INTERNAL_API_PASSWORD}
RPC_API_TOKEN=${RPC_API_TOKEN}

POSTGRES_USER=comcent
POSTGRES_DB=comcent
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
RABBITMQ_USER=comcent
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}

SECRET_KEY_BASE=${SECRET_KEY_BASE}
SIGNING_KEY=${SIGNING_KEY}

ENV=prod
CLUSTER_STRATEGY=gossip
EOF
chmod 600 .env
ok ".env written (mode 600)"

# ---------- final instructions ---------------------------------------------
cat <<EOF

${G}Setup complete.${N}  Three manual steps remain — read carefully:

${B}1) Edit .env${N}
     ${INSTALL_DIR}/.env

   Search for the string ${Y}replaceMe${N} and fill every one in:
     • COMCENT_DOMAIN          (e.g. voice.example.com — DNS A → ${PUBLIC_IP})
     • LETSENCRYPT_EMAIL       (your address for cert-renewal alerts)
     • SOURCE_EMAIL            (sender for invites; the host part will likely match COMCENT_DOMAIN)
     • SMTP_URL                (smtp://user:pass@host:587 — any provider)
     • STORAGE_BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

${B}2) Start the stack${N}
     cd ${INSTALL_DIR}
     docker compose up -d

   First run pulls ~800MB of images and takes 5–10 minutes — that is
   normal, not stuck. Then watch the boot:
     docker compose logs -f server

   Once Let's Encrypt issues (≈1 min after first start), open:
     https://<COMCENT_DOMAIN>

${B}3) Claim your instance${N}
   Once up, the server prints a one-time setup token. Grab it from
   the logs:
     docker compose logs server | grep -A 10 "FIRST-RUN SETUP"

   Then open https://<COMCENT_DOMAIN>/setup and create the first
   admin account. (Lost it? The token is re-printed on every server
   start until claimed.)

${B}Required inbound firewall rules${N}
   TCP    80, 443         HTTP/HTTPS (cert issuance + app)
   UDP+TCP 5060           SIP signaling
   TCP    5063            SIP-over-WSS (browser dialer)
   UDP    19000-19100     RTP media

${B}Upgrade later${N}
   This install is pinned to ${COMCENT_VERSION}. To move to a newer release
   (https://github.com/${REPO}/releases), set COMCENT_VERSION in .env, then:
     cd ${INSTALL_DIR} && docker compose pull && docker compose up -d

EOF
