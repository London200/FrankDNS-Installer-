#!/bin/bash
set -euo pipefail

################################################################################
#  FRANKDNS+ 2026 - LISTA KEZELŐ v3.0
#
#  FUNKCIÓK:
#    • Bármilyen reklám lista letöltése URL-ből
#    • Közvetlen FrankDNS+ szerver integráció
#    • Domain ellenőrzés (blokkolva/engedélyezve)
#    • Whitelist/Blacklist kezelés
#    • AdGuard formátum támogatás
#
################################################################################

# Színek
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

################################
# KONFIGURÁCIÓ
################################
FRANKDNS_SERVER="192.168.3.143"
FRANKDNS_PORT="8000"
FRANKDNS_API="http://${FRANKDNS_SERVER}:${FRANKDNS_PORT}/api"

BASE="/home/robot_36/frankdns-lists"
DATA="$BASE/data"
TMP="$DATA/tmp"

# Domain regex
DOMAIN_RE='([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}'

################################
# INICIALIZÁLÁS
################################
init() {
    mkdir -p "$DATA" "$TMP"
    
    # Telepítsd a szükséges csomagokat ha hiányoznak
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}📦 jq telepítése...${NC}"
        sudo apt-get install -y jq 2>/dev/null || true
    fi
    
    if ! command -v dig &> /dev/null; then
        echo -e "${YELLOW}📦 dnsutils telepítése...${NC}"
        sudo apt-get install -y dnsutils 2>/dev/null || true
    fi
}

################################
# FRANKDNS+ KAPCSOLAT ELLENŐRZÉS
################################
check_frankdns() {
    echo -e "${CYAN}🔗 FrankDNS+ kapcsolat ellenőrzése...${NC}"
    
    if curl -s --connect-timeout 5 "${FRANKDNS_API}/stats" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ FrankDNS+ elérhető: ${FRANKDNS_SERVER}:${FRANKDNS_PORT}${NC}"
        return 0
    else
        echo -e "${RED}❌ FrankDNS+ nem elérhető!${NC}"
        echo -e "${YELLOW}   Ellenőrizd: sudo systemctl status frankdnsplus${NC}"
        return 1
    fi
}

################################
# DOMAIN LETÖLTÉSE WEBOLDALRÓL
################################
download_domains_from_url() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}      ${BOLD}🌐 DOMAIN LETÖLTÉSE WEBOLDALRÓL / URL-BŐL${NC}           ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Példa URL-ek:${NC}"
    echo "  • https://superadblocktest.com"
    echo "  • https://d3ward.github.io/toolz/adblock.html"
    echo "  • https://adblock.turtlecute.org"
    echo "  • Bármilyen TXT lista URL"
    echo ""
    
    read -rp "URL: " url
    
    if [[ -z "$url" ]]; then
        echo -e "${RED}❌ Üres URL${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo ""
    echo -e "${BLUE}📥 Tartalom letöltése...${NC}"
    
    # Letöltjük a tartalmát
    local content
    content=$(curl -Ls --connect-timeout 15 --max-time 60 "$url" 2>/dev/null)
    
    if [[ -z "$content" ]]; then
        echo -e "${RED}❌ Nem sikerült letölteni!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    # Domainek kinyerése
    local domains_file="$TMP/extracted_domains.txt"
    echo "$content" | tr 'A-Z' 'a-z' | grep -oE "$DOMAIN_RE" | sort -u > "$domains_file"
    
    local total
    total=$(wc -l < "$domains_file")
    
    if [[ "$total" -eq 0 ]]; then
        echo -e "${RED}❌ Nem találtam domaineket!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo -e "${GREEN}✅ Találtam $total egyedi domaint!${NC}"
    echo ""
    
    # Szűrjük - csak a reklám/tracking domaineket tartjuk meg
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Talált domainek (első 30):${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    head -30 "$domains_file" | cat -n
    if [[ "$total" -gt 30 ]]; then
        echo "  ... és még $((total - 30)) domain"
    fi
    echo ""
    
    # Kérdezzük meg mit csináljunk
    echo -e "${YELLOW}Mit szeretnél csinálni?${NC}"
    echo ""
    echo "  [1] 🚫 ÖSSZES hozzáadása FEKETELISTÁHOZ ($total domain)"
    echo "  [2] ✅ ÖSSZES hozzáadása FEHÉRLISTÁHOZ ($total domain)"
    echo "  [3] 🔍 Egyenként átnézni és választani"
    echo "  [4] 📋 Csak mentés fájlba (nem küldöm a szervernek)"
    echo "  [0] ❌ Mégse"
    echo ""
    read -rp "Választás: " choice
    
    case "$choice" in
        1)
            echo ""
            echo -e "${BLUE}Hozzáadás a feketelistához...${NC}"
            
            # Lekérjük a config-ot
            local config
            config=$(curl -s "${FRANKDNS_API}/config")
            
            # Hozzáadjuk az összes domaint
            local new_blacklist
            new_blacklist=$(echo "$config" | jq -r '.blacklist // []')
            
            while read -r d; do
                [[ -z "$d" ]] && continue
                new_blacklist=$(echo "$new_blacklist" | jq --arg d "$d" '. + [$d] | unique')
            done < "$domains_file"
            
            # Frissítjük
            local updated_config
            updated_config=$(echo "$config" | jq --argjson bl "$new_blacklist" '.blacklist = $bl')
            
            local response
            response=$(curl -s -X POST "${FRANKDNS_API}/config" \
                -H "Content-Type: application/json" \
                -d "$updated_config")
            
            if echo "$response" | grep -q '"status":"ok"'; then
                echo -e "${GREEN}✅ Sikeresen hozzáadva $total domain a feketelistához!${NC}"
            else
                echo -e "${RED}❌ Hiba: $response${NC}"
            fi
            ;;
        2)
            echo ""
            echo -e "${BLUE}Hozzáadás a fehérlistához...${NC}"
            
            local config
            config=$(curl -s "${FRANKDNS_API}/config")
            
            local new_whitelist
            new_whitelist=$(echo "$config" | jq -r '.whitelist // []')
            
            while read -r d; do
                [[ -z "$d" ]] && continue
                new_whitelist=$(echo "$new_whitelist" | jq --arg d "$d" '. + [$d] | unique')
            done < "$domains_file"
            
            local updated_config
            updated_config=$(echo "$config" | jq --argjson wl "$new_whitelist" '.whitelist = $wl')
            
            local response
            response=$(curl -s -X POST "${FRANKDNS_API}/config" \
                -H "Content-Type: application/json" \
                -d "$updated_config")
            
            if echo "$response" | grep -q '"status":"ok"'; then
                echo -e "${GREEN}✅ Sikeresen hozzáadva $total domain a fehérlistához!${NC}"
            else
                echo -e "${RED}❌ Hiba: $response${NC}"
            fi
            ;;
        3)
            echo ""
            echo -e "${CYAN}Egyenként átnézés (y = feketelistához, w = fehérlistához, n = kihagy, q = kilép):${NC}"
            echo ""
            
            local config
            config=$(curl -s "${FRANKDNS_API}/config")
            local new_blacklist new_whitelist
            new_blacklist=$(echo "$config" | jq -r '.blacklist // []')
            new_whitelist=$(echo "$config" | jq -r '.whitelist // []')
            
            local added_black=0
            local added_white=0
            
            while read -r d; do
                [[ -z "$d" ]] && continue
                read -rp "  $d [y/w/n/q]: " ans
                case "$ans" in
                    y|Y)
                        new_blacklist=$(echo "$new_blacklist" | jq --arg d "$d" '. + [$d] | unique')
                        ((added_black++))
                        echo -e "    ${RED}→ Feketelista${NC}"
                        ;;
                    w|W)
                        new_whitelist=$(echo "$new_whitelist" | jq --arg d "$d" '. + [$d] | unique')
                        ((added_white++))
                        echo -e "    ${GREEN}→ Fehérlista${NC}"
                        ;;
                    q|Q)
                        break
                        ;;
                    *)
                        echo -e "    ${YELLOW}→ Kihagyva${NC}"
                        ;;
                esac
            done < "$domains_file"
            
            # Mentés
            local updated_config
            updated_config=$(echo "$config" | jq --argjson bl "$new_blacklist" --argjson wl "$new_whitelist" '.blacklist = $bl | .whitelist = $wl')
            
            curl -s -X POST "${FRANKDNS_API}/config" \
                -H "Content-Type: application/json" \
                -d "$updated_config" > /dev/null
            
            echo ""
            echo -e "${GREEN}✅ Kész! Feketelista: +$added_black | Fehérlista: +$added_white${NC}"
            ;;
        4)
            local save_file="$DATA/downloaded_domains_$(date +%Y%m%d_%H%M%S).txt"
            cp "$domains_file" "$save_file"
            echo -e "${GREEN}✅ Mentve: $save_file${NC}"
            ;;
        *)
            echo -e "${YELLOW}Megszakítva.${NC}"
            ;;
    esac
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# TESZTELŐ OLDALAK GYORS IMPORT
################################
import_from_test_sites() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}      ${BOLD}⚡ TESZTELŐ OLDALAK GYORS IMPORT${NC}                    ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Válassz egy népszerű adblock tesztelő oldalt:${NC}"
    echo ""
    echo "  [1] 🔴 superadblocktest.com (összes reklám domain)"
    echo "  [2] 🟢 d3ward.github.io/toolz/adblock (részletes teszt)"
    echo "  [3] 🐢 adblock.turtlecute.org (vizuális teszt)"
    echo "  [4] 🔵 canyoublockit.com (alap teszt)"
    echo "  [5] 📋 Saját URL megadása"
    echo ""
    echo "  [0] Vissza"
    echo ""
    read -rp "Választás: " choice
    
    local url=""
    case "$choice" in
        1) url="https://superadblocktest.com" ;;
        2) url="https://d3ward.github.io/toolz/adblock.html" ;;
        3) url="https://adblock.turtlecute.org" ;;
        4) url="https://canyoublockit.com" ;;
        5) 
            read -rp "URL: " url
            ;;
        0) return ;;
        *) 
            echo -e "${RED}Érvénytelen választás${NC}"
            sleep 1
            return
            ;;
    esac
    
    if [[ -z "$url" ]]; then
        return
    fi
    
    echo ""
    echo -e "${BLUE}📥 Letöltés: $url${NC}"
    
    # Letöltjük az oldalt
    local content
    content=$(curl -Ls --connect-timeout 15 --max-time 60 "$url" 2>/dev/null)
    
    if [[ -z "$content" ]]; then
        echo -e "${RED}❌ Nem sikerült letölteni!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    # Kinyerjük a domaineket
    local domains
    domains=$(echo "$content" | tr 'A-Z' 'a-z' | grep -oE "$DOMAIN_RE" | \
        grep -vE "^(www\.)?(google\.com|facebook\.com|youtube\.com|github\.com|githubusercontent\.com|cloudflare\.com|jsdelivr\.net|superadblocktest\.com|d3ward\.github\.io|turtlecute\.org|canyoublockit\.com)$" | \
        sort -u)
    
    local count
    count=$(echo "$domains" | grep -c . || echo 0)
    
    echo -e "${GREEN}✅ Talált reklám domainek: $count db${NC}"
    echo ""
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "${YELLOW}Nem találtam új domaineket.${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    # Megmutatjuk a domaineket
    echo -e "${BLUE}Talált domainek:${NC}"
    echo "$domains" | head -30 | while read -r d; do echo "  • $d"; done
    if [[ "$count" -gt 30 ]]; then
        echo "  ... és még $((count - 30)) további"
    fi
    
    echo ""
    echo -e "${YELLOW}Hozzáadod a FEKETELISTÁHOZ? [i/n]${NC}"
    read -rp "> " confirm
    
    if [[ "$confirm" =~ ^[IiYy]$ ]]; then
        echo ""
        echo -e "${BLUE}Hozzáadás...${NC}"
        
        local config
        config=$(curl -s "${FRANKDNS_API}/config")
        
        local new_blacklist
        new_blacklist=$(echo "$config" | jq -r '.blacklist // []')
        
        while IFS= read -r d; do
            [[ -z "$d" ]] && continue
            new_blacklist=$(echo "$new_blacklist" | jq --arg d "$d" '. + [$d] | unique')
        done <<< "$domains"
        
        local updated_config
        updated_config=$(echo "$config" | jq --argjson bl "$new_blacklist" '.blacklist = $bl')
        
        local response
        response=$(curl -s -X POST "${FRANKDNS_API}/config" \
            -H "Content-Type: application/json" \
            -d "$updated_config")
        
        if echo "$response" | grep -q '"status":"ok"'; then
            echo -e "${GREEN}✅ Sikeresen hozzáadva $count domain!${NC}"
        else
            echo -e "${RED}❌ Hiba: $response${NC}"
        fi
    else
        echo -e "${YELLOW}Kihagyva.${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# DOMAIN HOZZÁADÁSA BLACKLIST-HEZ
################################
add_to_blacklist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}🚫 DOMAIN HOZZÁADÁSA FEKETELISTÁHOZ${NC}             ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Add meg a domaineket (minden sorba egyet, üres sor = vége):${NC}"
    echo ""
    
    local domains=()
    while true; do
        read -rp "> " domain
        [[ -z "$domain" ]] && break
        domains+=("$domain")
    done
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Nem adtál meg domaint.${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo ""
    echo -e "${BLUE}Hozzáadás a FrankDNS+ feketelistához...${NC}"
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    if [[ -z "$config" ]]; then
        echo -e "${RED}❌ Nem sikerült lekérni a config-ot!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    local new_blacklist
    new_blacklist=$(echo "$config" | jq -r '.blacklist // []')
    
    for d in "${domains[@]}"; do
        new_blacklist=$(echo "$new_blacklist" | jq --arg d "$d" '. + [$d] | unique')
    done
    
    local updated_config
    updated_config=$(echo "$config" | jq --argjson bl "$new_blacklist" '.blacklist = $bl')
    
    local response
    response=$(curl -s -X POST "${FRANKDNS_API}/config" \
        -H "Content-Type: application/json" \
        -d "$updated_config")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Sikeresen hozzáadva ${#domains[@]} domain!${NC}"
        for d in "${domains[@]}"; do
            echo -e "   ${GREEN}✓${NC} $d"
        done
    else
        echo -e "${RED}❌ Hiba történt: $response${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# DOMAIN HOZZÁADÁSA WHITELIST-HEZ
################################
add_to_whitelist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}✅ DOMAIN HOZZÁADÁSA FEHÉRLISTÁHOZ${NC}              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Add meg a domaineket (minden sorba egyet, üres sor = vége):${NC}"
    echo ""
    
    local domains=()
    while true; do
        read -rp "> " domain
        [[ -z "$domain" ]] && break
        domains+=("$domain")
    done
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Nem adtál meg domaint.${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo ""
    echo -e "${BLUE}Hozzáadás a FrankDNS+ fehérlistához...${NC}"
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    if [[ -z "$config" ]]; then
        echo -e "${RED}❌ Nem sikerült lekérni a config-ot!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    local new_whitelist
    new_whitelist=$(echo "$config" | jq -r '.whitelist // []')
    
    for d in "${domains[@]}"; do
        new_whitelist=$(echo "$new_whitelist" | jq --arg d "$d" '. + [$d] | unique')
    done
    
    local updated_config
    updated_config=$(echo "$config" | jq --argjson wl "$new_whitelist" '.whitelist = $wl')
    
    local response
    response=$(curl -s -X POST "${FRANKDNS_API}/config" \
        -H "Content-Type: application/json" \
        -d "$updated_config")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Sikeresen hozzáadva ${#domains[@]} domain!${NC}"
        for d in "${domains[@]}"; do
            echo -e "   ${GREEN}✓${NC} $d"
        done
    else
        echo -e "${RED}❌ Hiba történt: $response${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# DOMAIN ELLENŐRZÉS (DNS)
################################
check_domain() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              ${BOLD}🔍 DOMAIN ELLENŐRZÉS${NC}                         ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Írd be a domaineket (szóközzel, vesszővel, vagy új sorral elválasztva):${NC}"
    echo -e "${YELLOW}Majd nyomj ENTER-t kétszer a befejezéshez.${NC}"
    echo ""
    
    # Beolvassuk az összes inputot
    local input=""
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        input="$input $line"
    done
    
    if [[ -z "$input" ]]; then
        echo -e "${YELLOW}Nem adtál meg domaint.${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    # Feldolgozzuk: vesszőket és szóközöket új sorra cseréljük, majd kinyerjük a domaineket
    local domains_file="$TMP/check_domains.txt"
    echo "$input" | tr ',' ' ' | tr -s ' ' '\n' | tr 'A-Z' 'a-z' | grep -oE "$DOMAIN_RE" | sort -u > "$domains_file"
    
    local count
    count=$(wc -l < "$domains_file")
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}Nem találtam érvényes domaint!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  EREDMÉNY (DNS szerver: $FRANKDNS_SERVER) - $count domain${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local blocked=0
    local allowed=0
    
    # Fájlból olvassuk, nem pipe-ból - így nem szakad meg
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        local result
        result=$(dig +short "$d" @"$FRANKDNS_SERVER" 2>/dev/null | head -n1)
        
        if [[ -z "$result" || "$result" == "0.0.0.0" || "$result" == "::" ]]; then
            echo -e "  ${GREEN}🚫 BLOKKOLVA${NC}    → $d"
            ((blocked++))
        else
            echo -e "  ${RED}✅ ENGEDÉLYEZVE${NC} → $d (IP: $result)"
            ((allowed++))
        fi
    done < "$domains_file"
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "  Összesen: ${GREEN}$blocked blokkolva${NC} | ${RED}$allowed engedélyezve${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# GYORS TESZT
################################
quick_test() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}⚡ GYORS REKLÁMBLOKKOLÁS TESZT${NC}                  ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Teszt domainek fájlba
    local test_file="$TMP/quick_test.txt"
    cat > "$test_file" << 'TESTEOF'
pagead2.googlesyndication.com
googleads.g.doubleclick.net
adservice.google.com
analytics.google.com
pixel.facebook.com
an.facebook.com
ads.facebook.com
ads.unity3d.com
unityads.unity3d.com
static.media.net
adcolony.com
app-measurement.com
crashlytics.com
facebook.com
google.com
youtube.com
TESTEOF
    
    local total
    total=$(wc -l < "$test_file")
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  TESZT EREDMÉNYEK (DNS: $FRANKDNS_SERVER) - $total domain${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local blocked=0
    local allowed=0
    
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        local result
        result=$(dig +short "$d" @"$FRANKDNS_SERVER" 2>/dev/null | head -n1)
        
        if [[ -z "$result" || "$result" == "0.0.0.0" || "$result" == "::" ]]; then
            echo -e "  ${GREEN}🚫 BLOKKOLVA${NC}    → $d"
            ((blocked++))
        else
            echo -e "  ${RED}✅ ENGEDÉLYEZVE${NC} → $d"
            ((allowed++))
        fi
    done < "$test_file"
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}Blokkolva: $blocked${NC} | ${RED}Engedélyezve: $allowed${NC}"
    echo ""
    
    local pct=$((blocked * 100 / total))
    if [[ $pct -ge 80 ]]; then
        echo -e "  ${GREEN}🎉 KIVÁLÓ! $pct% blokkolva${NC}"
    elif [[ $pct -ge 50 ]]; then
        echo -e "  ${YELLOW}⚠️ KÖZEPES: $pct% blokkolva${NC}"
    else
        echo -e "  ${RED}❌ GYENGE: $pct% blokkolva${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# JELENLEGI LISTÁK MEGTEKINTÉSE
################################
view_current_lists() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}📊 FRANKDNS+ JELENLEGI BEÁLLÍTÁSOK${NC}              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    if [[ -z "$config" ]]; then
        echo -e "${RED}❌ Nem sikerült lekérni a config-ot!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📋 SZŰRŐLISTÁK:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "$config" | jq -r '.blocklists[] | "  [\(if .enabled then "BE" else "KI" end)] \(.name)"' 2>/dev/null || echo "  (nincs)"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ FEHÉRLISTA (Whitelist):${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    local whitelist
    whitelist=$(echo "$config" | jq -r '.whitelist[]' 2>/dev/null)
    if [[ -n "$whitelist" ]]; then
        echo "$whitelist" | while read -r d; do echo "  • $d"; done
    else
        echo "  (üres)"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}🚫 FEKETELISTA (Blacklist):${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    local blacklist
    blacklist=$(echo "$config" | jq -r '.blacklist[]' 2>/dev/null)
    if [[ -n "$blacklist" ]]; then
        echo "$blacklist" | while read -r d; do echo "  • $d"; done
    else
        echo "  (üres)"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📈 STATISZTIKA:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local stats
    stats=$(curl -s "${FRANKDNS_API}/stats")
    local database blocked total
    database=$(echo "$stats" | jq -r '.database // 0')
    blocked=$(echo "$stats" | jq -r '.blocked // 0')
    total=$(echo "$stats" | jq -r '.total // 0')
    
    echo "  • Adatbázis méret: $database domain"
    echo "  • Összes kérés: $total"
    echo "  • Blokkolva: $blocked"
    
    echo ""
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# SZŰRŐLISTA HOZZÁADÁSA
################################
add_blocklist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}        ${BOLD}➕ ÚJ SZŰRŐLISTA HOZZÁADÁSA${NC}                       ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Népszerű listák:${NC}"
    echo "  1. AdGuard DNS Popup Hosts filter"
    echo "  2. AdGuard DNS filter (59)"
    echo "  3. HUN: Hufilter"
    echo "  4. OISD Big"
    echo "  5. 1Hosts Pro"
    echo "  6. Egyedi URL megadása"
    echo ""
    
    read -rp "Választás [1-6]: " choice
    
    local name url
    case "$choice" in
        1)
            name="AdGuard DNS Popup Hosts filter"
            url="https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"
            ;;
        2)
            name="AdGuard DNS filter"
            url="https://adguardteam.github.io/HostlistsRegistry/assets/filter_59.txt"
            ;;
        3)
            name="HUN: Hufilter"
            url="https://adguardteam.github.io/HostlistsRegistry/assets/filter_35.txt"
            ;;
        4)
            name="OISD Big"
            url="https://big.oisd.nl/domainswild"
            ;;
        5)
            name="1Hosts Pro"
            url="https://raw.githubusercontent.com/badmojr/1Hosts/master/Pro/adblock.txt"
            ;;
        6)
            read -rp "Lista neve: " name
            read -rp "Lista URL: " url
            ;;
        *)
            echo -e "${RED}Érvénytelen választás${NC}"
            read -rp "Nyomj ENTER-t a folytatáshoz..." _
            return
            ;;
    esac
    
    if [[ -z "$name" || -z "$url" ]]; then
        echo -e "${RED}Hiányzó adatok!${NC}"
        read -rp "Nyomj ENTER-t a folytatáshoz..." _
        return
    fi
    
    echo ""
    echo -e "${BLUE}Hozzáadás: $name${NC}"
    echo -e "${BLUE}URL: $url${NC}"
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    local new_blocklist
    new_blocklist=$(echo "$config" | jq --arg name "$name" --arg url "$url" \
        '.blocklists += [{"name": $name, "url": $url, "enabled": true}]')
    
    local response
    response=$(curl -s -X POST "${FRANKDNS_API}/config" \
        -H "Content-Type: application/json" \
        -d "$new_blocklist")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Lista hozzáadva: $name${NC}"
        echo ""
        echo -e "${YELLOW}⚠️ Frissítés indítása...${NC}"
        curl -s -X POST "${FRANKDNS_API}/update_blocklists" > /dev/null
        echo -e "${GREEN}✅ Frissítés elindult a háttérben!${NC}"
    else
        echo -e "${RED}❌ Hiba: $response${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# LISTA FRISSÍTÉS
################################
refresh_lists() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}🔄 SZŰRŐLISTÁK FRISSÍTÉSE${NC}                       ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}Listák frissítése...${NC}"
    
    local response
    response=$(curl -s -X POST "${FRANKDNS_API}/update_blocklists")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Frissítés elindítva!${NC}"
        echo ""
        echo -e "${CYAN}A frissítés a háttérben fut. Nézd a logot:${NC}"
        echo -e "  sudo journalctl -u frankdnsplus -f"
    else
        echo -e "${RED}❌ Hiba: $response${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# SZŰRŐLISTA TÖRLÉSE
################################
remove_blocklist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}🗑️  SZŰRŐLISTA TÖRLÉSE${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    echo -e "${BLUE}Jelenlegi szűrőlisták:${NC}"
    echo "$config" | jq -r '.blocklists | to_entries[] | "  \(.key + 1). \(.value.name)"' 2>/dev/null
    
    echo ""
    read -rp "Törlendő lista sorszáma (0 = mégse): " num
    
    if [[ "$num" == "0" || -z "$num" ]]; then
        return
    fi
    
    local index=$((num - 1))
    local updated_config
    updated_config=$(echo "$config" | jq "del(.blocklists[$index])")
    
    local response
    response=$(curl -s -X POST "${FRANKDNS_API}/config" \
        -H "Content-Type: application/json" \
        -d "$updated_config")
    
    if echo "$response" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Lista törölve!${NC}"
    else
        echo -e "${RED}❌ Hiba: $response${NC}"
    fi
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# BLACKLIST KEZELÉSE
################################
clear_blacklist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}🗑️  FEKETELISTA KEZELÉSE${NC}                        ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    echo -e "${BLUE}Jelenlegi feketelista:${NC}"
    echo "$config" | jq -r '.blacklist[]' 2>/dev/null | cat -n || echo "  (üres)"
    
    echo ""
    echo "[1] Egy domain törlése"
    echo "[2] Összes törlése"
    echo "[0] Vissza"
    read -rp "Választás: " choice
    
    case "$choice" in
        1)
            read -rp "Törlendő domain: " domain
            if [[ -n "$domain" ]]; then
                local updated_config
                updated_config=$(echo "$config" | jq --arg d "$domain" '.blacklist -= [$d]')
                curl -s -X POST "${FRANKDNS_API}/config" \
                    -H "Content-Type: application/json" \
                    -d "$updated_config" > /dev/null
                echo -e "${GREEN}✅ Törölve: $domain${NC}"
            fi
            ;;
        2)
            local updated_config
            updated_config=$(echo "$config" | jq '.blacklist = []')
            curl -s -X POST "${FRANKDNS_API}/config" \
                -H "Content-Type: application/json" \
                -d "$updated_config" > /dev/null
            echo -e "${GREEN}✅ Feketelista kiürítve!${NC}"
            ;;
    esac
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# WHITELIST KEZELÉSE
################################
clear_whitelist() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}🗑️  FEHÉRLISTA KEZELÉSE${NC}                         ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local config
    config=$(curl -s "${FRANKDNS_API}/config")
    
    echo -e "${BLUE}Jelenlegi fehérlista:${NC}"
    echo "$config" | jq -r '.whitelist[]' 2>/dev/null | cat -n || echo "  (üres)"
    
    echo ""
    echo "[1] Egy domain törlése"
    echo "[2] Összes törlése"
    echo "[0] Vissza"
    read -rp "Választás: " choice
    
    case "$choice" in
        1)
            read -rp "Törlendő domain: " domain
            if [[ -n "$domain" ]]; then
                local updated_config
                updated_config=$(echo "$config" | jq --arg d "$domain" '.whitelist -= [$d]')
                curl -s -X POST "${FRANKDNS_API}/config" \
                    -H "Content-Type: application/json" \
                    -d "$updated_config" > /dev/null
                echo -e "${GREEN}✅ Törölve: $domain${NC}"
            fi
            ;;
        2)
            local updated_config
            updated_config=$(echo "$config" | jq '.whitelist = []')
            curl -s -X POST "${FRANKDNS_API}/config" \
                -H "Content-Type: application/json" \
                -d "$updated_config" > /dev/null
            echo -e "${GREEN}✅ Fehérlista kiürítve!${NC}"
            ;;
    esac
    
    read -rp "Nyomj ENTER-t a folytatáshoz..." _
}

################################
# FŐ MENÜ
################################
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}     ${BOLD}🛡️  FrankDNS+ Lista Kezelő v3.0${NC}                     ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}     ${CYAN}Szerver: $FRANKDNS_SERVER:$FRANKDNS_PORT${NC}                        ${GREEN}║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${CYAN}[1]${NC} 📊 Jelenlegi beállítások megtekintése              ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${YELLOW}[2]${NC} ➕ Szűrőlista hozzáadása                           ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${YELLOW}[3]${NC} 🗑️  Szűrőlista törlése                             ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${YELLOW}[4]${NC} 🔄 Listák frissítése                               ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${NC}[W]${NC} 🌐 Webes felület (böngészőben)                     ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${RED}[0]${NC} ❌ Kilépés                                         ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -rp "Választás: " C
        
        case "$C" in
            1) view_current_lists ;;
            2) add_blocklist ;;
            3) remove_blocklist ;;
            4) refresh_lists ;;
            [Ww])
                echo -e "${CYAN}Nyisd meg a böngészőben: http://$FRANKDNS_SERVER:$FRANKDNS_PORT${NC}"
                read -rp "Nyomj ENTER-t a folytatáshoz..." _
                ;;
            0)
                echo -e "${GREEN}👋 Viszlát!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Érvénytelen választás${NC}"
                sleep 1
                ;;
        esac
    done
}

################################
# INDÍTÁS
################################
init
check_frankdns || true
main_menu
