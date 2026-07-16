#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CONFIG_FILE="${ROOT_DIR}/xray/config.json"
KEYS_FILE="${ROOT_DIR}/xray/.keys"
XRAY_IMAGE="${XRAY_IMAGE:-ghcr.io/xtls/xray-core:latest}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Не найден $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Нужен jq: sudo apt install -y jq" >&2
  exit 1
fi

echo "Генерация Reality-ключей через Xray..."
KEYS_OUTPUT="$(docker run --rm "$XRAY_IMAGE" x25519)"

parse_key() {
  local pattern="$1"
  echo "$KEYS_OUTPUT" | awk -F': ' -v p="$pattern" '$1 ~ p {print $2; exit}' | tr -d '\r\n'
}

PRIVATE_KEY="$(parse_key 'Private key|PrivateKey')"
PUBLIC_KEY="$(parse_key 'Public key|PublicKey|Password')"

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "Не удалось распарсить вывод x25519:" >&2
  echo "$KEYS_OUTPUT" >&2
  exit 1
fi

SHORT_ID="$(openssl rand -hex 8)"

mkdir -p "$(dirname "$KEYS_FILE")"
cat > "$KEYS_FILE" <<EOF
REALITY_PRIVATE_KEY=${PRIVATE_KEY}
REALITY_PUBLIC_KEY=${PUBLIC_KEY}
REALITY_SHORT_ID=${SHORT_ID}
EOF
chmod 600 "$KEYS_FILE"

TMP_CONFIG="$(mktemp)"
jq \
  --arg privateKey "$PRIVATE_KEY" \
  --arg shortId "$SHORT_ID" \
  '.inbounds[0].streamSettings.realitySettings.privateKey = $privateKey
   | .inbounds[0].streamSettings.realitySettings.shortIds = [$shortId]' \
  "$CONFIG_FILE" > "$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG_FILE"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -f "$ENV_FILE" ]]; then
  grep -q '^REALITY_PUBLIC_KEY=' "$ENV_FILE" && sed -i "s/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=$PUBLIC_KEY/" "$ENV_FILE" || echo "REALITY_PUBLIC_KEY=$PUBLIC_KEY" >> "$ENV_FILE"
  grep -q '^REALITY_SHORT_ID=' "$ENV_FILE" && sed -i "s/^REALITY_SHORT_ID=.*/REALITY_SHORT_ID=$SHORT_ID/" "$ENV_FILE" || echo "REALITY_SHORT_ID=$SHORT_ID" >> "$ENV_FILE"
else
  cat >> "$ENV_FILE" <<EOF
REALITY_PUBLIC_KEY=$PUBLIC_KEY
REALITY_SHORT_ID=$SHORT_ID
EOF
fi

echo
echo "Reality-ключи сохранены:"
echo "  private key -> $KEYS_FILE (не передавать сотрудникам)"
echo "  public key  -> $PUBLIC_KEY"
echo "  short id    -> $SHORT_ID"
echo
echo "Дальше: ./scripts/add-user.sh <имя-сотрудника>"
