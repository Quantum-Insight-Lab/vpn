#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
MTG_CONFIG="${ROOT_DIR}/mtg/config.toml"
MTG_IMAGE="${MTG_IMAGE:-nineseconds/mtg:2}"
DOMAIN="${MTPROTO_DOMAIN:-cloudflare.com}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  DOMAIN="${MTPROTO_DOMAIN:-$DOMAIN}"
fi

: "${SOCKS_USER:?SOCKS_USER required in .env}"
: "${SOCKS_PASS:?SOCKS_PASS required in .env}"
: "${VPS_IP:?VPS_IP required in .env}"

echo "Генерация MTProto secret (FakeTLS, domain: $DOMAIN)..."
SECRET="$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$DOMAIN" | tr -d '\r\n')"
CF_IP="$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}')"

cat > "$MTG_CONFIG" <<EOT
secret = "$SECRET"
bind-to = "127.0.0.1:13128"
prefer-ip = "only-ipv4"
public-ipv4 = "${VPS_IP}"
concurrency = 8192
auto-update = false
tolerate-time-skewness = "24h"
allow-fallback-on-unknown-dc = true

[network]
dns = "https://1.1.1.1"
proxies = [
  "socks5://${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:12080"
]

[network.timeout]
tcp = "10s"
http = "15s"
idle = "5m"
handshake = "15s"

[domain-fronting]
host = "${CF_IP}"
port = 443

[defense.blocklist]
enabled = false

[defense.anti-replay]
enabled = false
EOT
chmod 644 "$MTG_CONFIG"

grep -q '^MTPROTO_SECRET=' "$ENV_FILE" && sed -i "s/^MTPROTO_SECRET=.*/MTPROTO_SECRET=$SECRET/" "$ENV_FILE" || echo "MTPROTO_SECRET=$SECRET" >> "$ENV_FILE"
grep -q '^MTPROTO_PORT=' "$ENV_FILE" && sed -i 's/^MTPROTO_PORT=.*/MTPROTO_PORT=443/' "$ENV_FILE" || echo 'MTPROTO_PORT=443' >> "$ENV_FILE"
grep -q '^MTPROTO_DOMAIN=' "$ENV_FILE" && sed -i "s/^MTPROTO_DOMAIN=.*/MTPROTO_DOMAIN=$DOMAIN/" "$ENV_FILE" || echo "MTPROTO_DOMAIN=$DOMAIN" >> "$ENV_FILE"

echo
echo "MTProto (без VLESS), порт 443:"
echo "  https://t.me/proxy?server=${VPS_IP}&port=443&secret=${SECRET}"
echo "  tg://proxy?server=${VPS_IP}&port=443&secret=${SECRET}"

if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps --status running mtg 2>/dev/null | grep -q mtg; then
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d --force-recreate mtg
  echo "mtg перезапущен."
fi
