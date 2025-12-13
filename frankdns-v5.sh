#!/bin/bash
set -euo pipefail

# ==============================================================================
#  FRANKDNS SUITE v5.1 - USER FRIENDLY LIST
#  Javítva: A lista nézegető (2-es gomb) most már egyértelműen jelzi,
#  hogyan lépj vissza, és nem ragadsz benne az (END) képernyőn.
# ==============================================================================

# --- KONFIGURÁCIÓ ---
SERVER_IP="192.168.3.143"
PORT="8000"
API_URL="http://${SERVER_IP}:${PORT}/api"

# Útvonalak
BASE_DIR="/home/robot_36"
WORK_DIR="$BASE_DIR/frankdns-banyasz"
LIST_FILE="$WORK_DIR/extracted_domains.txt"
TEMP_FILE="$WORK_DIR/temp_raw.txt"

# Színek
R='\033[0;31m' # Piros
G='\033[0;32m' # Zöld
Y='\033[1;33m' # Sárga
B='\033[0;34m' # Kék
C='\033[0;36m' # Cián
W='\033[1m'    # Fehér/Félkövér
N='\033[0m'    # Nincs szín

# --- RENDSZER ELLENŐRZÉS ---
setup() {
    mkdir -p "$WORK_DIR"
    if [ ! -w "$WORK_DIR" ]; then
        echo -e "${Y}Jogosultság javítása...${N}"
        sudo chown -R $USER:$USER "$BASE_DIR"
        sudo chmod -R 755 "$BASE_DIR"
    fi
    if ! command -v jq &> /dev/null; then sudo apt-get install -y jq >/dev/null 2>&1 || true; fi
    if ! command -v dig &> /dev/null; then sudo apt-get install -y dnsutils >/dev/null 2>&1 || true; fi
}

# --- BÁNYÁSZ MOTOR ---
scrape() {
    clear
    echo -e "${C}=== URL LETÖLTÉS ÉS TAKARÍTÁS ===${N}"
    echo -e "${Y}Add meg az URL-t (pl. https://adblock.turtlecute.org):${N}"
    read -rp "> " url
    [[ -z "$url" ]] && return

    echo -e "${B}Letöltés...${N}"
    content=$(curl -s --connect-timeout 10 -L "$url")
    if [[ -z "$content" ]]; then echo -e "${R}Hiba: Üres válasz!${N}"; sleep 2; return; fi
    
    echo "$content" > "$TEMP_FILE"
    
    # JS fájlok keresése
    js_links=$(echo "$content" | grep -oE 'src="[^"]+\.js"' | cut -d'"' -f2)
    for js in $js_links; do
        if [[ "$js" == http* ]]; then full="$js"; else
            base=$(echo "$url" | sed 's|/$||'); clean=$(echo "$js" | sed 's|^/||'); full="${base}/${clean}"
        fi
        echo -e "JS elemzése: $clean"
        curl -s "$full" >> "$TEMP_FILE"
    done

    echo -e "${B}Takarítás...${N}"
    grep -oE '([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}' "$TEMP_FILE" | sort -u > "$WORK_DIR/raw.txt"
    
    # Szűrés
    grep -vE '\.(html|png|jpg|css|js|xml|php|ico|svg|woff)$' "$WORK_DIR/raw.txt" | \
    grep -vE '\.(length|width|height|click|push|pop|shift|join|map|filter|reduce|bind|call|apply|style|inner|outer|top|left|right|bottom)$' | \
    grep -vE '^(e\.|t\.|n\.|m\.|f\.|this\.|window\.|console\.)' | \
    grep -E '\.(com|net|org|hu|eu|info|io|co|uk|de|ru|cn|biz|top|xyz|site|online|tech|store|shop)$' > "$LIST_FILE"

    source_domain=$(echo "$url" | awk -F/ '{print $3}')
    if [[ -n "$source_domain" ]]; then grep -vF "$source_domain" "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"; fi

    count=$(wc -l < "$LIST_FILE")
    echo -e "${G}KÉSZ! $count db tiszta domain.${N}"
    
    upload_menu
}

# --- SZERVER MŰVELETEK ---
upload_menu() {
    if [[ ! -f "$LIST_FILE" ]]; then echo -e "${R}Nincs lista!${N}"; sleep 1; return; fi
    count=$(wc -l < "$LIST_FILE")
    
    echo ""
    echo -e "${W}Mit tegyünk a ${count} domainnel?${N}"
    echo -e " [1] ${R}🚫 Blokkolás (Feketelista)${N}"
    echo -e " [2] ${G}✅ Engedélyezés (Fehérlista)${N}"
    echo -e " [0] Mégse"
    read -rp "> " c
    
    [[ "$c" == "0" ]] && return
    type="blacklist"
    [[ "$c" == "2" ]] && type="whitelist"
    
    echo -e "${B}Küldés a szervernek...${N}"
    cfg=$(curl -s "${API_URL}/config")
    curr=$(echo "$cfg" | jq -r ".$type // []")
    
    while read -r d; do curr=$(echo "$curr" | jq --arg d "$d" '. + [$d] | unique'); done < "$LIST_FILE"
    
    new_cfg=$(echo "$cfg" | jq --argjson l "$curr" ".$type = \$l")
    curl -s -X POST "${API_URL}/config" -H "Content-Type: application/json" -d "$new_cfg" > /dev/null
    
    echo -e "${G}Siker! Feltöltve.${N}"
    echo -e "${Y}Javaslat: Nyomj Frissítést a menüben!${N}"
    read -rp "Enter..."
}

delete_from_server() {
    clear
    echo -e "${R}=== VISSZAVONÁS (TÖRLÉS A SZERVERRŐL) ===${N}"
    if [[ ! -f "$LIST_FILE" ]]; then echo -e "${R}Nincs lista betöltve!${N}"; sleep 2; return; fi
    
    count=$(wc -l < "$LIST_FILE")
    echo -e "A listában lévő ${W}$count db${N} domaint fogom törölni a szerverről."
    echo ""
    echo -e " [1] ${R}🚫 Feketelistáról törlés${N}"
    echo -e " [2] ${G}✅ Fehérlistáról törlés${N}"
    echo -e " [0] Mégse"
    read -rp "> " c
    
    [[ "$c" == "0" ]] && return
    type="blacklist"
    [[ "$c" == "2" ]] && type="whitelist"
    
    echo -e "${B}Törlés folyamatban...${N}"
    cfg=$(curl -s "${API_URL}/config")
    curr=$(echo "$cfg" | jq -r ".$type // []")
    
    while read -r d; do curr=$(echo "$curr" | jq --arg d "$d" '. - [$d]'); done < "$LIST_FILE"
    
    new_cfg=$(echo "$cfg" | jq --argjson l "$curr" ".$type = \$l")
    curl -s -X POST "${API_URL}/config" -H "Content-Type: application/json" -d "$new_cfg" > /dev/null
    
    echo -e "${G}Kész! Törölve a szerverről.${N}"
    read -rp "Enter..."
}

update_server() {
    echo -e "${B}Szerver frissítése...${N}"
    curl -s -X POST "${API_URL}/update_blocklists" > /dev/null
    echo -e "${G}Frissítés elindult!${N}"
    sleep 1
}

# --- ITT A JAVÍTOTT LISTA NÉZEGETŐ ---
view_list() {
    clear
    if [[ -f "$LIST_FILE" ]]; then
        count=$(wc -l < "$LIST_FILE")
        echo -e "${C}Lista tartalma ($count db):${N}"
        echo -e "${Y}Görgess a nyilakkal. Kilépéshez nyomd meg a 'q' betűt!${N}"
        echo "------------------------------------------------"
        read -rp "Nyomj ENTER-t a lista megnyitásához..."
        
        # Megnyitjuk a less-t
        less "$LIST_FILE"
        
        # Ha kilépett a less-ből (q betűvel), akkor ide jön:
        echo ""
        echo "------------------------------------------------"
        echo -e "${G}Kiléptél a listából.${N}"
    else
        echo -e "${R}A lista üres.${N}"
    fi
    # Itt a visszalépés a menübe
    read -rp "Nyomj ENTER-t a menübe való visszalépéshez..."
}

reset_folder() {
    rm -rf "$WORK_DIR"/*
    echo "Törölve."
    sleep 1
}

# --- FŐMENÜ ---
while true; do
    clear
    echo -e "${C}╔═══════════════════════════════════════╗${N}"
    echo -e "${C}║${N}    ${W}FRANKDNS v5.1 - STABLE MENU${N}        ${C}║${N}"
    echo -e "${C}╚═══════════════════════════════════════╝${N}"
    echo ""
    echo -e "${W}--- BÁNYÁSZAT ---${N}"
    echo -e " [1] ${G}🌐 URL Letöltése & Elemzése${N}"
    echo -e " [2] 📋 Lista megtekintése"
    echo -e " [3] 📂 Mappa megnyitása"
    echo -e " [4] 🗑️  Helyi fájlok törlése (Reset)"
    echo ""
    echo -e "${W}--- SZERVER MŰVELETEK ---${N}"
    echo -e " [5] ☁️  Manuális Feltöltés (Hozzáadás)"
    echo -e " [6] 🔄 ${Y}Szerver Frissítése (Update)${N}"
    echo -e " [7] 🗑️  Jelenlegi lista fájl törlése"
    echo -e " [8] ${R}🔥 TÖRLÉS A SZERVERRŐL (Visszavonás)${N}"
    echo ""
    echo -e " [0] Kilépés"
    echo ""
    read -rp "Választás: " opt

    case "$opt" in
        1) scrape ;;
        2) view_list ;;
        3) ls -lh "$WORK_DIR"; read -rp "Enter..." ;;
        4) reset_folder ;;
        5) upload_menu ;;
        6) update_server ;;
        7) rm "$LIST_FILE"; echo "Törölve."; sleep 1 ;;
        8) delete_from_server ;;
        0) exit 0 ;;
    esac
done
