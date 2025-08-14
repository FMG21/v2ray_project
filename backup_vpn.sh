#!/bin/bash
# backup_vpn.sh — собирает конфиги V2Ray и Nginx в архив

TIMESTAMP=$(date +%F_%H-%M-%S)
BACKUP_DIR="/root/vpn_backup_$TIMESTAMP"
ARCHIVE="/root/vpn_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "📦 Собираем файлы в $BACKUP_DIR ..."

# V2Ray конфиг
if [ -f /usr/local/etc/v2ray/config.json ]; then
    cp /usr/local/etc/v2ray/config.json "$BACKUP_DIR/"
    echo "✅ V2Ray config добавлен"
else
    echo "❌ V2Ray config не найден"
fi

# Nginx конфиги
if [ -d /etc/nginx ]; then
    cp -r /etc/nginx "$BACKUP_DIR/"
    echo "✅ Nginx конфиги добавлены"
else
    echo "❌ Nginx конфиги не найдены"
fi

# SSL сертификаты
if [ -d /etc/letsencrypt ]; then
    cp -r /etc/letsencrypt "$BACKUP_DIR/"
    echo "✅ Let's Encrypt сертификаты добавлены"
else
    echo "❌ Let's Encrypt сертификаты не найдены"
fi

# Создаём архив
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" .
echo "✅ Архив готов: $ARCHIVE"

echo "Теперь можешь скачать его командой:"
echo "scp root@<IP_СЕРВЕРА>:${ARCHIVE} ."

