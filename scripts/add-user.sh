#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CONFIG_FILE="${ROOT_DIR}/xray/config.json"
XRAY_IMAGE="${XRAY_IMAGE:-ghcr.io/xtls/xray-core:latest}"

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 <имя-сотрудника> [uuid]" >&2
  exit 1
fi

LABEL="$1"
USER_UUID="${2:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Нужен jq: sudo apt install -y jq" >&2
  exit 1
fi

if [[ -z "$USER_UUID" ]]; then
  USER_UUID="$(docker run --rm "$XRAY_IMAGE" uuid | tr -d '\r\n')"
fi

PRIVATE_KEY="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")"
if [[ "$PRIVATE_KEY" == "REPLACE_WITH_PRIVATE_KEY" || -z "$PRIVATE_KEY" ]]; then
  echo "Сначала запустите ./scripts/gen-reality.sh" >&2
  exit 1
fi

if jq -e --arg id "$USER_UUID" '.inbounds[0].settings.clients[] | select(.id == $id)' "$CONFIG_FILE" >/dev/null; then
  echo "UUID уже есть в config.json: $USER_UUID" >&2
  exit 1
fi

TMP_CONFIG="$(mktemp)"
jq \
  --arg id "$USER_UUID" \
  --arg email "$LABEL" \
  '.inbounds[0].settings.clients += [{"id": $id, "email": $email, "flow": "xtls-rprx-vision"}]' \
  "$CONFIG_FILE" > "$TMP_CONFIG"
mv "$TMP_CONFIG" "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

echo "Пользователь добавлен: $LABEL"
echo "UUID: $USER_UUID"
echo

if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps xray 2>/dev/null | grep -q running; then
  docker compose -f "${ROOT_DIR}/docker-compose.yml" restart xray
  echo "Xray перезапущен."
fi

"${ROOT_DIR}/scripts/gen-vless-link.sh" "$USER_UUID" "$LABEL"
