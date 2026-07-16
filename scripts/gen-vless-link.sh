#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CONFIG_FILE="${ROOT_DIR}/xray/config.json"

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 <uuid> [label]" >&2
  exit 1
fi

USER_UUID="$1"
LABEL="${2:-employee}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Не найден .env — скопируйте .env.example и заполните VPS_IP" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -z "${VPS_IP:-}" ]]; then
  echo "VPS_IP не задан в .env" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Нужен jq: sudo apt install -y jq" >&2
  exit 1
fi

KEYS_FILE="${ROOT_DIR}/xray/.keys"
if [[ -f "$KEYS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$KEYS_FILE"
fi

PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
SHORT_ID="${REALITY_SHORT_ID:-}"
SNI="${REALITY_SNI:-www.cloudflare.com}"
PORT="${XRAY_PORT:-443}"
FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
FINGERPRINT="${VLESS_FINGERPRINT:-chrome}"

if [[ -z "$SHORT_ID" ]]; then
  SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")"
fi

if [[ -z "$PUBLIC_KEY" || -z "$SHORT_ID" || "$SHORT_ID" == "REPLACE_WITH_SHORT_ID" ]]; then
  echo "Не найдены Reality public key / short id. Запустите ./scripts/gen-reality.sh" >&2
  exit 1
fi

ENCODED_LABEL="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${LABEL}'))")"

LINK="vless://${USER_UUID}@${VPS_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=${FLOW}#${ENCODED_LABEL}"

echo "$LINK"
