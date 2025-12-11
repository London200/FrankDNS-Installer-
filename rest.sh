#!/bin/bash

echo "============================================"
echo "     FRANKDNS+ — TELJES TISZTÍTÁS"
echo "============================================"

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
    echo "❌ Hibás jogosultság! Futtasd így: sudo ./reset.sh"
    exit 1
fi

INSTALL_DIR="/opt/frankdnsplus"
SERVICE_FILE="/etc/systemd/system/frankdnsplus.service"

echo "🛑 Szolgáltatás leállítása..."
systemctl stop frankdnsplus 2>/dev/null
systemctl disable frankdnsplus 2>/dev/null

echo "🗑️ Régi könyvtárak törlése..."
rm -rf "$INSTALL_DIR"

echo "🗑️ Régi bináris eltávolítása..."
rm -f /usr/local/bin/frankdnsplus
rm -f /usr/local/bin/frank

echo "🗑️ Régi systemd szolgáltatás törlése..."
rm -f "$SERVICE_FILE"
systemctl daemon-reload

echo "🔓 Portok felszabadítása..."
fuser -k 3000/tcp 2>/dev/null
fuser -k 53/tcp 2>/dev/null
fuser -k 53/udp 2>/dev/null

echo "🧹 Go cache törlése..."
rm -rf /root/go/pkg/mod/cache 2>/dev/null
rm -rf /home/*/go/pkg/mod/cache 2>/dev/null

echo "🧹 Konfig backup maradékok törlése..."
rm -f /tmp/frankdnsplus_* 2>/dev/null

echo "============================================"
echo "   ✔ KÉSZ! A RENDSZER TELJESEN TISZTA"
echo "============================================"
echo "Most már futtathatod az új telepítőt!"
echo ""
