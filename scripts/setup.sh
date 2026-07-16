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

echo
echo "==> MTProto secret"
"${ROOT_DIR}/scripts/gen-mtproto.sh"

echo
echo "==> Docker Compose up"
docker compose -f "${ROOT_DIR}/docker-compose.yml" pull
docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d

echo
echo "Готово. Добавьте сотрудника:"
echo "  ./scripts/add-user.sh ivan-petrov"
