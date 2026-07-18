#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "${ROOT_DIR}/.env.example" "$ENV_FILE"
  echo "Создан $ENV_FILE — укажите VPS_IP, SOCKS_USER, SOCKS_PASS и запустите снова."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ "${VPS_IP:-}" == "0.0.0.0" || -z "${VPS_IP:-}" ]]; then
  echo "Заполните VPS_IP в $ENV_FILE" >&2
  exit 1
fi

if [[ -z "${SOCKS_PASS:-}" ]]; then
  echo "Заполните SOCKS_PASS в $ENV_FILE" >&2
  exit 1
fi

chmod +x "${ROOT_DIR}/scripts/"*.sh

echo "==> Reality keys"
"${ROOT_DIR}/scripts/gen-reality.sh"

echo
echo "==> Подставьте в xray/config.json:"
echo "  - SOCKS accounts (SOCKS_USER / SOCKS_PASS)"
echo "  - routing REPLACE_VPS_IP → ${VPS_IP}"
echo "  - WARP secretKey из warp/wgcf-profile.conf (см. README)"
echo
echo "==> Docker Compose up (xray)"
docker compose -f "${ROOT_DIR}/docker-compose.yml" pull
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

echo
echo "Дальше вручную (см. README):"
echo "  1) sslh: deploy/sslh.cfg + systemctl enable --now sslh-vpn"
echo "  2) WARP outbound в config + docker compose restart xray"
echo "  3) ./scripts/add-user.sh ivan-petrov"
