#!/bin/bash

# ================================
# 🚀 FŐ SCRIPT - MAXIMÁLIS LETÖLTÉS
# ================================

while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║   🚀 MAXIMÁLIS DOMAIN LETÖLTŐ       ║"
    echo "║   🌐 TÖBB FORRÁS TÁMOGATÁSSAL       ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "1. Új link letöltése (MAXIMÁLISAN)"
    echo "2. Előző eredmények"
    echo "3. Gyors letöltés előre definiált forrásokból"
    echo "4. Kilépés"
    echo ""
    read -p "Választás: " choice
    
    case $choice in
        1)
            echo ""
            echo "📋 PÉLDÁK:"
            echo "   • https://adblock.turtlecute.org"
            echo "   • https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
            echo "   • https://easylist.to/easylist/easylist.txt"
            echo "   • https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
            echo "   • https://www.example.com"
            echo ""
            read -p "🔗 Link: " LINK
            
            if [ -z "$LINK" ]; then
                echo "❌ Üres link!"
                sleep 2
                continue
            fi
            
            echo ""
            echo "🚀 MAXIMÁLIS LETÖLTÉS INDUL..."
            echo "⏳ Ez eltarthat 15-30 másodpercig..."
            
            # Fájlnév generálása
            TIMESTAMP=$(date +%s)
            OUTPUT_FILE="/home/robot_36/domain_${TIMESTAMP}.txt"
            
            # **MAXIMÁLIS LETÖLTÉS - 6 KÜLÖNBÖZŐ MÓDSZER**
            echo ""
            echo "🔍 MAXIMÁLIS DOMAIN KERESÉS (6 módszerrel)..."
            
            # Ideiglenes fájlok
            TEMP_DIR="/tmp/domain_download_${TIMESTAMP}"
            mkdir -p "$TEMP_DIR"
            
            # 1. MÓDSZER: Jina AI API teljes tartalommal
            echo "   1. Jina AI API (teljes tartalom)..."
            curl -s -H "X-With-Generated-Alt: true" \
                 -H "X-With-Links: true" \
                 -H "X-With-Markdown: true" \
                 -H "X-No-Cache: true" \
                 "https://r.jina.ai/$LINK" | \
            grep -oE '[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+\.[a-zA-Z]{2,}' | \
            sort -u > "${TEMP_DIR}/method1.txt"
            
            # 2. MÓDSZER: Közvetlen letöltés nagy timeout-tal
            echo "   2. Közvetlen letöltés (nagy timeout)..."
            curl -s -L --max-time 30 --retry 2 "$LINK" | \
            grep -oE '[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
            sort -u > "${TEMP_DIR}/method2.txt"
            
            # 3. MÓDSZER: WGET-tel (másik user agent)
            echo "   3. WGET alternatív módszer..."
            wget -q -T 20 -U "Mozilla/5.0" -O "${TEMP_DIR}/raw.html" "$LINK" 2>/dev/null
            cat "${TEMP_DIR}/raw.html" | \
            tr ' ' '\n' | tr '"' '\n' | tr "'" '\n' | tr '>' '\n' | tr '<' '\n' | tr '/' '\n' | \
            grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | \
            grep -v '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' | \
            sort -u > "${TEMP_DIR}/method3.txt"
            
            # 4. MÓDSZER: Python parser (legjobb domain kinyerés)
            echo "   4. Python parser (legjobb)..."
            python3 -c "
import re
import requests
import urllib3
import sys
from concurrent.futures import ThreadPoolExecutor
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

url = '$LINK'
output_file = '${TEMP_DIR}/method4.txt'

try:
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache'
    }
    
    session = requests.Session()
    session.headers.update(headers)
    
    # Letöltés
    response = session.get(url, timeout=20, verify=False)
    html = response.text
    
    # Különböző regex pattern-ek
    patterns = [
        # Alap domain minta
        r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}',
        # URL-ekből domain-ek
        r'https?://([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
        # HTML attribútumokból
        r'(?:href|src|data-url|data-src|action|cite)=\"[^\"]*?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
        # JavaScript változók
        r'[\'\"]([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})[\'\"]',
        # Külön sorban lévő domain-ek
        r'^[ \t]*([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})[ \t]*$'
    ]
    
    domains = set()
    for pattern in patterns:
        matches = re.findall(pattern, html, re.MULTILINE | re.IGNORECASE)
        domains.update(matches)
    
    # További domain-ek keresése a szövegben
    text_lines = html.split('\n')
    for line in text_lines:
        # Domain-ek pontok vagy vesszők után
        line_domains = re.findall(r'[^a-zA-Z0-9]([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})[^a-zA-Z0-9]', line)
        domains.update(line_domains)
    
    # Szűrés és tisztítás
    filtered = set()
    for domain in domains:
        domain = domain.strip().lower()
        if (len(domain) > 4 and 
            '.' in domain and 
            not domain.startswith(('http://', 'https://', '//', 'www.')) and
            not re.match(r'^\d+\.\d+\.\d+\.\d+$', domain) and
            not any(word in domain for word in ['example', 'test', 'localhost', 'domain', 'yourdomain'])):
            # Normalizálás: www. eltávolítása
            if domain.startswith('www.'):
                domain = domain[4:]
            filtered.add(domain)
    
    # Mentés
    with open(output_file, 'w') as f:
        for domain in sorted(filtered):
            f.write(domain + '\\n')
    
    print(f'Python parser: {len(filtered)} domain')
    
except Exception as e:
    print(f'Python hiba: {str(e)[:50]}...')
    open(output_file, 'w').close()
" 2>/dev/null || touch "${TEMP_DIR}/method4.txt"
            
            # 5. MÓDSZER: Lynx (ha telepítve van)
            echo "   5. Lynx text browser (ha elérhető)..."
            if command -v lynx &> /dev/null; then
                lynx -dump -nolist "$LINK" 2>/dev/null | \
                grep -oE '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' | \
                sort -u > "${TEMP_DIR}/method5.txt"
            else
                touch "${TEMP_DIR}/method5.txt"
            fi
            
            # 6. MÓDSZER: Alternatív API (htmlq)
            echo "   6. Alternatív API (htmlq)..."
            curl -s "$LINK" | \
            python3 -c "
import sys
import re
html = sys.stdin.read()
# Minden lehetséges domain keresése
import itertools
all_domains = re.findall(r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}', html)
# Egyediek
unique = sorted(set(d for d in all_domains if '.' in d and len(d) > 3))
for d in unique:
    print(d)
" 2>/dev/null | sort -u > "${TEMP_DIR}/method6.txt"
            
            # **ÖSSZES DOMAIN EGYESÍTÉSE ÉTISZTÍTÁSA**
            echo ""
            echo "🔄 Összes domain egyesítése és tisztítása..."
            
            # Összes módszer egyesítése
            cat "${TEMP_DIR}"/method*.txt 2>/dev/null | \
            sort -u | \
            # Duplikátumok eltávolítása (kisbetű/nagybetű normalizálás)
            awk '{print tolower($0)}' | \
            sort -u | \
            # Domain-ek szűrése
            grep -v '^[0-9].*\.[0-9].*\.[0-9].*\.[0-9].*$' | \
            grep -v '^localhost$' | \
            grep -v '^example\.' | \
            grep -v '^test\.' | \
            # Túl rövid domain-ek szűrése
            awk 'length($0) > 4' | \
            # WWW prefix eltávolítása
            sed 's/^www\.//' | \
            sort -u > "$OUTPUT_FILE"
            
            # Takarítás
            rm -rf "$TEMP_DIR"
            
            # **EREDMÉNYEK**
            COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
            
            clear
            echo ""
            echo "┌─────────────────────────────────────┐"
            echo "│      🚀 MAXIMÁLIS EREDMÉNY         │"
            echo "└─────────────────────────────────────┘"
            echo ""
            echo "🔗 Link: $LINK"
            echo "✅ Találat: $COUNT domain"
            echo "📁 Fájl: $OUTPUT_FILE"
            echo ""
            
            if [ "$COUNT" -gt 0 ]; then
                # **DOMAIN STATISZTIKA**
                echo "📊 DOMAIN STATISZTIKA:"
                echo "─────────────────────────────────────"
                echo "   .com domain-ek: $(grep -c '\.com$' "$OUTPUT_FILE")"
                echo "   .org domain-ek: $(grep -c '\.org$' "$OUTPUT_FILE")"
                echo "   .net domain-ek: $(grep -c '\.net$' "$OUTPUT_FILE")"
                echo "   .io domain-ek: $(grep -c '\.io$' "$OUTPUT_FILE")"
                echo "─────────────────────────────────────"
                echo ""
                
                echo "📝 Előnézet (első 25 domain):"
                echo "─────────────────────────────────────"
                head -25 "$OUTPUT_FILE" | nl -w 2 -s '. '
                echo "─────────────────────────────────────"
                
                if [ "$COUNT" -gt 25 ]; then
                    echo "... és még $((COUNT - 25)) domain"
                fi
                
                # **KATEGÓRIÁK AUTOMATIKUS FELISMERÉSE**
                echo ""
                echo "🎯 AUTOMATIKUS KATEGÓRIAFELISMERÉS:"
                echo "─────────────────────────────────────"
                
                # Ads domain-ek
                ads_count=$(grep -iE '(ads?\.|adservice|adserver|doubleclick|googlesyndication|amazon-adsystem|adcolony|media\.net)' "$OUTPUT_FILE" | wc -l)
                echo "   🎪 Reklám (Ads): $ads_count domain"
                
                # Analytics domain-ek
                analytics_count=$(grep -iE '(analytics|metrics|stats|tracking|mouseflow|hotjar|luckyorange)' "$OUTPUT_FILE" | wc -l)
                echo "   📈 Analytics: $analytics_count domain"
                
                # Social domain-ek
                social_count=$(grep -iE '(facebook|twitter|linkedin|reddit|tiktok|pinterest|youtube)' "$OUTPUT_FILE" | wc -l)
                echo "   👥 Social: $social_count domain"
                
                # Tracking domain-ek
                tracking_count=$(grep -iE '(tracking|tracker|pixel|beacon|tagmanager)' "$OUTPUT_FILE" | wc -l)
                echo "   🔍 Tracking: $tracking_count domain"
                
                # CDN domain-ek
                cdn_count=$(grep -iE '(cdn\.|cloudfront|akamai|fastly|cloudflare)' "$OUTPUT_FILE" | wc -l)
                echo "   📦 CDN: $cdn_count domain"
                
                echo "─────────────────────────────────────"
                
            else
                echo "⚠️  Nem találtam domain-eket!"
                echo ""
                echo "📋 Tippek:"
                echo "   • Ellenőrizd a link helyességét"
                echo "   • Próbálj másik linket"
                echo "   • Lehet hogy a weboldal JavaScript-t használ"
            fi
            
            echo ""
            
            # **KÉRDÉS: Mit szeretnél tenni?**
            while true; do
                echo "🤔 MIT SZERETNÉL TENNI?"
                echo "   1. Letörlöm ezt a listát"
                echo "   2. Még több domain keresése (EXTRA módszer)"
                echo "   3. Automatikus formátumok készítése"
                echo "   4. Fájl megnyitása/megtekintése"
                echo "   5. Új keresés (másik link)"
                echo "   6. Vissza a főmenühöz"
                echo ""
                read -p "Választás (1-6): " action
                
                case $action in
                    1)
                        rm -f "$OUTPUT_FILE"
                        echo "🗑️  Lista törölve!"
                        sleep 1
                        break
                        ;;
                    2)
                        echo ""
                        echo "💫 EXTRA DOMAIN KERESÉS (speciális módszer)..."
                        echo "⏳ Ez eltarthat 10 másodpercig..."
                        
                        # EXTRA módszer: teljes HTML elemzés
                        python3 -c "
import re
import requests
import urllib.parse
import sys

url = '$LINK'
output_file = '$OUTPUT_FILE'

try:
    # Meglévő domain-ek beolvasása
    existing_domains = set()
    try:
        with open(output_file, 'r') as f:
            existing_domains = set(line.strip().lower() for line in f)
    except:
        pass
    
    # Új letöltés
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    
    response = requests.get(url, headers=headers, timeout=15, verify=False)
    html = response.text
    
    # Összes lehetséges domain keresése
    all_domains = set()
    
    # 1. HTML-ből domain-ek
    html_domains = re.findall(r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}', html)
    all_domains.update(html_domains)
    
    # 2. Link-ekből domain-ek
    links = re.findall(r'href=[\"\']([^\"\']+)[\"\']', html, re.IGNORECASE)
    for link in links:
        try:
            parsed = urllib.parse.urlparse(link)
            if parsed.netloc:
                all_domains.add(parsed.netloc)
        except:
            pass
    
    # 3. Script src-ből domain-ek
    scripts = re.findall(r'src=[\"\']([^\"\']+)[\"\']', html, re.IGNORECASE)
    for script in scripts:
        try:
            parsed = urllib.parse.urlparse(script)
            if parsed.netloc:
                all_domains.add(parsed.netloc)
        except:
            pass
    
    # 4. Text sorokból domain-ek
    lines = html.split('\n')
    for line in lines:
        # Domain-ek szóközök vagy írásjelek között
        line_domains = re.findall(r'[^a-zA-Z0-9]([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})[^a-zA-Z0-9]', line)
        all_domains.update(line_domains)
    
    # Szűrés
    new_domains = set()
    for domain in all_domains:
        domain = domain.strip().lower()
        if (len(domain) > 3 and 
            '.' in domain and 
            not domain.startswith(('http://', 'https://', '//')) and
            not re.match(r'^\d+\.\d+\.\d+\.\d+$', domain)):
            # Normalizálás
            if domain.startswith('www.'):
                domain = domain[4:]
            if domain not in existing_domains:
                new_domains.add(domain)
    
    # Új domain-ek hozzáadása
    if new_domains:
        with open(output_file, 'a') as f:
            for domain in sorted(new_domains):
                f.write(domain + '\\n')
        
        # Újrasorrendezés
        sorted_domains = sorted(set(line.strip() for line in open(output_file)))
        with open(output_file, 'w') as f:
            for domain in sorted_domains:
                f.write(domain + '\\n')
        
        print(f'✅ {len(new_domains)} új domain hozzáadva!')
        print(f'📊 Összes domain: {len(sorted_domains)}')
        
    else:
        print('ℹ️  Nincs új domain.')
    
except Exception as e:
    print(f'❌ Hiba: {str(e)[:50]}')
" 2>&1 | tail -10
                        
                        # Frissített eredmény
                        NEW_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
                        
                        echo ""
                        echo "📊 FRISSÍTETT EREDMÉNY: $NEW_COUNT domain"
                        echo ""
                        read -p "Nyomj Entert a folytatáshoz..."
                        COUNT=$NEW_COUNT
                        continue
                        ;;
                    3)
                        echo ""
                        echo "🛠️  AUTOMATIKUS FORMÁTUMOK KÉSZÍTÉSE..."
                        
                        if [ "$COUNT" -gt 0 ]; then
                            # AdBlock formátum
                            cat "$OUTPUT_FILE" | while read domain; do
                                echo "||$domain^"
                            done > "/home/robot_36/adblock_max_${TIMESTAMP}.txt"
                            
                            # Hosts formátum
                            cat "$OUTPUT_FILE" | while read domain; do
                                echo "127.0.0.1 $domain"
                                echo "::1 $domain"
                            done > "/home/robot_36/hosts_max_${TIMESTAMP}.txt"
                            
                            # Pi-hole formátum
                            echo "# Pi-hole blacklist" > "/home/robot_36/pihole_max_${TIMESTAMP}.txt"
                            echo "# Generated from: $LINK" >> "/home/robot_36/pihole_max_${TIMESTAMP}.txt"
                            echo "# Total domains: $COUNT" >> "/home/robot_36/pihole_max_${TIMESTAMP}.txt"
                            cat "$OUTPUT_FILE" >> "/home/robot_36/pihole_max_${TIMESTAMP}.txt"
                            
                            # DNSMasq formátum
                            cat "$OUTPUT_FILE" | while read domain; do
                                echo "server=/$domain/"
                                echo "address=/$domain/0.0.0.0"
                            done > "/home/robot_36/dnsmasq_max_${TIMESTAMP}.txt"
                            
                            echo ""
                            echo "✅ FORMÁTUMOK KÉSZEK:"
                            echo "─────────────────────────────────────"
                            echo "   📄 adblock_max_${TIMESTAMP}.txt"
                            echo "   📄 hosts_max_${TIMESTAMP}.txt"
                            echo "   📄 pihole_max_${TIMESTAMP}.txt"
                            echo "   📄 dnsmasq_max_${TIMESTAMP}.txt"
                            echo "   📄 $OUTPUT_FILE (eredeti)"
                            echo "─────────────────────────────────────"
                        else
                            echo "❌ Nincs domain a formátumok készítéséhez!"
                        fi
                        
                        echo ""
                        read -p "Nyomj Entert a folytatáshoz..."
                        continue
                        ;;
                    4)
                        echo ""
                        echo "📄 FÁJL MEGTEKINTÉSE: $OUTPUT_FILE"
                        echo "─────────────────────────────────────"
                        if [ -f "$OUTPUT_FILE" ] && [ "$COUNT" -gt 0 ]; then
                            # Teljes fájl vagy első 50 sor
                            if [ "$COUNT" -le 100 ]; then
                                cat "$OUTPUT_FILE" | nl -w 3 -s '. '
                            else
                                head -50 "$OUTPUT_FILE" | nl -w 3 -s '. '
                                echo "... és még $((COUNT - 50)) sor"
                            fi
                        else
                            echo "Fájl üres vagy nem létezik."
                        fi
                        echo "─────────────────────────────────────"
                        echo ""
                        read -p "Nyomj Entert a folytatáshoz..."
                        continue
                        ;;
                    5)
                        echo "🔄 Új keresés..."
                        break 2
                        ;;
                    6)
                        echo "⏭️  Vissza a főmenühöz..."
                        sleep 1
                        break
                        ;;
                    *)
                        echo "❌ Érvénytelen választás"
                        sleep 1
                        continue
                        ;;
                esac
            done
            ;;
        2)
            # Előző eredmények (ugyanaz mint előző scriptben)
            clear
            echo ""
            echo "┌─────────────────────────────────────┐"
            echo "│        📁 ELŐZŐ EREDMÉNYEK         │"
            echo "└─────────────────────────────────────┘"
            echo ""
            
            if ls /home/robot_36/domain_*.txt 1> /dev/null 2>&1; then
                echo "Legutóbbi 10 fájl:"
                echo "─────────────────────────────────────"
                ls -la /home/robot_36/domain_*.txt 2>/dev/null | head -10 | \
                awk '{printf "📄 %s (%s bájt, %s sor)\n", $9, $5, NR}'
                echo "─────────────────────────────────────"
                echo ""
                
                TOTAL_FILES=$(ls /home/robot_36/domain_*.txt 2>/dev/null | wc -l)
                TOTAL_DOMAINS=$(cat /home/robot_36/domain_*.txt 2>/dev/null | sort -u | wc -l)
                
                echo "📊 ÖSSZESÍTÉS:"
                echo "   • Fájlok száma: $TOTAL_FILES"
                echo "   • Egyedi domain-ek: $TOTAL_DOMAINS"
                echo ""
                
                echo "🤔 MIT SZERETNÉL?"
                echo "   1. Egy fájl tartalmát megtekinteni"
                echo "   2. Összes fájl egyesítése"
                echo "   3. Vissza"
                echo ""
                read -p "Választás: " file_action
                
                case $file_action in
                    1)
                        echo ""
                        read -p "Fájlnév: " filename
                        if [ -f "/home/robot_36/$filename" ]; then
                            echo ""
                            echo "📄 $filename tartalma:"
                            echo "─────────────────────────────────────"
                            head -20 "/home/robot_36/$filename"
                            echo "─────────────────────────────────────"
                            TOTAL=$(wc -l < "/home/robot_36/$filename")
                            echo "Összesen: $TOTAL domain"
                        else
                            echo "❌ Fájl nem található!"
                        fi
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                    2)
                        echo ""
                        echo "🔄 Összes fájl egyesítése..."
                        cat /home/robot_36/domain_*.txt 2>/dev/null | \
                        sort -u > /home/robot_36/osszes_domain.txt
                        
                        MERGED_COUNT=$(wc -l < /home/robot_36/osszes_domain.txt)
                        echo "✅ Kész! $MERGED_COUNT egyedi domain"
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                esac
            else
                echo "ℹ️  Nincsenek előző letöltések."
                echo ""
                read -p "Nyomj Entert..."
            fi
            ;;
        3)
            # Gyors letöltés előre definiált forrásokból
            clear
            echo ""
            echo "┌─────────────────────────────────────┐"
            echo "│      🚀 GYORS LETÖLTÉS             │"
            echo "│      📋 ELŐRE DEFINIÁLT FORRÁSOK   │"
            echo "└─────────────────────────────────────┘"
            echo ""
            echo "VÁLASZD KI A FORRÁST:"
            echo "   1. AdGuard DNS Filter (hivatalos)"
            echo "   2. EasyList (alap reklám lista)"
            echo "   3. EasyPrivacy (adatvédelmi lista)"
            echo "   4. uBlock Origin Filters"
            echo "   5. Fanboy's Annoyance List"
            echo "   6. Hagezi's Multi List"
            echo "   7. OISD Full List (nagy lista)"
            echo "   8. Vissza"
            echo ""
            read -p "Választás (1-8): " source_choice
            
            case $source_choice in
                1)
                    LINK="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
                    SOURCE_NAME="AdGuard DNS Filter"
                    ;;
                2)
                    LINK="https://easylist.to/easylist/easylist.txt"
                    SOURCE_NAME="EasyList"
                    ;;
                3)
                    LINK="https://easylist.to/easylist/easyprivacy.txt"
                    SOURCE_NAME="EasyPrivacy"
                    ;;
                4)
                    LINK="https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
                    SOURCE_NAME="uBlock Origin Filters"
                    ;;
                5)
                    LINK="https://secure.fanboy.co.nz/fanboy-annoyance.txt"
                    SOURCE_NAME="Fanboy's Annoyance List"
                    ;;
                6)
                    LINK="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt"
                    SOURCE_NAME="Hagezi's Multi List"
                    ;;
                7)
                    LINK="https://big.oisd.nl/domains"
                    SOURCE_NAME="OISD Full List"
                    ;;
                8)
                    continue
                    ;;
                *)
                    echo "❌ Érvénytelen választás"
                    sleep 1
                    continue
                    ;;
            esac
            
            echo ""
            echo "🚀 Letöltés: $SOURCE_NAME"
            echo "🔗 $LINK"
            echo ""
            
            TIMESTAMP=$(date +%s)
            OUTPUT_FILE="/home/robot_36/${SOURCE_NAME// /_}_${TIMESTAMP}.txt"
            
            # Közvetlen letöltés filter listákhoz
            echo "⏳ Letöltés folyamatban..."
            curl -s -L "$LINK" | \
            grep -oE '[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
            sort -u > "$OUTPUT_FILE"
            
            COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
            
            echo ""
            echo "✅ KÉSZ!"
            echo "📊 $COUNT domain letöltve"
            echo "📁 $OUTPUT_FILE"
            echo ""
            
            # Gyors statisztika
            if [ "$COUNT" -gt 0 ]; then
                echo "📈 GYORS STATISZTIKA:"
                echo "─────────────────────────────────────"
                echo "   .com: $(grep -c '\.com$' "$OUTPUT_FILE")"
                echo "   .net: $(grep -c '\.net$' "$OUTPUT_FILE")"
                echo "   .org: $(grep -c '\.org$' "$OUTPUT_FILE")"
                echo "─────────────────────────────────────"
                echo ""
                
                echo "📝 Előnézet (első 15):"
                head -15 "$OUTPUT_FILE" | nl -w 2 -s '. '
            fi
            
            echo ""
            read -p "Nyomj Entert a folytatáshoz..."
            ;;
        4)
            clear
            echo ""
            echo "┌─────────────────────────────────────┐"
            echo "│            👋 VISZLÁT!             │"
            echo "└─────────────────────────────────────┘"
            echo ""
            echo "Készített fájlok: /home/robot_36/domain_*.txt"
            echo ""
            exit 0
            ;;
        *)
            echo "❌ Érvénytelen választás"
            sleep 1
            ;;
    esac
done
