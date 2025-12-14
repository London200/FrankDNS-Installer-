#!/bin/bash
set -euo pipefail

# ==============================================================================
#  FRANKDNS SUITE v8.4 - EASY VIEW EDITION
#  Javítva: A lista nézegető (2-es gomb) most már kiírja a képernyő aljára,
#  hogy "Nyomj Q-t a kilépéshez", így nem ragadsz bent.
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
NEW_BATCH="$WORK_DIR/new_batch.txt"
DELETE_QUEUE="$WORK_DIR/delete_queue.txt"

# Színek
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1m'
N='\033[0m'

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

# --- BÁNYÁSZ MOTOR (BULK MÓD) ---
scrape() {
    clear
    echo -e "${C}=== TÖMEGES URL FELDOLGOZÓ ===${N}"
    echo -e "${Y}1. Másold be ide a linkeket (jöhet mind egyszerre!).${N}"
    echo -e "${Y}2. Ha végeztél, nyomj egy ÜRES ENTER-t az indításhoz.${N}"
    echo ""
    echo -e "${W}Várom a linkeket...${N}"

    if [[ -f "$LIST_FILE" ]]; then old_count=$(wc -l < "$LIST_FILE"); else old_count=0; fi

    raw_input=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        raw_input="$raw_input $line"
    done

    if [[ -z "$raw_input" ]]; then return; fi

    echo ""
    echo -e "${B}🚀 Feldolgozás indítása...${N}"

    for url in $raw_input; do
        if [[ "$url" != http* ]]; then continue; fi

        echo -e "   ⬇️  Letöltés: $url"
        content=$(curl -s --connect-timeout 8 -L "$url")
        if [[ -z "$content" ]]; then 
            echo -e "${R}      Hiba: Nem elérhető.${N}"
            continue 
        fi
        
        echo "$content" > "$TEMP_FILE"
        
        js_links=$(echo "$content" | grep -oE 'src="[^"]+\.js"' | cut -d'"' -f2)
        if [[ -n "$js_links" ]]; then
            for js in $js_links; do
                if [[ "$js" == http* ]]; then full="$js"; else
                    base=$(echo "$url" | sed 's|/$||'); clean=$(echo "$js" | sed 's|^/||'); full="${base}/${clean}"
                fi
                curl -s "$full" >> "$TEMP_FILE" || true
            done
        fi

        grep -oE '([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}' "$TEMP_FILE" | sort -u > "$WORK_DIR/raw.txt"
        
        grep -vE '\.(html|png|jpg|css|js|xml|php|ico|svg|woff)$' "$WORK_DIR/raw.txt" | \
        grep -vE '\.(length|width|height|click|push|pop|shift|join|map|filter|reduce|bind|call|apply|style|inner|outer|top|left|right|bottom)$' | \
        grep -vE '^(e\.|t\.|n\.|m\.|f\.|this\.|window\.|console\.)' | \
        grep -E '\.(com|net|org|hu|eu|info|io|co|uk|de|ru|cn|biz|top|xyz|site|online|tech|store|shop)$' > "$NEW_BATCH"

        source_domain=$(echo "$url" | awk -F/ '{print $3}')
        if [[ -n "$source_domain" ]]; then 
            grep -vF "$source_domain" "$NEW_BATCH" > "${NEW_BATCH}.tmp" && mv "${NEW_BATCH}.tmp" "$NEW_BATCH"
        fi

        if [[ -f "$LIST_FILE" ]]; then
            cat "$LIST_FILE" "$NEW_BATCH" | sort -u > "${LIST_FILE}.merged"
            mv "${LIST_FILE}.merged" "$LIST_FILE"
        else
            mv "$NEW_BATCH" "$LIST_FILE"
        fi
    done

    if [[ -f "$LIST_FILE" ]]; then
        new_total=$(wc -l < "$LIST_FILE")
        added=$((new_total - old_count))
        echo ""
        echo -e "${G}✅ MINDEN KÉSZ!${N}"
        echo -e "Hozzáadva: ${W}+$added${N} új domain."
        echo -e "Teljes adatbázis: ${W}$new_total${N} db."
    else
        echo -e "${R}Nem lett semmi letöltve.${N}"
        return
    fi
    
    advanced_filter
}

# --- SZELEKTÍV SZŰRŐ ---
advanced_filter() {
    while true; do
        total=$(wc -l < "$LIST_FILE")
        echo ""
        echo -e "${C}========================================${N}"
        echo -e "Adatbázis mérete: ${W}$total${N} db domain."
        echo -e "${Y}Keresés és Törlés (Számok alapján):${N}"
        echo -e "Írj be egy keresőszót (pl. google), vagy ENTER a továbblépéshez."
        read -rp "Keresés > " query

        if [[ -z "$query" ]]; then break; fi

        mapfile -t matches < <(grep "$query" "$LIST_FILE" | head -20)
        match_count=$(grep -c "$query" "$LIST_FILE" || true)

        if [[ "$match_count" -eq 0 ]]; then
            echo -e "${R}Nincs találat.${N}"
            continue
        fi

        echo -e "${B}Találatok ($match_count db):${N}"
        echo "--------------------------------"
        i=1
        for m in "${matches[@]}"; do
            echo -e " [${W}$i${N}] $m"
            ((i++))
        done
        if [[ "$match_count" -gt 20 ]]; then echo "... és még $((match_count - 20)) db"; fi
        echo "--------------------------------"
        
        echo -e "${Y}Melyik számokat töröljük?${N}"
        echo -e " - Pl: ${W}1 3 5${N} (vagy: ${R}all${N} ha mindet)"
        echo -e " - ENTER ha egyiket sem."
        read -rp "Választás > " selection

        if [[ -z "$selection" ]]; then continue; fi

        if [[ "$selection" == "all" ]]; then
            grep -v "$query" "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
            echo -e "${G}✅ Minden '$query' találat törölve!${N}"
        else
            rm -f "$DELETE_QUEUE"
            for id in $selection; do
                if [[ "$id" =~ ^[0-9]+$ ]] && [ "$id" -le "${#matches[@]}" ] && [ "$id" -gt 0 ]; then
                    domain_to_del="${matches[$((id-1))]}"
                    echo "$domain_to_del" >> "$DELETE_QUEUE"
                fi
            done

            if [[ -f "$DELETE_QUEUE" ]]; then
                grep -vFf "$DELETE_QUEUE" "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
                echo -e "${G}✅ Kijelölt domainek törölve!${N}"
                rm "$DELETE_QUEUE"
            fi
        fi
    done
    upload_menu
}

# --- SZERVER MŰVELETEK ---
upload_menu() {
    if [[ ! -f "$LIST_FILE" ]]; then return; fi
    count=$(wc -l < "$LIST_FILE")
    
    echo ""
    echo -e "${W}Mit tegyünk a ${count} db domainnel?${N}"
    echo -e " [1] ${R}🚫 Blokkolás (Feketelista)${N}"
    echo -e " [2] ${G}✅ Engedélyezés (Fehérlista)${N}"
    echo -e " [0] Mégse (Csak mentés fájlba)"
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

# --- JAVÍTOTT LISTA NÉZEGETŐ ---
view_list() {
    clear
    if [[ -f "$LIST_FILE" ]]; then
        count=$(wc -l < "$LIST_FILE")
        echo -e "${C}Lista tartalma ($count db):${N}"
        echo -e "${Y}Görgess a nyilakkal. Kilépéshez nyomd meg a 'q' betűt!${N}"
        echo "------------------------------------------------"
        read -rp "Nyomj ENTER-t a lista megnyitásához..."
        
        # ITT A JAVÍTÁS:
        # A -e kapcsoló miatt a végénél, ha nyomsz még egy entert, kilép.
        # A -P kapcsoló kiírja az aljára, hogy mit kell nyomni.
        less -e -P "--- VÉGE (Nyomj Q-t a kilépéshez!) ---" "$LIST_FILE"
        
        echo ""
        echo "------------------------------------------------"
        echo -e "${G}Kiléptél a listából.${N}"
    else
        echo -e "${R}A lista üres.${N}"
    fi
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
    echo -e "${C}║${N}    ${W}FRANKDNS v8.4 - EASY VIEW${N}          ${C}║${N}"
    echo -e "${C}╚═══════════════════════════════════════╝${N}"
    echo ""
    echo -e "${W}--- BÁNYÁSZAT (Automata Tömeges Mód) ---${N}"
    echo -e " [1] ${G}🌐 TÖMEGES URL Beillesztés & Feldolgozás${N}"
    echo -e " [2] 📋 Lista megtekintése"
    echo -e " [3] 📂 Mappa megnyitása"
    echo -e " [4] 🗑️  Teljes lista törlése (Újraindítás)"
    echo ""
    echo -e "${W}--- SZERVER MŰVELETEK ---${N}"
    echo -e " [5] ☁️  Manuális Feltöltés (Hozzáadás)"
    echo -e " [6] 🔄 ${Y}Szerver Frissítése (Update)${N}"
    echo -e " [7] 🗑️  Jelenlegi fájl törlése"
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
