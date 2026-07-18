# VPN для сотрудников (Selectel KZ)

Стек на одном VPS:

- **Xray** — VLESS + Reality (полный туннель) и SOCKS5/HTTP для Telegram
- **sslh** — мультиплексор на `443/tcp` (TLS → VLESS, SOCKS5/HTTP → прокси)
- **Cloudflare WARP** — outbound для DC Telegram (локально в `warp/`, не в git)

MTProto (`mtg`) больше не в default-стеке.

## Требования

- Ubuntu 22.04/24.04 на VPS Selectel (KZ)
- Docker + Docker Compose
- `jq`, `openssl`, `python3`, `sslh`
- Открытые порты: `443/tcp`, SSH
- Аккаунт WARP (`wgcf`) для Telegram-маршрута

## Порты

| Снаружи | Куда | Назначение |
|---------|------|------------|
| `443` | sslh | вход: VLESS (TLS/Reality) или SOCKS5/HTTP |
| — | `127.0.0.1:10443` | Xray VLESS Reality |
| — | `127.0.0.1:12080` | Xray SOCKS5 |
| — | `127.0.0.1:12081` | Xray HTTP proxy |

## Быстрый старт на VPS

```bash
# 1. Зависимости
sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq openssl python3 sslh
sudo systemctl enable --now docker

# 2. Репозиторий
git clone <repo-url> vpn && cd vpn
cp .env.example .env
nano .env   # VPS_IP=публичный.ip, SOCKS_USER / SOCKS_PASS

# 3. Reality-ключи + Xray
chmod +x scripts/*.sh
./scripts/gen-reality.sh
# подставьте privateKey/shortId в xray/config.json (или через gen-reality.sh),
# SOCKS-логин/пароль, REPLACE_VPS_IP в routing → to-socks
docker compose up -d

# 4. sslh на 443
sudo cp deploy/sslh.cfg /etc/sslh.cfg
sudo cp deploy/sslh-vpn.service /etc/systemd/system/sslh-vpn.service
# в unit путь к конфигу: -F /etc/sslh.cfg
sudo systemctl daemon-reload
sudo systemctl enable --now sslh-vpn

# 5. WARP для Telegram (один раз)
mkdir -p warp && cd warp
# установить wgcf, затем:
wgcf register --accept-tos
wgcf generate
# secretKey из wgcf-profile.conf → outbound "warp" в xray/config.json
cd ..
docker compose restart xray

# 6. Сотрудник (VPN)
./scripts/add-user.sh ivan-petrov
```

## Клиенты

| Платформа | VPN (VLESS Reality) | Telegram |
|-----------|---------------------|----------|
| Windows   | v2rayN, Nekoray, Hiddify | SOCKS5 на `:443` |
| Android   | Nekobox, Hiddify | SOCKS5 на `:443` |
| iOS       | Streisand, Happ, Hiddify | SOCKS5 на `:443` |
| macOS     | Nekoray, Hiddify | SOCKS5 на `:443` |

### VLESS

Импорт `vless://...` из `add-user.sh` → clipboard. Режим — **global / full tunnel**.  
SNI: `www.cloudflare.com`.

### Telegram (SOCKS5)

Настройки → Данные и память → Прокси → **SOCKS5**:

- Сервер: `VPS_IP`
- Порт: `443`
- Логин / пароль: из `.env` (`SOCKS_USER` / `SOCKS_PASS`)
- Secret: пусто

## Управление доступом

**Добавить сотрудника (VPN):**

```bash
./scripts/add-user.sh name-surname
```

**Отозвать VPN:** удалить UUID из `xray/config.json` → `clients[]`, затем:

```bash
docker compose restart xray
```

**Сменить пароль SOCKS:** обновить accounts в `socks-in` / `http-in` и `.env`, затем `docker compose restart xray`.

Вести `UUID ↔ сотрудник` отдельно (не в git).

## Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
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
- [ ] В клиенте remote/routed DNS

### Telegram

- [ ] SOCKS5 `:443` — «Проверить прокси» OK
- [ ] В `docker compose logs xray` есть `-> warp` на DC `149.154.*` / `91.108.*`

### Сервер

- [ ] `docker compose ps` — `xray` Up
- [ ] `systemctl is-active sslh-vpn` — active
- [ ] `ss -tlnp | grep -E ':443|:10443|:12080'` — слушают
- [ ] Диск не 100% (`df -h /`)

### При проблемах

1. `VPS_IP`, `pbk`, `sid`, `sni=www.cloudflare.com` в vless-ссылке
2. С VPS: `curl -I https://www.cloudflare.com`
3. SOCKS с телефона/ПК только на порт **443**, не 2080
4. Security Group Selectel: inbound `443/tcp`

## Структура репозитория

```
docker-compose.yml       # только xray (host network)
xray/config.json         # шаблон: VLESS + SOCKS + HTTP + WARP routing
deploy/
  sslh.cfg               # мультиплексор 443
  sslh-vpn.service       # systemd unit
scripts/
  setup.sh               # Reality + docker up; sslh/WARP — по README
  gen-reality.sh
  add-user.sh
  gen-vless-link.sh
  gen-mtproto.sh         # опционально, mtg не в compose
.env.example
warp/                    # локально, не в git
```

## Секреты

Не коммитить: `.env`, `xray/.keys`, `mtg/config.toml`, `warp/`.
