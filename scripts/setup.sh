#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "${ROOT_DIR}/.env.example" "$ENV_FILE"
  echo "Создан $ENV_FILE — укажите VPS_IP и запустите снова."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ "${VPS_IP:-}" == "0.0.0.0" || -z "${VPS_IP:-}" ]]; then
  echo "Заполните VPS_IP в $ENV_FILE" >&2
  exit 1
fi

chmod +x "${ROOT_DIR}/scripts/"*.sh

echo "==> Reality keys"
"${ROOT_DIR}/scripts/gen-reality.sh"

WARP_KEY="$(jq -r '.outbounds[] | select(.tag=="warp") | .settings.secretKey' "${ROOT_DIR}/xray/config.json")"
if [[ "$WARP_KEY" == "REPLACE_WARP_PRIVATE_KEY" || -z "$WARP_KEY" || "$WARP_KEY" == "null" ]]; then
  echo "Заполните outbound warp из warp/wgcf-profile.conf и запустите снова." >&2
  exit 1
fi

echo
echo "==> Проверка конфига"
docker run --rm \
  -v "${ROOT_DIR}/xray/config.json:/etc/xray/config.json:ro" \
  "${XRAY_IMAGE:-ghcr.io/xtls/xray-core:latest}" \
  run -test -config /etc/xray/config.json

echo
echo "==> Caddy на 127.0.0.1:8443, затем Xray на :443"
docker compose -f "${ROOT_DIR}/telemt-web/docker-compose.yml" up -d caddy
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d xray

echo
echo "Дальше: ./scripts/add-user.sh ivan-petrov"
echo "Клиент — полный туннель. https://ifconfig.me должен показать адрес Cloudflare."
