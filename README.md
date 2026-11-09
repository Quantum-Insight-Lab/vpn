# VPN для сотрудников (Selectel KZ)

Стек на одном VPS:

- **Xray** — VLESS + REALITY + XHTTP на `443/tcp`. SNI `proxy.qip.zone`, соединение без ключа уходит на локальный Caddy (self-steal).
- **Caddy + Telemt** — живой сайт и WEB-прокси Telegram на том же домене. Caddy слушает `127.0.0.1:8443`, снаружи его закрывает Xray. Порт `80/tcp` остаётся у Caddy для выпуска сертификата.
- **Cloudflare WARP** — единственный выход пользовательского трафика. Адрес входа (`VPS_IP`) в интернет не выпускает клиентов. С адреса узла уходят только служебные соединения: DoH ядра и туннель до `engage.cloudflareclient.com`.

Каталоги `deploy/` (sslh, nginx SNI) и `mtg/` в репозитории сохранены, в эту схему не входят: открытый SOCKS/HTTP на 443 и чужой SNI `cloudflare.com` больше не поднимаются. Сервис `mtg` в Compose выключен профилем и сам не стартует.

## Требования

- Ubuntu 22.04/24.04 на VPS Selectel (KZ)
- Docker + Docker Compose
- `jq`, `openssl`, `python3`, `wgcf`
- Открытые порты: `443/tcp`, `80/tcp` (продление сертификата), SSH
- Аккаунт WARP (`wgcf`) — выход всего туннеля, не только Telegram

## Порты

| Снаружи | Куда | Назначение |
|---------|------|------------|
| `443` | Xray | VLESS REALITY XHTTP; без ключа — сайт `proxy.qip.zone` |
| `80` | Caddy | HTTP-01 для сертификата |
| — | `127.0.0.1:8443` | Caddy, цель REALITY и локальный сайт |
| — | Telemt в сети compose | WEB-прокси Telegram |

## Быстрый старт на VPS

```bash
# 1. Зависимости
sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq openssl python3
sudo systemctl enable --now docker

# 2. Репозиторий
git clone <repo-url> vpn && cd vpn
cp .env.example .env
nano .env   # VPS_IP

# 3. WARP, один раз
mkdir -p warp && cd warp
wgcf register --accept-tos
wgcf generate
# PrivateKey и Address (v4) из wgcf-profile.conf → outbound "warp" в xray/config.json
cd ..

# 4. Reality и запуск
chmod +x scripts/*.sh
./scripts/setup.sh

# 5. Сотрудник (VPN)
./scripts/add-user.sh ivan-petrov
```

`setup.sh` выпускает ключи REALITY, проверяет конфиг (`xray run -test`), переводит Caddy на `127.0.0.1:8443` и поднимает Xray на `443`.

## Клиенты

| Платформа | VPN (VLESS REALITY XHTTP) | Telegram без VPN |
|-----------|---------------------------|------------------|
| Windows   | v2rayN, Hiddify | WEB-ссылка `tg://webproxy` |
| Android   | Hiddify, v2rayNG | WEB, если сборка умеет этот тип |
| iOS       | Happ, Streisand, Hiddify | WEB-ссылка |
| macOS     | Hiddify, v2rayN | WEB-ссылка |

### VLESS

Импорт из `add-user.sh`: ссылка `type=xhttp` и JSON с тем же `extra`. В клиенте должны быть диапазоны паддинга и xmux, не дефолтный залп соединений. Поток `xtls-rprx-vision` не используется.

Режим — **global / full tunnel**. SNI: `proxy.qip.zone`. Весь трафик устройства идёт в туннель; деление по приложениям на клиенте не используется.

`https://ifconfig.me` через туннель показывает адрес Cloudflare, не IP VPS.

### Telegram (WEB) — без VLESS

Домен `proxy.qip.zone`, порт 443. Ссылку выдаёт Telemt при старте (`docker logs telemt`). Обычный браузер на этом домене видит страницу QIP.

## Управление доступом

**Добавить сотрудника (VPN):**

```bash
./scripts/add-user.sh name-surname
```

**Отозвать VPN:** удалить UUID из `xray/config.json` → `clients[]`, затем `docker compose restart xray`.

**Сменить Reality:** `./scripts/gen-reality.sh`, затем раздать новые ссылки.

Вести `UUID ↔ сотрудник` отдельно (не в git).

## Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
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

### Сайт и WEB-прокси

- [ ] `https://proxy.qip.zone/` открывается без VPN и показывает страницу QIP
- [ ] Сертификат Let's Encrypt на `proxy.qip.zone`
- [ ] `tg://webproxy` подключается

### VPN

- [ ] Клиент подключается (REALITY + XHTTP)
- [ ] `https://ifconfig.me` показывает IP Cloudflare
- [ ] YouTube / заблокированные сайты открываются
- [ ] В логах Xray пользовательские сессии идут в `warp`

### Сервер

- [ ] `docker compose ps` — `xray` Up
- [ ] `docker compose -f telemt-web/docker-compose.yml ps` — `caddy` и `telemt` Up
- [ ] `ss -tlnp` — публичный `443` у `xray`, `8443` только на `127.0.0.1`
- [ ] Диск не 100% (`df -h /`)

### При проблемах

1. VLESS: `pbk`, `sid`, `sni=proxy.qip.zone`, `type=xhttp`, путь `/cdn/img`, в клиенте тот же `extra`
2. Сайт не открывается: Caddy слушает `127.0.0.1:8443`, Xray `dest` указывает туда же
3. `ifconfig.me` показывает IP VPS: outbound `warp` не заполнен или трафик ушёл не в него. Пользовательского `freedom` в конфиге нет
4. Security Group Selectel: inbound `443/tcp` и `80/tcp`

## Структура репозитория

```
docker-compose.yml       # xray (host network); mtg за профилем и не стартует
xray/config.json         # VLESS REALITY XHTTP, выход WARP
telemt-web/              # Caddy на 127.0.0.1:8443 и Telemt
deploy/                  # старые sslh и nginx-sni, не используются
mtg/                     # старый MTProto FakeTLS, не используется
scripts/
  setup.sh
  gen-reality.sh
  add-user.sh
  gen-vless-link.sh
.env.example
warp/                    # локально, не в git
```

## Секреты

Не коммитить: `.env`, `xray/.keys`, живой `xray/config.json` с ключами, `telemt-web/config/`, `warp/`.
