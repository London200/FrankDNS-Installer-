#!/bin/bash

# Színek definiálása
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Segítség kiírása, ha nincs bemenet
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}Használat:${NC}"
    echo -e "1. Felsorolás:  ./multi_check.sh google.com doubleclick.net facebook.com"
    echo -e "2. Fájlból:     ./multi_check.sh lista.txt"
    exit 1
fi

# Bemenet kezelése: Ha az első paraméter egy létező fájl, onnan olvassuk
if [ -f "$1" ]; then
    DOMAINS=$(cat "$1")
    echo -e "${CYAN}Fájl feldolgozása: $1${NC}"
else
    DOMAINS="$@"
fi

echo -e "\n${CYAN}Indul az ellenőrzés...${NC}"
printf "%-35s | %-15s | %s\n" "DOMAIN" "STÁTUSZ" "OK / RÉSZLETEK"
echo "--------------------------------------------------------------------------------"

for RAW_DOMAIN in $DOMAINS; do
    # Domain tisztítása (http, / jelek levágása, üres sorok kihagyása)
    DOMAIN=$(echo "$RAW_DOMAIN" | sed -e 's|^[^/]*//||' -e 's|/.*$||' | xargs)
    
    if [ -z "$DOMAIN" ]; then continue; fi

    STATUS="UNKNOWN"
    MSG=""
    COLOR=$NC

    # 1. /etc/hosts ellenőrzés
    if grep -q " $DOMAIN" /etc/hosts || grep -q "	$DOMAIN" /etc/hosts; then
        STATUS="BLOKKOLVA"
        MSG="Helyi hosts fájl"
        COLOR=$GREEN
    else
        # 2. DNS ellenőrzés (0.0.0.0)
        IP=$(dig +short +time=1 +tries=1 $DOMAIN | head -n 1)

        if [ "$IP" == "0.0.0.0" ] || [ "$IP" == "127.0.0.1" ]; then
            STATUS="BLOKKOLVA"
            MSG="DNS (Pi-hole/AdGuard)"
            COLOR=$GREEN
        elif [ -z "$IP" ]; then
            # Ha nincs IP, lehet, hogy csak nem létezik, vagy DNS szinten dobták
            STATUS="NEM TALÁLHATÓ"
            MSG="Nincs DNS rekord"
            COLOR=$YELLOW
        else
            # 3. Kapcsolódási teszt (Ha van IP, próbáljunk csatlakozni)
            # -m 2: max 2 másodperc várakozás
            curl -I -m 2 "http://$DOMAIN" &> /dev/null
            RET=$?
            
            if [ $RET -ne 0 ]; then
                STATUS="BLOKKOLVA?"
                MSG="Szerver nem válaszol (IP: $IP)"
                COLOR=$GREEN
            else
                STATUS="ELÉRHETŐ"
                MSG="Sikeres kapcsolat (IP: $IP)"
                COLOR=$RED
            fi
        fi
    fi

    # Eredmény kiírása egy sorban
    printf "%-35s | ${COLOR}%-15s${NC} | %s\n" "$DOMAIN" "$STATUS" "$MSG"

done

echo "--------------------------------------------------------------------------------"
echo -e "${CYAN}Ellenőrzés befejezve.${NC}\n"
