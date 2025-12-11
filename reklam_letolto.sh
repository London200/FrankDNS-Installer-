#!/bin/bash

while true; do
    clear
    echo ""
    echo "╔══════════════════════════════╗"
    echo "║   🔗 LINK BEKÉRŐ SCRIPT     ║"
    echo "╚══════════════════════════════╝"
    echo ""
    echo "1. Új link letöltése"
    echo "2. Előző eredmények"
    echo "3. Kilépés"
    echo ""
    read -p "Választás: " choice
    
    case $choice in
        1)
            echo ""
            echo "📋 PÉLDA: https://adblock.turtlecute.org"
            read -p "🔗 Link: " LINK
            
            if [ -z "$LINK" ]; then
                echo "❌ Üres link!"
                sleep 2
                continue
            fi
            
            echo ""
            echo "⏳ TELJES OLDAL letöltése... (ez eltarthat 5-10 másodpercig)"
            
            # Fájlnév generálása
            TIMESTAMP=$(date +%s)
            OUTPUT_FILE="/home/robot_36/domain_${TIMESTAMP}.txt"
            
            # **JAVÍTÁS: TELJES OLDAL LETÖLTÉSE JINA AI-VAL**
            echo "🔍 Domain-ek keresése a TELJES oldalon..."
            
            # MÓDSZER 1: Teljes oldal letöltése több API paraméterrel
            curl -s -H "X-With-Generated-Alt: true" \
                 -H "X-With-Links: true" \
                 -H "X-With-Markdown: true" \
                 "https://r.jina.ai/$LINK" | \
            grep -oE '[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+\.[a-zA-Z]{2,}' | \
            sort -u > "$OUTPUT_FILE"
            
            COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
            
            # **HA MÉG MINDIG KEVÉS DOMAIN, PRÓBÁLJUNK MÁSIK API-T**
            if [ "$COUNT" -lt 50 ]; then
                echo "ℹ️  Még mindig kevés ($COUNT domain), alternatív módszert próbálok..."
                
                # MÓDSZER 2: textise API (ez több tartalmat ad vissza)
                curl -s "https://r.jina.ai/$LINK?max=10000" | \
                grep -oE '[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
                sort -u > "$OUTPUT_FILE"
                
                COUNT=$(wc -l < "$OUTPUT_FILE")
                
                # MÓDSZER 3: Ha még mindig kevés, saját parser
                if [ "$COUNT" -lt 50 ]; then
                    echo "⚠️  Még mindig kevés, saját parser-t használok..."
                    
                    # Létrehozunk egy Python scriptet ami jobban parsol
                    python3 -c "
import re
import requests
import sys

url = sys.argv[1]
try:
    # User-Agent beállítása, hogy ne blokkoljanak
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    response = requests.get(url, headers=headers, timeout=10)
    html = response.text
    
    # Különböző regex pattern-ek
    patterns = [
        r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}',
        r'[\w.-]+\.(?:com|org|net|io|co|uk|de|fr|it|es|ru|info|biz|xyz)',
        r'(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}'
    ]
    
    domains = set()
    for pattern in patterns:
        domains.update(re.findall(pattern, html))
    
    # Szűrjük ki a nem domain-eket
    filtered = []
    for domain in domains:
        if len(domain) > 4 and '.' in domain and not domain.startswith('.'):
            if not re.match(r'^\d+\.\d+\.\d+\.\d+$', domain):
                filtered.append(domain)
    
    # Mentés
    with open(sys.argv[2], 'w') as f:
        for domain in sorted(set(filtered)):
            f.write(domain + '\\n')
    
    print(f'Sikeresen mentve {len(set(filtered))} domain')
    
except Exception as e:
    print(f'Hiba: {e}')
    open(sys.argv[2], 'w').close()
" "$LINK" "$OUTPUT_FILE"
                    
                    COUNT=$(wc -l < "$OUTPUT_FILE")
                fi
            fi
            
            # **EREDMÉNY MEGJELENÍTÉSE**
            clear
            echo ""
            echo "┌─────────────────────────────────────┐"
            echo "│           📊 EREDMÉNY              │"
            echo "└─────────────────────────────────────┘"
            echo ""
            echo "🔗 Link: $LINK"
            echo "✅ Találat: $COUNT domain"
            echo "📁 Fájl: $OUTPUT_FILE"
            echo ""
            
            if [ "$COUNT" -gt 0 ]; then
                echo "📝 Előnézet (első 20):"
                echo "─────────────────────────────────────"
                head -20 "$OUTPUT_FILE" | nl -w 2 -s '. '
                echo "─────────────────────────────────────"
                
                if [ "$COUNT" -gt 20 ]; then
                    echo "... és még $((COUNT - 20)) domain"
                fi
            else
                echo "⚠️  Nem találtam domain-eket!"
                echo ""
                echo "📋 Tippek:"
                echo "   • Próbáld a 'Frissítem' opciót"
                echo "   • Ellenőrizd, hogy a link elérhető-e"
                echo "   • Próbálj másik linket"
            fi
            
            echo ""
            
            # **KÉRDÉS: Mit szeretnél tenni?**
            while true; do
                echo "🤔 MIT SZERETNÉL TENNI?"
                echo "   1. Letörlöm ezt a listát"
                echo "   2. Frissítem (KÜLÖN MÓDSZERREL több domain-ért)"
                echo "   3. Tovább (vissza a menühöz)"
                echo "   4. Automatikus formátumok készítése"
                echo "   5. Új keresés (másik link)"
                echo ""
                read -p "Választás (1-5): " action
                
                case $action in
                    1)
                        rm -f "$OUTPUT_FILE"
                        echo "🗑️  Lista törölve!"
                        sleep 1
                        break
                        ;;
                    2)
                        echo ""
                        echo "🔄 KÜLÖN MÓDSZERREL több domain keresése..."
                        echo "⏳ Ez eltarthat 10-15 másodpercig..."
                        
                        # **KÜLÖN MÓDSZER: Saját parser Pythonnal**
                        echo "🐍 Python parser használata..."
                        
                        python3 -c "
import re
import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

url = '$LINK'
output_file = '$OUTPUT_FILE'

try:
    # Headers a blokkolás elkerülésére
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'hu-HU,hu;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Cache-Control': 'max-age=0'
    }
    
    # Session létrehozása
    session = requests.Session()
    session.headers.update(headers)
    
    # Letöltés
    print('Letöltés...')
    response = session.get(url, timeout=15, verify=False)
    html = response.text
    
    # DOMAIN REGEX-ek amik tényleg működnek
    print('Domain-ek keresése...')
    
    # 1. Alap domain minta
    domains = set(re.findall(
        r'[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}', 
        html
    ))
    
    # 2. Speciális esetek (subdomain-ekkel)
    domains.update(re.findall(
        r'(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}', 
        html
    ))
    
    # 3. HTML attribútumokból
    domains.update(re.findall(
        r'(?:href|src|data-url|data-src)=\"[^\"]*?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', 
        html
    ))
    
    # Szűrés
    filtered = set()
    for domain in domains:
        domain = domain.strip().lower()
        if (len(domain) > 4 and 
            '.' in domain and 
            not domain.startswith(('http://', 'https://', 'www.', '//')) and
            not re.match(r'^\d+\.\d+\.\d+\.\d+$', domain) and
            not any(word in domain for word in ['example', 'test', 'localhost'])):
            filtered.add(domain)
    
    # Duplikátumok eltávolítása és sorrendbe rakás
    sorted_domains = sorted(filtered)
    
    # Mentés
    with open(output_file, 'w') as f:
        for domain in sorted_domains:
            f.write(domain + '\\n')
    
    print(f'✅ {len(sorted_domains)} domain találva!')
    print('Első 10 domain:')
    for i, domain in enumerate(sorted_domains[:10], 1):
        print(f'  {i}. {domain}')
    
except Exception as e:
    print(f'❌ Hiba: {e}')
    # Ha nem sikerül, marad a régi fájl
" 2>&1 | tail -20
                        
                        NEW_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
                        
                        # **FRISSÍTETT EREDMÉNY MEGJELENÍTÉSE**
                        clear
                        echo ""
                        echo "┌─────────────────────────────────────┐"
                        echo "│      🔄 FRISSÍTETT EREDMÉNY        │"
                        echo "└─────────────────────────────────────┘"
                        echo ""
                        echo "🔗 Link: $LINK"
                        echo "✅ Találat: $NEW_COUNT domain"
                        echo "📁 Fájl: $OUTPUT_FILE"
                        echo ""
                        
                        if [ "$NEW_COUNT" -gt 0 ]; then
                            echo "📝 Előnézet (első 25):"
                            echo "─────────────────────────────────────"
                            head -25 "$OUTPUT_FILE" | nl -w 2 -s '. '
                            echo "─────────────────────────────────────"
                            
                            if [ "$NEW_COUNT" -gt 25 ]; then
                                echo "... és még $((NEW_COUNT - 25)) domain"
                            fi
                            
                            # Domain-ek statisztikája
                            echo ""
                            echo "📊 Statisztika:"
                            echo "   .com domain-ek: $(grep -c '\.com$' "$OUTPUT_FILE" 2>/dev/null || echo "0")"
                            echo "   .org domain-ek: $(grep -c '\.org$' "$OUTPUT_FILE" 2>/dev/null || echo "0")"
                            echo "   .net domain-ek: $(grep -c '\.net$' "$OUTPUT_FILE" 2>/dev/null || echo "0")"
                        fi
                        
                        echo ""
                        read -p "Nyomj Entert a folytatáshoz..."
                        COUNT=$NEW_COUNT
                        continue
                        ;;
                    3)
                        echo "⏭️  Vissza a főmenühöz..."
                        sleep 1
                        break
                        ;;
                    4)
                        echo ""
                        echo "🛠️  Automatikus formátumok készítése..."
                        
                        if [ "$COUNT" -gt 0 ]; then
                            # Duplikátum ellenőrzés
                            UNIQUE_COUNT=$(sort -u "$OUTPUT_FILE" | wc -l)
                            
                            # AdBlock formátum
                            cat "$OUTPUT_FILE" | while read domain; do
                                echo "||$domain^"
                            done > "/home/robot_36/adblock_${TIMESTAMP}.txt"
                            
                            # Hosts formátum
                            cat "$OUTPUT_FILE" | while read domain; do
                                echo "127.0.0.1 $domain"
                                echo "::1 $domain"
                            done > "/home/robot_36/hosts_${TIMESTAMP}.txt"
                            
                            echo ""
                            echo "✅ Formátumok kész:"
                            echo "   📄 adblock_${TIMESTAMP}.txt"
                            echo "   📄 hosts_${TIMESTAMP}.txt"
                            echo "   📄 $OUTPUT_FILE (eredeti: $COUNT domain)"
                        else
                            echo "❌ Nincs domain a formátumok készítéséhez!"
                        fi
                        
                        echo ""
                        read -p "Nyomj Entert a folytatáshoz..."
                        continue
                        ;;
                    5)
                        echo "🔄 Új keresés..."
                        break 2
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
                awk '{printf "📄 %s (%s bájt, %s %s)\n", $9, $5, $6, $7}'
                echo "─────────────────────────────────────"
                echo ""
                
                TOTAL_FILES=$(ls /home/robot_36/domain_*.txt 2>/dev/null | wc -l)
                echo "📊 Összesítés:"
                echo "   • Fájlok száma: $TOTAL_FILES"
                
                echo "🔍 Egyedi domain-ek összesítése..."
                TOTAL_DOMAINS=$(cat /home/robot_36/domain_*.txt 2>/dev/null | sort -u | wc -l)
                echo "   • Egyedi domain-ek: $TOTAL_DOMAINS"
                
                ALL_DOMAINS_COUNT=$(cat /home/robot_36/domain_*.txt 2>/dev/null | wc -l)
                DUPLICATES_COUNT=$((ALL_DOMAINS_COUNT - TOTAL_DOMAINS))
                echo "   • Duplikátumok: $DUPLICATES_COUNT"
                
                # **ÚJ: Duplikált domain-ek listázása**
                if [ "$DUPLICATES_COUNT" -gt 0 ]; then
                    echo ""
                    echo "🔍 Duplikált domain-ek (első 10):"
                    cat /home/robot_36/domain_*.txt 2>/dev/null | \
                    sort | uniq -d | head -10 | nl -w 2 -s '. '
                    
                    if [ $(cat /home/robot_36/domain_*.txt 2>/dev/null | sort | uniq -d | wc -l) -gt 10 ]; then
                        echo "   ...és még $((DUPLICATES_COUNT - 10)) duplikátum"
                    fi
                fi
                
                echo ""
                
                echo "🤔 MIT SZERETNÉL?"
                echo "   1. Egy fájl tartalmát megtekinteni"
                echo "   2. Összes fájl egyesítése (DUPLIKÁTUM ELLENŐRZÉSSEL)"
                echo "   3. Duplikátumok ellenőrzése egy fájlban"
                echo "   4. Duplikált domain-ek listázása"
                echo "   5. Vissza"
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
                            UNIQUE=$(sort -u "/home/robot_36/$filename" | wc -l)
                            echo "Összesen: $TOTAL domain"
                            echo "Egyedi: $UNIQUE domain"
                            if [ "$TOTAL" -gt "$UNIQUE" ]; then
                                echo "⚠️  Duplikátumok: $((TOTAL - UNIQUE))"
                                
                                # Duplikált domain-ek listázása a fájlon belül
                                echo ""
                                echo "📋 Duplikált domain-ek ebben a fájlban:"
                                sort "/home/robot_36/$filename" | uniq -d | head -10 | nl -w 2 -s '. '
                            fi
                        else
                            echo "❌ Fájl nem található!"
                        fi
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                    2)
                        echo ""
                        echo "🔄 Összes fájl egyesítése (DUPLIKÁTUM ELLENŐRZÉSSEL)..."
                        echo "⏳ Fájlok összeolvasása és duplikátumok eltávolítása..."
                        
                        # **JAVÍTOTT: Ellenőrizzük a duplikátumokat mielőtt egyesítjük**
                        
                        # 1. Összes domain összegyűjtése
                        ALL_DOMAINS=$(cat /home/robot_36/domain_*.txt 2>/dev/null)
                        TOTAL_DOMAINS_COUNT=$(echo "$ALL_DOMAINS" | wc -l)
                        
                        # 2. Duplikált domain-ek keresése
                        DUPLICATED_DOMAINS=$(echo "$ALL_DOMAINS" | sort | uniq -d)
                        DUPLICATES_FOUND=$(echo "$DUPLICATED_DOMAINS" | wc -l)
                        
                        # 3. Egyedi domain-ek kinyerése
                        UNIQUE_DOMAINS=$(echo "$ALL_DOMAINS" | sort -u)
                        UNIQUE_COUNT=$(echo "$UNIQUE_DOMAINS" | wc -l)
                        
                        # 4. Mentés
                        echo "$UNIQUE_DOMAINS" > /home/robot_36/osszes_domain.txt
                        
                        echo ""
                        echo "✅ KÉSZ! Duplikátum ellenőrzés vége!"
                        echo ""
                        echo "📊 EREDMÉNY:"
                        echo "   • Összes domain (összes fájlból): $TOTAL_DOMAINS_COUNT"
                        echo "   • Duplikált domain-ek találva: $DUPLICATES_FOUND"
                        echo "   • Egyedi domain-ek (duplikátumok nélkül): $UNIQUE_COUNT"
                        echo "   • Eltávolított duplikátumok: $((TOTAL_DOMAINS_COUNT - UNIQUE_COUNT))"
                        echo ""
                        
                        # Duplikált domain-ek listázása
                        if [ "$DUPLICATES_FOUND" -gt 0 ]; then
                            echo "🔍 Duplikált domain-ek amiket eltávolítottam:"
                            echo "$DUPLICATED_DOMAINS" | head -15 | nl -w 2 -s '. '
                            
                            if [ "$DUPLICATES_FOUND" -gt 15 ]; then
                                echo "   ...és még $((DUPLICATES_FOUND - 15)) duplikátum"
                            fi
                        else
                            echo "✅ Nincsenek duplikált domain-ek!"
                        fi
                        
                        # **ÚJ: Automatikus formátumok készítése az egyesített fájlból**
                        echo ""
                        read -p "Szeretnél automatikus formátumokat készíteni az egyesített fájlból? (i/n): " create_formats
                        
                        if [[ "$create_formats" == "i" || "$create_formats" == "I" ]]; then
                            MERGE_TIMESTAMP=$(date +%s)
                            
                            # AdBlock formátum
                            cat /home/robot_36/osszes_domain.txt | while read domain; do
                                echo "||$domain^"
                            done > "/home/robot_36/adblock_merged_${MERGE_TIMESTAMP}.txt"
                            
                            # Hosts formátum
                            cat /home/robot_36/osszes_domain.txt | while read domain; do
                                echo "127.0.0.1 $domain"
                                echo "::1 $domain"
                            done > "/home/robot_36/hosts_merged_${MERGE_TIMESTAMP}.txt"
                            
                            echo ""
                            echo "✅ Formátumok kész:"
                            echo "   📄 adblock_merged_${MERGE_TIMESTAMP}.txt"
                            echo "   📄 hosts_merged_${MERGE_TIMESTAMP}.txt"
                        fi
                        
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                    3)
                        echo ""
                        read -p "Fájlnév duplikátum ellenőrzéshez: " dup_file
                        if [ -f "/home/robot_36/$dup_file" ]; then
                            echo ""
                            echo "🔍 Duplikátum ellenőrzés: $dup_file"
                            echo "─────────────────────────────────────"
                            
                            TOTAL_LINES=$(wc -l < "/home/robot_36/$dup_file")
                            UNIQUE_LINES=$(sort -u "/home/robot_36/$dup_file" | wc -l)
                            DUPLICATES=$((TOTAL_LINES - UNIQUE_LINES))
                            
                            echo "Összes domain: $TOTAL_LINES"
                            echo "Egyedi domain: $UNIQUE_LINES"
                            echo "Duplikátumok: $DUPLICATES"
                            echo ""
                            
                            if [ "$DUPLICATES" -gt 0 ]; then
                                echo "📋 Duplikált domain-ek:"
                                sort "/home/robot_36/$dup_file" | uniq -d | head -20 | nl -w 2 -s '. '
                                
                                echo ""
                                read -p "Szeretnéd eltávolítani a duplikátumokat? (i/n): " remove_dup
                                if [[ "$remove_dup" == "i" || "$remove_dup" == "I" ]]; then
                                    sort -u "/home/robot_36/$dup_file" > "/home/robot_36/${dup_file}.unique"
                                    mv "/home/robot_36/${dup_file}.unique" "/home/robot_36/$dup_file"
                                    echo "✅ Duplikátumok eltávolítva! Új domain szám: $(wc -l < "/home/robot_36/$dup_file")"
                                fi
                            else
                                echo "✅ Nincsenek duplikátumok!"
                            fi
                        else
                            echo "❌ Fájl nem található!"
                        fi
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                    4)
                        echo ""
                        echo "🔍 ÖSSZES DUPLIKÁLT DOMAIN LISTÁZÁSA"
                        echo "─────────────────────────────────────"
                        
                        # Összes duplikált domain keresése
                        ALL_DUPLICATES=$(cat /home/robot_36/domain_*.txt 2>/dev/null | sort | uniq -d)
                        TOTAL_DUPLICATES=$(echo "$ALL_DUPLICATES" | wc -l)
                        
                        if [ "$TOTAL_DUPLICATES" -gt 0 ]; then
                            echo "Összes duplikált domain: $TOTAL_DUPLICATES"
                            echo ""
                            echo "Duplikált domain-ek listája:"
                            echo "─────────────────────────────────────"
                            echo "$ALL_DUPLICATES" | nl -w 2 -s '. '
                            echo "─────────────────────────────────────"
                            
                            # **ÚJ: Duplikátumok száma fájlonként**
                            echo ""
                            echo "📊 Duplikátumok fájlonként:"
                            for file in /home/robot_36/domain_*.txt; do
                                if [ -f "$file" ]; then
                                    FILENAME=$(basename "$file")
                                    FILE_DUPS=$(sort "$file" | uniq -d | wc -l)
                                    if [ "$FILE_DUPS" -gt 0 ]; then
                                        echo "   📄 $FILENAME: $FILE_DUPS duplikátum"
                                    fi
                                fi
                            done
                        else
                            echo "✅ Nincsenek duplikált domain-ek!"
                        fi
                        
                        echo ""
                        read -p "Nyomj Entert..."
                        ;;
                    5)
                        echo "⏮️  Vissza..."
                        ;;
                    *)
                        echo "❌ Érvénytelen választás"
                        sleep 1
                        ;;
                esac
            else
                echo "ℹ️  Nincsenek előző letöltések."
                echo ""
                read -p "Nyomj Entert..."
            fi
            ;;
        3)
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
