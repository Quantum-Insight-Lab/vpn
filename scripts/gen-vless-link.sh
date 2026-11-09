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
SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")"
PORT="$(jq -r '.inbounds[0].port' "$CONFIG_FILE")"
FINGERPRINT="${VLESS_FINGERPRINT:-chrome}"
XHTTP_PATH="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "$CONFIG_FILE")"
XHTTP_MODE="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode' "$CONFIG_FILE")"

if [[ -z "$SHORT_ID" || "$SHORT_ID" == "REPLACE_WITH_SHORT_ID" ]]; then
  SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")"
fi

if [[ -z "$PUBLIC_KEY" || -z "$SHORT_ID" || "$SHORT_ID" == "REPLACE_WITH_SHORT_ID" || "$SHORT_ID" == "null" ]]; then
  echo "Не найдены Reality public key / short id. Запустите ./scripts/gen-reality.sh" >&2
  exit 1
fi

ENCODED_LABEL="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$LABEL")"
ENCODED_PATH="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$XHTTP_PATH")"
EXTRA_JSON="$(jq -c '.inbounds[0].streamSettings.xhttpSettings.extra' "$CONFIG_FILE")"
ENCODED_EXTRA="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$EXTRA_JSON")"

LINK="vless://${USER_UUID}@${VPS_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=${ENCODED_PATH}&mode=${XHTTP_MODE}&extra=${ENCODED_EXTRA}#${ENCODED_LABEL}"

echo "$LINK"
echo
echo "Импортируйте ссылку и проверьте, что клиент взял extra ниже. Режим — полный туннель."
echo
python3 - "$CONFIG_FILE" "$LABEL" "$VPS_IP" "$PORT" "$USER_UUID" "$SNI" "$FINGERPRINT" "$PUBLIC_KEY" "$SHORT_ID" <<'PY'
import json, sys
config_path, label, address, port, user_id, sni, fp, pbk, sid = sys.argv[1:]
config = json.load(open(config_path))
xhttp = config["inbounds"][0]["streamSettings"]["xhttpSettings"]
doc = {
    "remarks": label,
    "outbounds": [
        {
            "protocol": "vless",
            "tag": "proxy",
            "settings": {
                "vnext": [
                    {
                        "address": address,
                        "port": int(port),
                        "users": [{"id": user_id, "encryption": "none"}],
                    }
                ]
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                    "serverName": sni,
                    "fingerprint": fp,
                    "publicKey": pbk,
                    "shortId": sid,
                },
                "xhttpSettings": xhttp,
            },
        }
    ],
}
json.dump(doc, sys.stdout, indent=2, ensure_ascii=False)
print()
PY
