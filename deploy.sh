#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =====================================
# deploy.sh — полный развёртыватель V2Ray (VLESS+WS) + Nginx + Certbot
# Создаёт структуру /opt/v2ray-repo, шаблоны, скрипты и делает базовую установку.
# Тестирован на Ubuntu 22.04/24.04.
# =====================================

# --- Параметры ---
PROJECT_DIR="/opt/v2ray-repo"
V2RAY_CONFIG_PATH="/usr/local/etc/v2ray/config.json"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# --- Проверка root ---
if [ "$EUID" -ne 0 ]; then
  echo "Запусти этот скрипт с root: sudo ./deploy.sh"
  exit 1
fi

# --- Приветствие и ввод данных ---
echo "=== V2Ray + Nginx + Certbot deploy script ==="
read -rp "1) Введи домен (например: vpn.example.com) [default: 13rus.casacam.net]: " DOMAIN_INPUT
DOMAIN="${DOMAIN_INPUT:-13rus.casacam.net}"

read -rp "2) Введи email для Let's Encrypt (например: you@example.com) [default: 21fmg21@gmail.com]: " EMAIL_INPUT
EMAIL="${EMAIL_INPUT:-21fmg21@gmail.com}"

read -rp "3) Использовать Cloudflare DNS-01 (реко.)? (y/n): " USE_CF

CF_API_TOKEN=""
if [[ "$USE_CF" =~ ^[Yy]$ ]]; then
  read -rp "   Вставь Cloudflare API Token (Zone DNS edit): " CF_API_TOKEN
fi

WS_PATH="/ws"   # можно изменить на /ray
echo
echo "Домен: $DOMAIN"
echo "Email: $EMAIL"
echo "Cloudflare DNS-01: ${USE_CF}"
echo

read -rp "Продолжить установку с этими параметрами? (y/n): " CONF
if [[ ! "$CONF" =~ ^[Yy]$ ]]; then
  echo "Отменено."
  exit 0
fi

# --- Установка пакетов системы ---
echo ">>> apt update && install core packages..."
apt update -y
apt upgrade -y

# essential tools
apt install -y ca-certificates curl wget git jq uuid-runtime python3 python3-pip \
               nginx certbot python3-certbot-nginx

# Если Cloudflare выбран — установим плагин
if [[ "$USE_CF" =~ ^[Yy]$ ]]; then
  apt install -y python3-certbot-dns-cloudflare
fi

# install Jinja2 for render script
pip3 install --upgrade pip >/dev/null 2>&1 || true
pip3 install jinja2 >/dev/null

# --- Установка V2Ray (официальный скрипт) ---
echo ">>> Устанавливаем V2Ray..."
bash <(curl -Ls https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# ensure systemd knows v2ray unit
systemctl daemon-reload || true
systemctl enable --now v2ray || true

# --- Создаём структуру проекта ---
echo ">>> Создаём проектную структуру в $PROJECT_DIR..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{config_templates,scripts}
chmod 755 "$PROJECT_DIR"

# --- Шаблоны конфигов (Jinja2) ---
cat > "$PROJECT_DIR/config_templates/v2ray-config.j2" <<'EOF'
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
{% for c in clients %}
          { "id": "{{ c.id }}", "level": 0, "email": "{{ c.email|default('user') }}" }{% if not loop.last %},{% endif %}
{% endfor %}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "{{ ws_path }}"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF

cat > "$PROJECT_DIR/config_templates/nginx-site.j2" <<'EOF'
server {
    listen 80;
    server_name {{ domain }};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name {{ domain }};

    ssl_certificate /etc/letsencrypt/live/{{ domain }}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{ domain }}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location {{ ws_path }} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    location / {
        return 404;
    }
}
EOF

cat > "$PROJECT_DIR/config_templates/reality_template.j2" <<'EOF'
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
{% for c in clients %}
          { "id": "{{ c.id }}", "flow": "", "email": "{{ c.email|default('user') }}" }{% if not loop.last %},{% endif %}
{% endfor %}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "handshake": 1,
          "publicKey": "{{ publickey|default('') }}",
          "shortIds": []
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF

# --- users.json (источник правды) ---
cat > "$PROJECT_DIR/users.json" <<EOF
{
  "clients": []
}
EOF

# --- inventory.json ---
cat > "$PROJECT_DIR/inventory.json" <<EOF
[]
EOF

# --- .env.example ---
cat > "$PROJECT_DIR/.env.example" <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
# If using Cloudflare, set CF_API_TOKEN environment variable or use the prompt during install
# CF_API_TOKEN=...
EOF

# --- README.md ---
cat > "$PROJECT_DIR/README.md" <<'EOF'
V2Ray + Nginx + Certbot deploy (VLESS+WS)

Structure:
/opt/v2ray-repo/
  config_templates/
  scripts/
  users.json
  inventory.json

See scripts/ for management.
EOF

# --- render-config.py (рендерит шаблоны) ---
cat > "$PROJECT_DIR/scripts/render-config.py" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from jinja2 import Environment, FileSystemLoader

REPO_ROOT = os.path.dirname(os.path.dirname(__file__))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "config_templates")
USERS_FILE = os.path.join(REPO_ROOT, "users.json")

env = Environment(loader=FileSystemLoader(TEMPLATES_DIR), trim_blocks=True, lstrip_blocks=True)

with open(USERS_FILE) as f:
    users = json.load(f)

ws_path = os.environ.get("WS_PATH", "/ws")
domain = os.environ.get("DOMAIN", "example.com")

# render v2ray config
tmpl = env.get_template("v2ray-config.j2")
cfg = tmpl.render(clients=users.get("clients", []), ws_path=ws_path)
with open("/usr/local/etc/v2ray/config.json", "w") as f:
    f.write(cfg)

# render nginx site
tmpl_ng = env.get_template("nginx-site.j2")
ngcfg = tmpl_ng.render(domain=domain, ws_path=ws_path)
ng_path = f"/etc/nginx/sites-available/{domain}.conf"
with open(ng_path, "w") as f:
    f.write(ngcfg)

# symlink sites-enabled
enabled = f"/etc/nginx/sites-enabled/{domain}.conf"
if not os.path.exists(enabled):
    try:
        os.symlink(ng_path, enabled)
    except Exception:
        pass

print("Rendered v2ray config and nginx site for domain:", domain)
PY

# --- add-user.sh ---
cat > "$PROJECT_DIR/scripts/add-user.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/opt/v2ray-repo"
USERS_JSON="$REPO_ROOT/users.json"

EMAIL="${1:-user@local}"

UUID="$(uuidgen)"
python3 - <<PY
import json
fn = "$USERS_JSON"
data = json.load(open(fn))
data.setdefault("clients", []).append({"id":"$UUID", "email":"$EMAIL"})
json.dump(data, open(fn, "w"), indent=2)
print("$UUID")
PY

export DOMAIN="${DOMAIN:-$DOMAIN}"
export WS_PATH="${WS_PATH:-/ws}"

cd "$REPO_ROOT"
python3 scripts/render-config.py

systemctl restart v2ray
nginx -t && systemctl reload nginx

echo "Added user: $EMAIL"
echo "UUID: $UUID"
python3 - <<PY
import urllib.parse, os
path = urllib.parse.quote(os.environ.get("WS_PATH", "/ws"), safe='')
print(f"vless://{os.environ.get('UUID', '$UUID')}@{os.environ.get('DOMAIN', '$DOMAIN')}:443?type=ws&security=tls&path={path}#${EMAIL}")
PY
SH

# --- remove-user.sh ---
cat > "$PROJECT_DIR/scripts/remove-user.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="/opt/v2ray-repo"
USERS_JSON="$REPO_ROOT/users.json"
UUID="$1"

python3 - <<PY
import json,sys
fn = "$USERS_JSON"
data = json.load(open(fn))
clients = data.get("clients", [])
clients = [c for c in clients if c.get("id") != "$UUID"]
data["clients"] = clients
json.dump(data, open(fn, "w"), indent=2)
print("removed", "$UUID")
PY

cd "$REPO_ROOT"
python3 scripts/render-config.py
systemctl restart v2ray
nginx -t && systemctl reload nginx
SH

# --- health-check.sh ---
cat > "$PROJECT_DIR/scripts/health-check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="${1:-example.com}"
echo "nginx:"
systemctl is-active --quiet nginx && echo "ok" || echo "FAIL"
echo "v2ray:"
systemctl is-active --quiet v2ray && echo "ok" || echo "FAIL"
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo -n "Cert days left: "
  openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
    | sed 's/^.*=//' \
    | xargs -I{} bash -c 'echo $(( ( $(date -d "{}" +%s) - $(date +%s) ) / 86400 ))'
else
  echo "No cert found for $DOMAIN"
fi
curl -I -m 10 "https://$DOMAIN" || echo "HTTPS check fail"
SH

# --- deploy run helper (local) ---
cat > "$PROJECT_DIR/scripts/deploy-run.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export DOMAIN="${DOMAIN}"
export WS_PATH="/ws"
# render default (no users yet)
python3 /opt/v2ray-repo/scripts/render-config.py
nginx -t
systemctl restart v2ray
systemctl reload nginx
SH

# Make scripts executable
chmod +x "$PROJECT_DIR"/scripts/*.sh
chmod +x "$PROJECT_DIR"/scripts/render-config.py

echo ">>> Сгенерированы шаблоны и скрипты в $PROJECT_DIR"

# --- Если нужно, создаём cloudflare creds для certbot ---
if [[ "$USE_CF" =~ ^[Yy]$ ]]; then
  echo ">>> Пишем Cloudflare credentials..."
  mkdir -p /root/.secrets/certbot
  CF_FILE="/root/.secrets/certbot/cloudflare.ini"
  cat > "$CF_FILE" <<EOF
dns_cloudflare_api_token = $CF_API_TOKEN
EOF
  chmod 600 "$CF_FILE"
fi

# --- Render initial nginx config (will include certificates path, may not exist yet) ---
echo ">>> Рендерим конфиги (nginx site) и проверяем..."
export DOMAIN="$DOMAIN"
export WS_PATH="$WS_PATH"
python3 "$PROJECT_DIR/scripts/render-config.py"

# --- Test nginx config (will fail without cert if nginx tries to load certs) ---
echo ">>> Проверка nginx - если cert отсутствует, nginx -t может выдавать ошибку — это нормально сейчас."
nginx -t || true

# --- Получаем TLS сертификат ---
if [[ "$USE_CF" =~ ^[Yy]$ ]]; then
  echo ">>> Получаем сертификат через DNS-01 (Cloudflare)..."
  certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" || {
      echo "Certbot DNS-01 failed — проверь CF token/permissions."
      exit 1
    }
  echo "Cert получен, перезагружаем nginx..."
  nginx -t
  systemctl reload nginx
else
  echo ">>> Получаем сертификат через HTTP-01 (certbot --nginx). Если порт 80 занят — нужно освободить."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" || {
    echo "certbot --nginx failed — проверь доступность порта 80 и DNS."
    exit 1
  }
  systemctl reload nginx
fi

# --- Создаём тест-пользователя ---
echo ">>> Добавляем тестового пользователя (test@$DOMAIN)..."
/opt/v2ray-repo/scripts/add-user.sh "test@$DOMAIN" || true

# --- Финальный nginx test & services restart ---
nginx -t && systemctl restart v2ray && systemctl reload nginx

echo
echo "========================================"
echo "Установка завершена."
echo "Папка проекта: $PROJECT_DIR"
echo "Добавлен тестовый пользователь test@$DOMAIN — см. users.json"
echo "Чтобы добавить пользователя: sudo $PROJECT_DIR/scripts/add-user.sh email@domain"
echo "Проверь работу: sudo $PROJECT_DIR/scripts/health-check.sh $DOMAIN"
echo "Если использовал Cloudflare: убедись, что DNS записи корректны и Proxy (orange cloud) настроен как нужно."
echo "========================================"
