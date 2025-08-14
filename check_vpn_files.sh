#!/bin/bash
# check_vpn_files.sh — проверяет наличие основных файлов V2Ray и Nginx

echo "🔍 Проверяем V2Ray конфиг..."
if [ -f /usr/local/etc/v2ray/config.json ]; then
    echo "✅ /usr/local/etc/v2ray/config.json найден"
else
    echo "❌ /usr/local/etc/v2ray/config.json НЕ найден"
fi

echo "🔍 Проверяем Nginx..."
if [ -d /etc/nginx ]; then
    echo "✅ /etc/nginx найден"
else
    echo "❌ /etc/nginx НЕ найден"
fi

echo "🔍 Проверяем SSL сертификаты..."
if [ -d /etc/letsencrypt ]; then
    echo "✅ /etc/letsencrypt найден"
else
    echo "❌ /etc/letsencrypt НЕ найден"
fi

echo "🔍 Проверяем systemd сервис V2Ray..."
if systemctl status v2ray >/dev/null 2>&1; then
    echo "✅ v2ray.service активен"
else
    echo "❌ v2ray.service не найден или не активен"
fi

echo "🔍 Проверяем порты..."
ss -plnt | grep -E '80|443|10000' || echo "⚠️ Порты 80/443/10000 не слушаются"

