# VPN + MTProto для сотрудников (Selectel KZ)

Стек на одном VPS:

- **Xray** — VLESS + Reality на `443/tcp` (полный туннель интернета)
- **mtg** — MTProto-прокси для Telegram на `8443/tcp`

## Требования

- Ubuntu 22.04/24.04 на VPS Selectel (KZ)
- Docker + Docker Compose
- `jq`, `openssl`, `python3`
- Открытые порты: `443`, `8443`, SSH

## Быстрый старт на VPS

```bash
# 1. Установка зависимостей
sudo apt update && sudo apt install -y docker.io docker-compose-v2 jq openssl python3
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
# перелогиниться или: newgrp docker

# 2. Клонировать / скопировать репозиторий
git clone <repo-url> vpn && cd vpn

# 3. Настроить окружение
cp .env.example .env
nano .env   # указать VPS_IP

# 4. Первичная настройка (ключи + контейнеры)
./scripts/setup.sh

# 5. Добавить сотрудника
./scripts/add-user.sh ivan-petrov
```

Скрипт `add-user.sh` выведет `vless://...` ссылку для клиента.

## Ручная настройка (пошагово)

```bash
cp .env.example .env
# VPS_IP=ваш.публичный.ip

chmod +x scripts/*.sh
./scripts/gen-reality.sh
./scripts/gen-mtproto.sh
./scripts/add-user.sh employee-name

docker compose up -d
```

## Прокси для Telegram (SOCKS5 / HTTP)

На `:443` через `sslh` рядом с VLESS (см. `deploy/sslh.cfg`).

1. Установить `sslh`, скопировать unit из `deploy/sslh-vpn.service`
2. Xray слушает `127.0.0.1:10443` (VLESS), `12080` (SOCKS), `12081` (HTTP)
3. Telegram → SOCKS5 → `VPS_IP:443` + логин/пароль из `.env`
4. Трафик к DC Telegram уходит через Cloudflare WARP (`warp/` локально, в git не коммитится)

При включённом VLESS в Telegram лучше **Прокси → Нет**, либо оставить SOCKS — hairpin на `VPS_IP:443` редиректится на локальный SOCKS.

## MTProto для Telegram (опционально)


После `./scripts/gen-mtproto.sh`:

```
tg://proxy?server=<VPS_IP>&port=8443&secret=<secret>
```

Или `https://t.me/proxy?server=...&port=...&secret=...` — открывается в Telegram.

Проверка ссылок:

```bash
docker run --rm -v "$PWD/mtg/config.toml:/config.toml:ro" nineseconds/mtg:2 access /config.toml
```

## Клиенты

| Платформа | VPN (VLESS Reality) | Telegram |
|-----------|---------------------|----------|
| Windows   | v2rayN, Nekoray, Hiddify | встроенный MTProto |
| Android   | Nekobox, Hiddify | встроенный MTProto |
| iOS       | Streisand, Happ, Hiddify | встроенный MTProto |
| macOS     | Nekoray, Hiddify | — |

Импорт: скопировать `vless://` ссылку → «Import from clipboard» в клиенте. Режим — **глобальный / full tunnel**.

## Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw allow 8443/tcp
sudo ufw enable
sudo ufw status
```

SSH лучше ограничить вашими IP в Selectel Security Groups или через `ufw allow from <office-ip> to any port 22`.

## Hardening SSH

```bash
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## Управление доступом

**Добавить сотрудника:**

```bash
./scripts/add-user.sh name-surname
```

**Отозвать VPN-доступ:** удалить UUID из `xray/config.json` → `clients[]`, затем:

```bash
docker compose restart xray
```

**Сменить MTProto secret** (все переподключатся):

```bash
./scripts/gen-mtproto.sh
docker compose restart mtg
```

Вести соответствие `UUID ↔ сотрудник` отдельно (не в git).

## Чеклист проверки из РФ

### VPN (полный туннель)

- [ ] Клиент подключается без ошибок handshake / REALITY
- [ ] `https://ifconfig.me` показывает IP VPS (KZ), не домашний/офисный
- [ ] Открываются заблокированные сайты (YouTube, GitHub и т.д.)
- [ ] DNS не «утекает»: в клиенте включён remote DNS / routed DNS
- [ ] Переподключение после sleep/wifi-switch работает

### MTProto

- [ ] Ссылка `tg://proxy?...` открывается в Telegram
- [ ] В Settings → Data and Storage → Proxy — статус Connected
- [ ] Сообщения и медиа отправляются/принимаются
- [ ] Работает при выключенном VPN (независимые сервисы)

### Сервер

- [ ] `docker compose ps` — оба контейнера `running`
- [ ] `ss -tlnp | grep -E ':443|:8443'` — порты слушают
- [ ] `docker compose logs xray --tail 50` — нет постоянных ошибок
- [ ] UFW активен, лишние порты закрыты

### При проблемах

1. Проверить `VPS_IP`, `pbk`, `sid`, `sni` в vless-ссылке
2. С VPS: `curl -I https://www.cloudflare.com` (dest для Reality)
3. Сменить `dest` / `serverNames` в `xray/config.json` на другой TLS 1.3 хост
4. Проверить Security Group Selectel (443, 8443 inbound)

## Структура репозитория

```
docker-compose.yml    # xray (host network) + mtg
xray/config.json      # VLESS Reality inbound
mtg/config.toml       # генерируется, не в git
scripts/
  setup.sh            # первичный деплой
  gen-reality.sh      # ключи Reality
  gen-mtproto.sh      # secret + tg:// ссылка
  add-user.sh         # UUID + vless ссылка
  gen-vless-link.sh   # перегенерация ссылки по UUID
.env.example
```

## Секреты

Не коммитить: `.env`, `xray/.keys`, `mtg/config.toml`.
