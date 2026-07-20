# VPN для сотрудников (Selectel KZ)

Стек на одном VPS:

- **Xray** — VLESS + Reality (полный туннель), SOCKS5/HTTP, маршрутизация Telegram через WARP
- **sslh-select** — мультиплексор на `443/tcp` (TLS / SOCKS5 / HTTP)
- **nginx stream** — SNI-роутер: `www.cloudflare.com` → VLESS, `cloudflare.com` → MTProto
- **mtg** — MTProto FakeTLS для Telegram без VLESS (DC через локальный SOCKS → WARP)
- **Cloudflare WARP** — outbound для DC Telegram (локально в `warp/`, не в git)

## Требования

- Ubuntu 22.04/24.04 на VPS Selectel (KZ)
- Docker + Docker Compose
- `jq`, `openssl`, `python3`, `sslh`, `nginx` + `libnginx-mod-stream`
- Открытые порты: `443/tcp`, SSH
- Аккаунт WARP (`wgcf`) для Telegram-маршрута

## Порты

| Снаружи | Куда | Назначение |
|---------|------|------------|
| `443` | sslh-select | вход: TLS → nginx SNI, SOCKS5/HTTP → Xray |
| — | `127.0.0.1:10440` | nginx SNI-router |
| — | `127.0.0.1:10443` | Xray VLESS Reality (`www.cloudflare.com`) |
| — | `127.0.0.1:13128` | mtg MTProto (`cloudflare.com`) |
| — | `127.0.0.1:12080` | Xray SOCKS5 (ещё и upstream для mtg) |
| — | `127.0.0.1:12081` | Xray HTTP proxy |

## Быстрый старт на VPS

```bash
# 1. Зависимости
sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq openssl python3 sslh nginx libnginx-mod-stream
sudo systemctl enable --now docker
sudo systemctl disable --now nginx   # системный nginx на 443 не нужен

# 2. Репозиторий
git clone <repo-url> vpn && cd vpn
cp .env.example .env
nano .env   # VPS_IP, SOCKS_USER / SOCKS_PASS

# 3. Reality + MTProto + Xray/mtg
chmod +x scripts/*.sh
./scripts/gen-reality.sh
./scripts/gen-mtproto.sh
# в xray/config.json: privateKey, shortId, SOCKS accounts,
# REPLACE_VPS_IP/32 в routing → to-mtg, WARP secretKey
docker compose up -d

# 4. nginx SNI + sslh на 443
# в deploy/nginx-sni.service путь к nginx.conf = каталог установки (по умолчанию /opt/vpn)
sudo cp deploy/nginx-sni.service /etc/systemd/system/nginx-sni.service
sudo cp deploy/sslh.cfg /etc/sslh.cfg
sudo cp deploy/sslh-vpn.service /etc/systemd/system/sslh-vpn.service
sudo systemctl daemon-reload
sudo systemctl enable --now nginx-sni sslh-vpn

# 5. WARP для Telegram (один раз)
mkdir -p warp && cd warp
wgcf register --accept-tos
wgcf generate
# secretKey из wgcf-profile.conf → outbound "warp" в xray/config.json
cd ..
docker compose restart xray

# 6. Сотрудник (VPN)
./scripts/add-user.sh ivan-petrov
```

## Клиенты

| Платформа | VPN (VLESS Reality) | Telegram без VPN |
|-----------|---------------------|------------------|
| Windows   | v2rayN, Nekoray, Hiddify | MTProto-ссылка `:443` |
| Android   | Nekobox, Hiddify | MTProto-ссылка `:443` |
| iOS       | Streisand, Happ, Hiddify | MTProto-ссылка `:443` |
| macOS     | Nekoray, Hiddify | MTProto-ссылка `:443` |

### VLESS

Импорт `vless://...` из `add-user.sh`. Режим — **global / full tunnel**.  
SNI: `www.cloudflare.com`.

С включённым VPN Telegram ходит через WARP; MTProto к этому же VPS тоже работает (hairpin `to-mtg`).

### Telegram (MTProto) — без VLESS

Основной способ. Ссылка после `./scripts/gen-mtproto.sh`:

```text
https://t.me/proxy?server=<VPS_IP>&port=443&secret=<MTPROTO_SECRET>
```

SNI/FakeTLS-домен: `cloudflare.com` (не путать с Reality SNI `www.cloudflare.com`).

### Telegram (SOCKS5) — запасной канал

Настройки → Прокси → **SOCKS5**: сервер `VPS_IP`, порт `443`, логин/пароль из `.env`.  
На мобильных операторах SOCKS часто режется DPI — предпочтительнее MTProto.

## Управление доступом

**Добавить сотрудника (VPN):**

```bash
./scripts/add-user.sh name-surname
```

**Отозвать VPN:** удалить UUID из `xray/config.json` → `clients[]`, затем `docker compose restart xray`.

**Сменить MTProto secret:** `./scripts/gen-mtproto.sh` (все переподключатся по новой ссылке).

**Сменить пароль SOCKS:** accounts в `socks-in` / `http-in`, `.env` и `proxies` в `mtg/config.toml` → `docker compose up -d --force-recreate`.

Вести `UUID ↔ сотрудник` отдельно (не в git).

## Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw enable
```

SSH лучше ограничить вашими IP (Security Groups / `ufw allow from <ip> to any port 22`).

## Hardening SSH

```bash
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## Чеклист проверки

### VPN

- [ ] Клиент подключается (REALITY handshake OK)
- [ ] `https://ifconfig.me` показывает IP VPS
- [ ] YouTube / заблокированные сайты открываются

### Telegram

- [ ] Без VLESS: MTProto-ссылка на `:443` — «подключён»
- [ ] С VLESS: чаты работают (в логах `vless-reality -> warp` на DC)
- [ ] `docker compose exec` / `docker logs mtg` + `xray` без массовых ошибок

### Сервер

- [ ] `docker compose ps` — `xray`, `mtg` Up
- [ ] `systemctl is-active sslh-vpn nginx-sni` — active
- [ ] `ss -tlnp | grep -E ':443|:10440|:10443|:13128|:12080'`
- [ ] Диск не 100% (`df -h /`)

### При проблемах

1. VLESS: `pbk`, `sid`, `sni=www.cloudflare.com` в ссылке
2. MTProto: порт **443**, secret с доменом `cloudflare.com`, VLESS можно оставить включённым
3. SOCKS с телефона часто нестабилен — используйте MTProto
4. Нужен **sslh-select**, не sslh-fork (fork плодит процессы под Telegram)
5. Security Group Selectel: inbound `443/tcp`

## Структура репозитория

```
docker-compose.yml       # xray + mtg (host network)
xray/config.json         # шаблон: VLESS + SOCKS + HTTP + WARP + to-mtg
nginx/nginx.conf         # SNI: cloudflare.com→mtg, www→xray
mtg/config.toml.example
deploy/
  sslh.cfg               # TLS→10440, SOCKS→12080, HTTP→12081
  sslh-vpn.service       # sslh-select
  nginx-sni.service
scripts/
  setup.sh
  gen-reality.sh
  gen-mtproto.sh
  add-user.sh
  gen-vless-link.sh
.env.example
warp/                    # локально, не в git
```

## Секреты

Не коммитить: `.env`, `xray/.keys`, живой `xray/config.json` с ключами, `mtg/config.toml`, `warp/`.
