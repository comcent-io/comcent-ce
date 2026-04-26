#!/usr/bin/env bash
#
# Comcent CE installer — one-shot bootstrap for a fresh Linux host.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/comcent-io/comcent-ce/main/install.sh | bash
#
# What it does:
#   1. Verifies Docker + curl + openssl.
#   2. Detects the host's public IP.
#   3. Prompts for things we cannot guess (domain, email, SMTP, S3 creds, etc.).
#   4. Generates strong random secrets for DB / RabbitMQ / API / signing.
#   5. Downloads docker-compose.deploy.yaml as docker-compose.yaml.
#   6. Writes .env (mode 600) and starts the stack.
#
# Re-running on a host that already has .env is refused — move it aside first.

set -euo pipefail

BRANCH="${COMCENT_BRANCH:-main}"
REPO_RAW="https://raw.githubusercontent.com/comcent-io/comcent-ce/${BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/comcent-ce}"

# ---------- output helpers --------------------------------------------------
if [ -t 1 ]; then
  R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'; B=$'\033[1;34m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; N=""
fi
info()  { printf "%s[*]%s %s\n" "$B" "$N" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$G" "$N" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$Y" "$N" "$*"; }
die()   { printf "%s[x]%s %s\n" "$R" "$N" "$*" >&2; exit 1; }

# ---------- TTY for prompts when piped from curl ----------------------------
# When run as `curl … | bash`, stdin is the script bytes. Reattach to /dev/tty
# so `read` can prompt the operator.
if [ ! -t 0 ]; then
  if [ -e /dev/tty ]; then
    exec </dev/tty
  else
    die "Interactive prompts require a TTY. Run on a real shell, not a non-interactive runner."
  fi
fi

# ---------- prereqs ---------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Missing prerequisite: $1"; }
need docker
need curl
need openssl
docker compose version >/dev/null 2>&1 \
  || die "docker compose plugin required (Docker 24+). On Ubuntu: 'apt install docker-compose-plugin'."

# ---------- detect host's public IP -----------------------------------------
detect_ip() {
  curl -fsS --max-time 5 https://api.ipify.org   2>/dev/null \
    || curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
    || curl -fsS --max-time 5 https://icanhazip.com 2>/dev/null \
    || true
}
PUBLIC_IP_DETECTED="$(detect_ip)"

# ---------- random secret helpers -------------------------------------------
rand_url() { openssl rand -base64 48 | tr -d '\n+/=' | head -c 32; }
rand_b64() { openssl rand -base64 64 | tr -d '\n'; }
rand_hex() { openssl rand -hex 32; }

# ---------- prompt helpers --------------------------------------------------
prompt() {
  # prompt VAR LABEL [DEFAULT]
  local __var="$1" __label="$2" __default="${3:-}" __reply
  if [ -n "$__default" ]; then
    printf "  %s [%s]: " "$__label" "$__default"
  else
    printf "  %s: " "$__label"
  fi
  IFS= read -r __reply || __reply=""
  [ -z "$__reply" ] && __reply="$__default"
  printf -v "$__var" "%s" "$__reply"
}

prompt_required() {
  # prompt_required VAR LABEL
  local __var="$1" __label="$2" __reply=""
  while [ -z "$__reply" ]; do
    printf "  %s: " "$__label"
    IFS= read -r __reply || __reply=""
    [ -z "$__reply" ] && warn "value required, please enter something"
  done
  printf -v "$__var" "%s" "$__reply"
}

# ---------- banner ----------------------------------------------------------
cat <<BANNER

${B}=============================================================${N}
  Comcent CE — open-source contact center installer
${B}=============================================================${N}
Install dir: ${INSTALL_DIR}
BANNER

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
[ -f .env ] && die ".env already exists in $INSTALL_DIR — refusing to overwrite. Move it aside or set INSTALL_DIR=…"

echo
info "We need a few things to set this up. Press enter to accept defaults shown in [brackets]."
echo

# ---------- required identity -----------------------------------------------
prompt_required COMCENT_DOMAIN   "Public domain (DNS A record must already point here)"
prompt PUBLIC_IP                 "Public IP (used by FreeSWITCH for SDP)"          "$PUBLIC_IP_DETECTED"
[ -z "$PUBLIC_IP" ] && die "PUBLIC_IP could not be detected and you didn't supply one."

prompt LETSENCRYPT_EMAIL         "Let's Encrypt contact email"                     "admin@${COMCENT_DOMAIN}"
prompt SOURCE_EMAIL              "Outbound sender (invites, password resets)"      "Comcent <noreply@${COMCENT_DOMAIN}>"
prompt SIP_WSS_PORT              "SIP-over-WSS host port"                          "5063"

# ---------- SMTP ------------------------------------------------------------
echo
info "SMTP for transactional email. Leave empty to skip (invites/password resets won't be sent)."
prompt SMTP_URL "SMTP URL (smtp://user:pass@host:587)" ""

# ---------- object storage --------------------------------------------------
echo
info "Object storage for call recordings & uploads (S3 or any S3-compatible)."
prompt_required STORAGE_BUCKET_NAME    "Bucket name"
prompt          BUCKET_REGION          "Region"                                   "us-east-1"
prompt_required AWS_ACCESS_KEY_ID      "Access key id"
prompt_required AWS_SECRET_ACCESS_KEY  "Secret access key"
prompt          S3_ENDPOINT_URL        "S3 endpoint URL (blank = AWS S3)"          ""

# ---------- AI keys ---------------------------------------------------------
echo
info "Optional AI features (transcription, summaries, voice bot). Leave empty to skip."
prompt DEEPGRAM_API_KEY "Deepgram API key" ""
prompt OPENAI_API_KEY   "OpenAI API key"   ""

# ---------- generated secrets -----------------------------------------------
POSTGRES_PASSWORD="$(rand_url)"
RABBITMQ_PASSWORD="$(rand_url)"
INTERNAL_API_PASSWORD="$(rand_url)"
RPC_API_TOKEN="$(rand_url)"
SECRET_KEY_BASE="$(rand_b64)"
SIGNING_KEY="$(rand_hex)"

echo
info "Generated random secrets for postgres, rabbitmq, internal API, RPC token, and signing keys."

# ---------- download compose ------------------------------------------------
info "Downloading docker-compose.deploy.yaml from ${REPO_RAW}…"
curl -fsSL "${REPO_RAW}/docker-compose.deploy.yaml" -o docker-compose.yaml \
  || die "Failed to download docker-compose.deploy.yaml"
ok "docker-compose.yaml saved."

# ---------- write .env ------------------------------------------------------
info "Writing .env (mode 600)…"
umask 077
cat > .env <<EOF
# Comcent CE — generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Edit at will, but keep this file out of source control.

# --- identity / networking ---
COMCENT_DOMAIN=${COMCENT_DOMAIN}
PUBLIC_IP=${PUBLIC_IP}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
SOURCE_EMAIL=${SOURCE_EMAIL}
SIP_WSS_PORT=${SIP_WSS_PORT}

# --- image tags ---
COMCENT_VERSION=latest
FREESWITCH_VERSION=latest

# --- service-to-service ---
# SBC pinned IP from docker-compose. dial_utils derives sip:<IP>:5065 from this;
# the same value drives the FS ACL deny rule and the SBC RPC URL.
SBC_IP=172.20.0.10
# Docker subnet — added as ALLOW in FS's "private" ACL so internal peers stay local.
FS_LOCAL_NETWORK=172.20.0.0/16

INTERNAL_API_USERNAME=internal_api
INTERNAL_API_PASSWORD=${INTERNAL_API_PASSWORD}
RPC_API_TOKEN=${RPC_API_TOKEN}

# --- data services ---
POSTGRES_USER=comcent
POSTGRES_DB=comcent
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
RABBITMQ_USER=comcent
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}

# --- secrets ---
SECRET_KEY_BASE=${SECRET_KEY_BASE}
SIGNING_KEY=${SIGNING_KEY}

# --- storage ---
STORAGE_BUCKET_NAME=${STORAGE_BUCKET_NAME}
BUCKET_REGION=${BUCKET_REGION}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
S3_ENDPOINT_URL=${S3_ENDPOINT_URL}
S3_PROXY_DOWNLOADS=false

# --- auth ---
AUTH_PASSWORD_ENABLED=true
AUTH_OIDC_PROVIDERS_JSON={}

# --- email ---
SMTP_URL=${SMTP_URL}

# --- AI (optional) ---
DEEPGRAM_API_KEY=${DEEPGRAM_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}

# --- observability (optional) ---
SERVER_SENTRY_DSN=
PUBLIC_SENTRY_DSN=

# --- runtime ---
ENV=prod
CLUSTER_STRATEGY=gossip
EOF
chmod 600 .env
ok ".env written."

# ---------- bring stack up --------------------------------------------------
echo
info "Pulling images (one-time download, several hundred MB)…"
docker compose pull
echo
info "Starting stack…"
docker compose up -d

# ---------- summary ---------------------------------------------------------
cat <<EOF

${G}Comcent CE is starting.${N}

Working directory : ${INSTALL_DIR}
Domain            : https://${COMCENT_DOMAIN}
Public IP         : ${PUBLIC_IP}

Watch boot logs:
  cd ${INSTALL_DIR} && docker compose logs -f server

Open the app once Let's Encrypt finishes (1–2 min on first launch):
  https://${COMCENT_DOMAIN}

Required inbound firewall rules:
  TCP 80, 443                 — HTTP/HTTPS (cert issuance + app)
  UDP+TCP 5060                — SIP signaling
  TCP 5061                    — SIP/TLS
  TCP ${SIP_WSS_PORT}                    — SIP-over-WSS (browser dialer)
  UDP 19000-19100             — RTP media

Upgrade later:
  cd ${INSTALL_DIR} && docker compose pull && docker compose up -d

EOF
