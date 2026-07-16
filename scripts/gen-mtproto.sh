#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
MTG_CONFIG="${ROOT_DIR}/mtg/config.toml"
MTG_IMAGE="${MTG_IMAGE:-nineseconds/mtg:2}"
DOMAIN="${MTPROTO_DOMAIN:-google.com}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  DOMAIN="${MTPROTO_DOMAIN:-$DOMAIN}"
fi

echo "Генерация MTProto secret (FakeTLS, domain: $DOMAIN)..."
SECRET="$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$DOMAIN" | tr -d '\r\n')"

cat > "$MTG_CONFIG" <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:3128"
EOF
chmod 600 "$MTG_CONFIG"

if [[ -f "$ENV_FILE" ]]; then
  grep -q '^MTPROTO_SECRET=' "$ENV_FILE" && sed -i "s/^MTPROTO_SECRET=.*/MTPROTO_SECRET=$SECRET/" "$ENV_FILE" || echo "MTPROTO_SECRET=$SECRET" >> "$ENV_FILE"
else
  echo "MTPROTO_SECRET=$SECRET" >> "$ENV_FILE"
fi

PORT="${MTPROTO_PORT:-8443}"

if [[ -n "${VPS_IP:-}" ]]; then
  echo
  echo "MTProto secret сохранён в $MTG_CONFIG"
  echo
  echo "Ссылки для сотрудников (подставьте IP вручную, если VPS_IP не задан):"
  echo "  tg://proxy?server=${VPS_IP}&port=${PORT}&secret=${SECRET}"
  echo "  https://t.me/proxy?server=${VPS_IP}&port=${PORT}&secret=${SECRET}"
else
  echo
  echo "MTProto secret сохранён в $MTG_CONFIG"
  echo "Задайте VPS_IP в .env и перезапустите скрипт или соберите ссылку вручную:"
  echo "  tg://proxy?server=<VPS_IP>&port=${PORT}&secret=${SECRET}"
fi

if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps mtg 2>/dev/null | grep -q running; then
  docker compose -f "${ROOT_DIR}/docker-compose.yml" restart mtg
  echo
  echo "mtg перезапущен."
fi

echo
echo "Проверка ссылок через mtg access:"
docker run --rm -v "${MTG_CONFIG}:/config.toml:ro" "$MTG_IMAGE" access /config.toml 2>/dev/null || true
