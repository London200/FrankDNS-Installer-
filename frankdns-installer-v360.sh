#!/bin/bash

# ==============================================================================
#  FRANKDNS+ 2026 - MODULAR SYSTEM INSTALLER (v3.6.0)
#  ARCHITEKTÚRA: Modular Go (cmd/internal layout)
#  MÓDOSÍTÁS DÁTUMA: 2025-12-13
#  INSTALL DIR: /home/robot_36/frankdnsplus
#  
#  JAVÍTÁSOK v3.6.0 - TISZTA LAP VERZIÓ:
#    ✓ ÜRES alapértelmezett Whitelist és Blacklist
#    ✓ NINCS beépített védett domain - te döntöd el a webes felületen!
#    ✓ GitHub lista URL frissítve: frankdns-adguard-final.txt
#    ✓ IsWhitelisted() javítva - blacklist prioritás
#    ✓ apiConfig hibakezelés és logging
#    ✓ postConfig Content-Type header
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}HIBA: Kérlek, futtasd root jogosultsággal! (sudo ./installer.sh)${NC}"
  exit 1
fi

show_main_menu() {
    clear
    echo -e "${BLUE}############################################################${NC}"
    echo -e "${BLUE}#${NC}       ${BOLD}FRANKDNS+ 2026 - MODULAR SYSTEM v3.6.0${NC}       ${BLUE}#${NC}"
    echo -e "${BLUE}############################################################${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} 🚀 TELEPÍTÉS / JAVÍTÁS (Modular Engine)"
    echo -e "      ${BLUE}- Teljes forráskód generálása és fordítása${NC}"
    echo -e "      ${BLUE}- Szolgáltatások újraindítása${NC}"
    echo ""
    echo -e "  ${YELLOW}2)${NC} 🔄 RENDSZER FRISSÍTÉS + TELEPÍTÉS"
    echo ""
    echo -e "  ${YELLOW}3)${NC} 🎛️  VEZÉRLŐPULT (Logok, Restart)"
    echo ""
    echo -e "  ${YELLOW}4)${NC} 📁 FTP beállítások (root login engedélyezése)"
    echo ""
    echo -e "  ${YELLOW}5)${NC} 🔧 Jogosultság javítás"
    echo ""
    echo -e "  ${YELLOW}6)${NC} 🚪 Kilépés"
    echo ""
    read -p "Mit szeretnél tenni? (1-6): " choice

    case $choice in
        1)
            FULL_UPDATE=false
            run_installer
            ;;
        2)
            FULL_UPDATE=true
            run_installer
            ;;
        3)
            if [ -f "/usr/local/bin/frank" ]; then
                bash /usr/local/bin/frank
                echo ""; read -p "Nyomj Entert a menübe való visszatéréshez..."
                show_main_menu
            else
                echo -e "\n${RED}❌ A FrankDNS nincs telepítve!${NC}"; sleep 2; show_main_menu
            fi
            ;;
        4)
            configure_ftp
            ;;
        5)
            fix_permissions
            ;;
        6) 
            echo -e "\nViszlát!"; exit 0 ;;
        *) 
            show_main_menu ;;
    esac
}

configure_ftp() {
    clear
    echo -e "${BLUE}############################################################${NC}"
    echo -e "${BLUE}#${NC}       ${BOLD}FTP BEÁLLÍTÁSOK${NC}       ${BLUE}#${NC}"
    echo -e "${BLUE}############################################################${NC}"
    echo ""
    
    echo "🔍 FTP szerverek keresése..."
    
    # vsftpd ellenőrzés
    if systemctl is-active --quiet vsftpd 2>/dev/null || dpkg -l | grep -q vsftpd; then
        echo -e "✅ vsftpd szerver észlelve"
        echo ""
        echo -e "${YELLOW}vsftpd beállítása:${NC}"
        echo "1) Root login engedélyezése vsftpd-ben"
        echo "2) Vissza a menübe"
        read -p "Válassz: " ftp_choice
        
        if [ "$ftp_choice" = "1" ]; then
            echo -e "\n🔧 vsftpd konfiguráció módosítása..."
            # vsftpd konfiguráció mentése
            if [ -f "/etc/vsftpd.conf" ]; then
                cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
                echo "💾 vsftpd konfiguráció mentve: /etc/vsftpd.conf.backup"
                
                # Root login engedélyezése
                sed -i 's/^#root_login/root_login/' /etc/vsftpd.conf 2>/dev/null
                sed -i 's/^root_login=NO/root_login=YES/' /etc/vsftpd.conf 2>/dev/null
                sed -i 's/^local_enable=NO/local_enable=YES/' /etc/vsftpd.conf 2>/dev/null
                # Csak akkor adjuk hozzá, ha még nincs benne
                grep -q "^local_enable=YES" /etc/vsftpd.conf || echo "local_enable=YES" >> /etc/vsftpd.conf
                grep -q "^write_enable=YES" /etc/vsftpd.conf || echo "write_enable=YES" >> /etc/vsftpd.conf
                
                systemctl restart vsftpd 2>/dev/null
                echo -e "${GREEN}✅ vsftpd root login engedélyezve${NC}"
            else
                echo -e "${RED}❌ /etc/vsftpd.conf nem található${NC}"
            fi
        fi
    fi
    
    # proftpd ellenőrzés
    if systemctl is-active --quiet proftpd 2>/dev/null || dpkg -l | grep -q proftpd; then
        echo -e "\n✅ proftpd szerver észlelve"
        echo ""
        echo -e "${YELLOW}proftpd beállítása:${NC}"
        echo "1) Root login engedélyezése proftpd-ben"
        echo "2) Vissza a menübe"
        read -p "Válassz: " proftpd_choice
        
        if [ "$proftpd_choice" = "1" ]; then
            echo -e "\n🔧 proftpd konfiguráció módosítása..."
            if [ -f "/etc/proftpd/proftpd.conf" ]; then
                cp /etc/proftpd/proftpd.conf /etc/proftpd/proftpd.conf.backup
                echo "💾 proftpd konfiguráció mentve: /etc/proftpd/proftpd.conf.backup"
                
                # Root login engedélyezése - csak ha még nincs benne
                if ! grep -q "AllowUser root" /etc/proftpd/proftpd.conf; then
                    echo "<Limit LOGIN>" >> /etc/proftpd/proftpd.conf
                    echo "    AllowUser root" >> /etc/proftpd/proftpd.conf
                    echo "</Limit>" >> /etc/proftpd/proftpd.conf
                fi
                
                systemctl restart proftpd 2>/dev/null
                echo -e "${GREEN}✅ proftpd root login engedélyezve${NC}"
            else
                echo -e "${RED}❌ /etc/proftpd/proftpd.conf nem található${NC}"
            fi
        fi
    fi
    
    # sshd ellenőrzés
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || dpkg -l | grep -q openssh-server; then
        echo -e "\n✅ SSH szerver észlelve"
        echo ""
        echo -e "${YELLOW}SSH beállítása:${NC}"
        echo "1) Root login engedélyezése SSH-n keresztül"
        echo "2) Vissza a menübe"
        read -p "Válassz: " ssh_choice
        
        if [ "$ssh_choice" = "1" ]; then
            echo -e "\n🔧 SSH konfiguráció módosítása..."
            if [ -f "/etc/ssh/sshd_config" ]; then
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
                echo "💾 SSH konfiguráció mentve: /etc/ssh/sshd_config.backup"
                
                # Root login engedélyezése
                sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
                
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
                echo -e "${GREEN}✅ SSH root login engedélyezve${NC}"
            else
                echo -e "${RED}❌ /etc/ssh/sshd_config nem található${NC}"
            fi
        fi
    fi
    
    # Ha egyik FTP szerver sem található
    if ! (systemctl is-active --quiet vsftpd 2>/dev/null || systemctl is-active --quiet proftpd 2>/dev/null || \
          systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || \
          dpkg -l | grep -q vsftpd || dpkg -l | grep -q proftpd || dpkg -l | grep -q openssh-server); then
        echo -e "${RED}❌ Nem található telepített FTP/SSH szerver${NC}"
        echo ""
        echo "Telepíthetsz egyet az alábbi parancsokkal:"
        echo "  vsftpd: apt-get install vsftpd"
        echo "  proftpd: apt-get install proftpd"
        echo "  SSH: apt-get install openssh-server"
    fi
    
    echo ""
    read -p "Nyomj Entert a menübe való visszatéréshez..."
    show_main_menu
}

fix_permissions() {
    clear
    echo -e "${BLUE}############################################################${NC}"
    echo -e "${BLUE}#${NC}       ${BOLD}JOGOSULTSÁG JAVÍTÁS${NC}       ${BLUE}#${NC}"
    echo -e "${BLUE}############################################################${NC}"
    echo ""
    
    echo "🔧 Jogosultságok javítása..."
    echo ""
    
    if id "robot_36" &>/dev/null; then
        echo "Felhasználó: robot_36"
        echo "Könyvtár: /home/robot_36"
        echo ""
        
        echo "Parancsok végrehajtása:"
        echo "  sudo chown -R robot_36:robot_36 /home/robot_36"
        echo "  sudo chmod -R 755 /home/robot_36"
        echo ""
        
        read -p "Folytatod? (i/n): " confirm
        if [ "$confirm" = "i" ] || [ "$confirm" = "I" ] || [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            echo ""
            echo "🏃‍♂️ Jogosultságok módosítása folyamatban..."
            
            # Jogosultságok javítása
            chown -R robot_36:robot_36 /home/robot_36
            chmod -R 755 /home/robot_36
            
            # FrankDNS+ specifikus könyvtárak
            if [ -d "/home/robot_36/frankdnsplus" ]; then
                echo "FrankDNS+ könyvtár jogosultságok ellenőrzése..."
                chown -R robot_36:robot_36 /home/robot_36/frankdnsplus
                find /home/robot_36/frankdnsplus -type f -exec chmod 644 {} \;
                find /home/robot_36/frankdnsplus -type d -exec chmod 755 {} \;
                
                # Bináris fájlok írásvédetté tétele
                if [ -f "/home/robot_36/frankdnsplus/main" ]; then
                    chmod +x /home/robot_36/frankdnsplus/main
                fi
            fi
            
            echo -e "${GREEN}✅ Jogosultságok javítva${NC}"
            echo ""
            echo "A /home/robot_36 könyvtár most:"
            echo "  Tulajdonos: robot_36:robot_36"
            echo "  Jogosultság: 755 (rwxr-xr-x)"
        else
            echo -e "${YELLOW}⏹️ Művelet megszakítva${NC}"
        fi
    else
        echo -e "${RED}❌ A robot_36 felhasználó nem létezik${NC}"
        echo ""
        echo "Hozd létre a felhasználót:"
        echo "  sudo useradd -m robot_36"
    fi
    
    echo ""
    read -p "Nyomj Entert a menübe való visszatéréshez..."
    show_main_menu
}

run_installer() {
    print_block() {
        echo -e "\n${BLUE}############################################################${NC}"
        echo -e "${BLUE}#${NC} ${YELLOW}${BOLD}$1${NC}"
        echo -e "${BLUE}############################################################${NC}"
        sleep 1
    }

    INSTALL_DIR="/home/robot_36/frankdnsplus"
    CONFIG_PATH="$INSTALL_DIR/config.json"

    print_block "1. LÉPÉS: TAKARÍTÁS ÉS ELŐKÉSZÍTÉS"

    echo "🛑 Régi szolgáltatások leállítása..."
    systemctl stop frankdnsplus 2>/dev/null
    systemctl disable frankdnsplus 2>/dev/null
    
    echo "🔓 Portok felszabadítása..."
    fuser -k 8000/tcp 2>/dev/null
    fuser -k 53/tcp 2>/dev/null
    fuser -k 53/udp 2>/dev/null

    echo "🗑️ Régi fájlok archiválása..."
    # Config mentése (régi /opt + új /home helyről is megpróbáljuk)
    if [ -f "/opt/frankdnsplus/config.json" ]; then
        cp /opt/frankdnsplus/config.json /tmp/frank_config_backup.json
        echo "💾 Konfiguráció mentve a /opt-ból..."
    elif [ -f "$CONFIG_PATH" ]; then
        cp "$CONFIG_PATH" /tmp/frank_config_backup.json
        echo "💾 Konfiguráció mentve a /home-ból..."
    fi

    rm -rf /opt/frankdnsplus
    rm -rf "$INSTALL_DIR"
    
    if lsof -i :53 | grep -q systemd-r; then
        echo "⚠️  systemd-resolved leállítása..."
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved 2>/dev/null
    fi

    echo "🌐 DNS ideiglenes beállítása..."
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/cmd/frankdns"
    mkdir -p "$INSTALL_DIR/internal/config"
    mkdir -p "$INSTALL_DIR/internal/cache"
    mkdir -p "$INSTALL_DIR/internal/blocklist"
    mkdir -p "$INSTALL_DIR/internal/dnsserver"
    mkdir -p "$INSTALL_DIR/internal/webapi"
    mkdir -p "$INSTALL_DIR/web"

    # Config visszaállítása
    if [ -f "/tmp/frank_config_backup.json" ]; then
        cp /tmp/frank_config_backup.json "$CONFIG_PATH"
        echo "💾 Konfiguráció visszaállítva."
    fi

    echo "📦 Csomagok frissítése..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y

    if [ "$FULL_UPDATE" = true ]; then
        apt-get upgrade -y
    fi

    apt-get install -y git curl lsof wget tar psmisc net-tools ca-certificates

    print_block "2. LÉPÉS: Go Motor Frissítése"

    rm -rf /usr/local/go
    
    RAW_ARCH=$(dpkg --print-architecture)
    case "$RAW_ARCH" in
        "amd64") GO_ARCH="amd64" ;;
        "arm64") GO_ARCH="arm64" ;;
        "armhf") GO_ARCH="armv6l" ;;
        "i386")  GO_ARCH="386" ;;
        *) GO_ARCH="amd64" ;;
    esac

    echo -e "🔍 Arch: ${YELLOW}$GO_ARCH${NC}"
    
    if wget -q --spider https://go.dev/dl/go1.23.4.linux-$GO_ARCH.tar.gz; then
         GO_VER="1.23.4"
    else
         GO_VER="1.23.0"
    fi

    echo "⬇️ Go $GO_VER letöltése..."
    wget -q "https://go.dev/dl/go$GO_VER.linux-$GO_ARCH.tar.gz" -O /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    if ! grep -q "/usr/local/go/bin" /etc/profile; then echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile; fi

    print_block "3. LÉPÉS: Moduláris Forráskód Generálása"

    cd "$INSTALL_DIR"

    # --- go.mod ---
cat << 'EOF' > go.mod
module frankdnsplus

go 1.23

require (
	github.com/miekg/dns v1.1.62
)
EOF

    # --- internal/config/config.go ---
cat << 'EOF' > internal/config/config.go
package config

import (
	"encoding/json"
	"os"
	"sync"
)

// Global configuration variables
var (
	Instance *Config
	Mutex    sync.RWMutex
	Path     string
)

func init() {
	// Környezeti változóból vagy alapértelmezettből
	Path = os.Getenv("FRANKDNS_CONFIG_PATH")
	if Path == "" {
		Path = "/home/robot_36/frankdnsplus/config.json"
	}
}

// BlocklistConfig defines a single external blocklist source
type BlocklistConfig struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Enabled bool   `json:"enabled"`
}

// Device defines a known network device
type Device struct {
	Name     string `json:"name"`
	IP       string `json:"ip"`
	MAC      string `json:"mac"`
	LastSeen string `json:"last_seen"`
}

// Config holds the main application configuration
type Config struct {
	ListenDNS           string            `json:"listen_dns"`
	ListenHTTP          string            `json:"listen_http"`
	Upstreams           []string          `json:"upstreams"`
	Blocklists          []BlocklistConfig `json:"blocklists"`
	Whitelist           []string          `json:"whitelist"`
	Blacklist           []string          `json:"blacklist"`
	ResponseMode        string            `json:"response_mode"`
	LogBufferSize       int               `json:"log_buffer_size"`
	AIDetection         bool              `json:"ai_detection"`
	AgressiveAIBlocking bool              `json:"agressive_ai_blocking"`
	BlockingEnabled     bool              `json:"blocking_enabled"`
	Devices             []Device          `json:"devices"`
}

// Default returns the default configuration structure
func Default() Config {
	return Config{
		ListenDNS:           ":53",
		ListenHTTP:          ":8000",
		Upstreams:           []string{"tls://1.1.1.1", "tls://1.0.0.1"},
		ResponseMode:        "zero",
		LogBufferSize:       100,
		AIDetection:         true,
		BlockingEnabled:     true,
		AgressiveAIBlocking: false,
		Devices:             []Device{},
		Whitelist:           []string{},
		Blacklist:           []string{},
		Blocklists: []BlocklistConfig{},
	}
}

// Load reads the config file or creates a default one if missing
func Load() {
	file, err := os.Open(Path)
	if err != nil {
		Instance = new(Config)
		*Instance = Default()
		Save()
		return
	}
	defer file.Close()

	Instance = new(Config)
	if err := json.NewDecoder(file).Decode(Instance); err != nil {
		*Instance = Default()
	}
}

// Save writes the current configuration to disk
func Save() error {
	Mutex.RLock()
	defer Mutex.RUnlock()

	data, err := json.MarshalIndent(Instance, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(Path, data, 0644)
}
EOF

    # --- internal/cache/cache.go ---
cat << 'EOF' > internal/cache/cache.go
package cache

import (
	"fmt"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// Entry represents a cached DNS response
type Entry struct {
	Msg     *dns.Msg
	Expires time.Time
}

// Store manages concurrent access to the DNS cache
type Store struct {
	items map[string]Entry
	mutex sync.RWMutex
}

// Global instance
var Global = New()

// New initializes a new cache store
func New() *Store {
	return &Store{
		items: make(map[string]Entry),
	}
}

// Get retrieves a cached response if valid
func (s *Store) Get(question dns.Question) *dns.Msg {
	key := fmt.Sprintf("%s:%d:%d", question.Name, question.Qtype, question.Qclass)

	s.mutex.RLock()
	entry, found := s.items[key]
	s.mutex.RUnlock()

	if found && time.Now().Before(entry.Expires) {
		msg := entry.Msg.Copy()
		return msg
	}
	return nil
}

// Set adds a response to the cache
func (s *Store) Set(question dns.Question, msg *dns.Msg) {
	if len(msg.Answer) == 0 {
		return
	}

	minTTL := uint32(3600)
	for _, rr := range msg.Answer {
		if rr.Header().Ttl < minTTL {
			minTTL = rr.Header().Ttl
		}
	}

	if minTTL == 0 {
		return
	}

	key := fmt.Sprintf("%s:%d:%d", question.Name, question.Qtype, question.Qclass)

	s.mutex.Lock()
	s.items[key] = Entry{
		Msg:     msg,
		Expires: time.Now().Add(time.Duration(minTTL) * time.Second),
	}
	s.mutex.Unlock()
}

// Cleanup removes expired entries
func (s *Store) Cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		s.mutex.Lock()
		for key, entry := range s.items {
			if now.After(entry.Expires) {
				delete(s.items, key)
			}
		}
		s.mutex.Unlock()
	}
}

// Clear removes all entries from cache (used when blocklist updates)
func (s *Store) Clear() {
	s.mutex.Lock()
	s.items = make(map[string]Entry)
	s.mutex.Unlock()
}

// StartCleanupRoutine runs the cleanup in a goroutine
func StartCleanupRoutine() {
	go Global.Cleanup()
}
EOF

    # --- internal/blocklist/blocklist.go ---
cat << 'EOF' > internal/blocklist/blocklist.go
package blocklist

import (
	"bufio"
	"frankdnsplus/internal/config"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Manager handles the lifecycle of blocklists
type Manager struct {
	BlockMap      map[string]struct{}
	WhitelistMap  map[string]struct{}
	BlacklistMap  map[string]struct{}
	ListCounts    map[string]int // Domain count per URL
	Mutex         sync.RWMutex
	StatsDatabase uint64
	LastUpdate    time.Time
}

// Global instance
var Global = &Manager{
	BlockMap:     make(map[string]struct{}),
	WhitelistMap: make(map[string]struct{}),
	BlacklistMap: make(map[string]struct{}),
	ListCounts:   make(map[string]int),
	LastUpdate:   time.Now(),
}

// Update downloads and parses all enabled blocklists
func (m *Manager) Update() {
	log.Printf("[BLOCKLIST] Frissítés indítása...")
	
	// 1️⃣ ÚJ ADATBÁZIS ELŐKÉSZÍTÉSE (teljesen üres, nincs duplikáció)
	newBlockMap := make(map[string]struct{})
	newWhitelistFromLists := make(map[string]struct{})
	newListCounts := make(map[string]int)
	successCount := 0
	errorCount := 0
	enabledCount := 0

	config.Mutex.RLock()
	lists := config.Instance.Blocklists
	config.Mutex.RUnlock()

	client := http.Client{Timeout: 30 * time.Second}

	// 3️⃣ KIZÁRÓLAG AZ AKTUÁLIS SZŰRŐLISTÁK LETÖLTÉSE
	for _, list := range lists {
		if !list.Enabled {
			continue
		}
		enabledCount++

		log.Printf("[BLOCKLIST] Letöltés: %s", list.Name)
		resp, err := client.Get(list.URL)
		if err != nil {
			log.Printf("[BLOCKLIST] ❌ Hiba a lista letöltésekor (%s): %v", list.Name, err)
			errorCount++
			continue
		}
		
		if resp.StatusCode != 200 {
			log.Printf("[BLOCKLIST] ❌ HTTP hiba (%s): %d", list.Name, resp.StatusCode)
			resp.Body.Close()
			errorCount++
			continue
		}

		scanner := bufio.NewScanner(resp.Body)
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 2*1024*1024) // 2MB buffer a nagy listákhoz
		
		lineCount := 0
		domainCount := 0
		whitelistCount := 0

		for scanner.Scan() {
			lineCount++
			rawLine := scanner.Text()
			
			// Whitelist sorok kezelése (@@||domain^)
			if strings.HasPrefix(strings.TrimSpace(rawLine), "@@") {
				wlDomains := parseWhitelistLine(rawLine)
				for _, domain := range wlDomains {
					if domain != "" {
						newWhitelistFromLists[domain] = struct{}{}
						whitelistCount++
					}
				}
				continue
			}
			
			// Block sorok kezelése
			domains := parseLine(rawLine)
			for _, domain := range domains {
				if domain != "" {
					newBlockMap[domain] = struct{}{}
					domainCount++
				}
			}
		}
		resp.Body.Close()
		
		if err := scanner.Err(); err != nil {
			log.Printf("[BLOCKLIST] ⚠️ Olvasási hiba (%s): %v", list.Name, err)
		}
		
		// Domain számláló tárolása ehhez az URL-hez
		newListCounts[list.URL] = domainCount
		
		successCount++
		log.Printf("[BLOCKLIST] ✅ %s: %d sor, %d block, %d whitelist", list.Name, lineCount, domainCount, whitelistCount)
	}

	newWhitelist := make(map[string]struct{})
	newBlacklist := make(map[string]struct{})
	
	// Listákból származó whitelist hozzáadása
	for domain := range newWhitelistFromLists {
		newWhitelist[domain] = struct{}{}
	}

	// NINCS alapértelmezett védett domain - te döntöd el a webes felületen!

	config.Mutex.RLock()
	for _, d := range config.Instance.Whitelist {
		if d != "" {
			newWhitelist[strings.ToLower(d)] = struct{}{}
		}
	}
	for _, d := range config.Instance.Blacklist {
		if d != "" {
			newBlacklist[strings.ToLower(d)] = struct{}{}
		}
	}
	config.Mutex.RUnlock()

	// 4️⃣ VÉDELEM: ha egyetlen lista sem töltődött be sikeresen
	if enabledCount > 0 && successCount == 0 {
		log.Printf("[BLOCKLIST] ❌ HIBA: Egyetlen lista sem töltődött be! Régi adatbázis marad aktív.")
		return
	}
	
	// Ha nincs engedélyezett lista
	if enabledCount == 0 {
		log.Printf("[BLOCKLIST] ⚠️ Nincs engedélyezett szűrőlista!")
	}

	// 5️⃣ RÉGI ADATBÁZIS TELJES TÖRLÉSE ÉS ÚJ AKTIVÁLÁSA
	m.Mutex.Lock()
	// Explicit törlés a régi map-ből (GC segítése)
	for k := range m.BlockMap {
		delete(m.BlockMap, k)
	}
	// Új adatok beállítása
	m.BlockMap = newBlockMap
	m.WhitelistMap = newWhitelist
	m.BlacklistMap = newBlacklist
	m.ListCounts = newListCounts
	m.LastUpdate = time.Now()
	m.Mutex.Unlock()

	// Statisztika azonnali frissítése
	atomic.StoreUint64(&m.StatsDatabase, uint64(len(newBlockMap)))
	
	log.Printf("[BLOCKLIST] ✅ Frissítés kész!")
	log.Printf("[BLOCKLIST] 📊 Összesen: %d domain | Sikeres listák: %d/%d | Hibás: %d", 
		len(newBlockMap), successCount, enabledCount, errorCount)
}

// StartUpdateLoop runs the update periodically
func StartUpdateLoop() {
	Global.Update()

	ticker := time.NewTicker(48 * time.Hour)
	for range ticker.C {
		Global.Update()
	}
}

// UpdateLocalLists frissíti CSAK a helyi whitelist/blacklist map-et (gyors, nem tölt le semmit)
func (m *Manager) UpdateLocalLists() {
	log.Printf("[BLOCKLIST] 🔄 Helyi whitelist/blacklist frissítése...")
	
	m.Mutex.Lock()
	defer m.Mutex.Unlock()
	
	// Whitelist újraépítése - CSAK a config-ból, nincs alapértelmezett!
	newWhitelist := make(map[string]struct{})
	
	// Config whitelist
	config.Mutex.RLock()
	for _, d := range config.Instance.Whitelist {
		if d != "" {
			newWhitelist[strings.ToLower(d)] = struct{}{}
		}
	}
	
	// Config blacklist
	newBlacklist := make(map[string]struct{})
	for _, d := range config.Instance.Blacklist {
		if d != "" {
			newBlacklist[strings.ToLower(d)] = struct{}{}
		}
	}
	config.Mutex.RUnlock()
	
	// Meglévő listából származó whitelist megtartása
	for domain := range m.WhitelistMap {
		newWhitelist[domain] = struct{}{}
	}
	
	m.WhitelistMap = newWhitelist
	m.BlacklistMap = newBlacklist
	
	log.Printf("[BLOCKLIST] ✅ Helyi listák frissítve! Whitelist: %d, Blacklist: %d", len(newWhitelist), len(newBlacklist))
}

func parseLine(line string) []string {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "!") {
		return nil
	}
	
	// Skip section headers (=====)
	if strings.HasPrefix(line, "=") {
		return nil
	}

	// Remove inline comments
	if idx := strings.Index(line, "#"); idx != -1 {
		line = strings.TrimSpace(line[:idx])
	}

	var domains []string

	// AdGuard Whitelist format: @@||domain^
	// Ezeket KÜLÖN kezeljük a whitelist-ben, nem itt
	if strings.HasPrefix(line, "@@") {
		return nil // Whitelist-et máshol kezeljük
	}

	// AdGuard/uBlock format: ||domain^
	if strings.HasPrefix(line, "||") && strings.HasSuffix(line, "^") {
		domain := strings.TrimPrefix(line, "||")
		domain = strings.TrimSuffix(domain, "^")
		// URL path eltávolítása (pl. youtube.com/api/stats -> youtube.com)
		if idx := strings.Index(domain, "/"); idx != -1 {
			domain = domain[:idx]
		}
		if clean := cleanDomain(domain); clean != "" {
			domains = append(domains, clean)
		}
		return domains
	}

	// AdGuard format: ||domain.com^$third-party vagy ||domain.com^$important
	if strings.HasPrefix(line, "||") && strings.Contains(line, "^") {
		parts := strings.SplitN(line, "^", 2)
		if len(parts) > 0 {
			domain := strings.TrimPrefix(parts[0], "||")
			// URL path eltávolítása
			if idx := strings.Index(domain, "/"); idx != -1 {
				domain = domain[:idx]
			}
			if clean := cleanDomain(domain); clean != "" {
				domains = append(domains, clean)
			}
		}
		return domains
	}

	// Hosts format: 0.0.0.0 domain.com
	// or: 127.0.0.1 domain.com
	fields := strings.Fields(line)
	if len(fields) >= 2 {
		ip := fields[0]
		if ip == "0.0.0.0" || ip == "127.0.0.1" || ip == "::1" {
			for i := 1; i < len(fields); i++ {
				domain := fields[i]
				if domain == "localhost" || domain == "localhost.localdomain" || domain == "local" {
					continue
				}
				if clean := cleanDomain(domain); clean != "" {
					domains = append(domains, clean)
				}
			}
			return domains
		}
	}

	// Simple domain list (one per line)
	if len(fields) == 1 && net.ParseIP(fields[0]) == nil {
		if clean := cleanDomain(fields[0]); clean != "" {
			domains = append(domains, clean)
		}
		return domains
	}

	// DNSmasq format: address=/domain.com/0.0.0.0
	if strings.HasPrefix(line, "address=/") {
		parts := strings.Split(line, "/")
		if len(parts) >= 3 {
			domain := parts[1]
			if clean := cleanDomain(domain); clean != "" {
				domains = append(domains, clean)
			}
		}
		return domains
	}

	// Wildcard support: *.domain.com -> domain.com
	if strings.HasPrefix(line, "*.") {
		domain := strings.TrimPrefix(line, "*.")
		if clean := cleanDomain(domain); clean != "" {
			domains = append(domains, clean)
		}
		return domains
	}

	return nil
}

// parseWhitelistLine parses AdGuard whitelist format: @@||domain^
func parseWhitelistLine(line string) []string {
	line = strings.TrimSpace(line)
	if !strings.HasPrefix(line, "@@") {
		return nil
	}
	
	// Remove @@ prefix
	line = strings.TrimPrefix(line, "@@")
	
	var domains []string
	
	// Format: @@||domain^
	if strings.HasPrefix(line, "||") && strings.Contains(line, "^") {
		parts := strings.SplitN(line, "^", 2)
		if len(parts) > 0 {
			domain := strings.TrimPrefix(parts[0], "||")
			// URL path eltávolítása
			if idx := strings.Index(domain, "/"); idx != -1 {
				domain = domain[:idx]
			}
			if clean := cleanDomain(domain); clean != "" {
				domains = append(domains, clean)
			}
		}
	}
	
	return domains
}

func cleanDomain(d string) string {
	d = strings.ToLower(d)
	d = strings.TrimSpace(d)
	d = strings.TrimSuffix(d, ".")
	if len(d) < 2 || strings.Contains(d, "/") || strings.Contains(d, " ") {
		return ""
	}
	return d
}

// IsBlocked checks if a domain is blocked (with subdomain support)
func (m *Manager) IsBlocked(domain string) bool {
	m.Mutex.RLock()
	defer m.Mutex.RUnlock()

	// Exact match
	if _, ok := m.BlockMap[domain]; ok {
		return true
	}
	if _, ok := m.BlacklistMap[domain]; ok {
		return true
	}

	// Subdomain/suffix match
	parts := strings.Split(domain, ".")
	for i := 0; i < len(parts)-1; i++ {
		suffix := strings.Join(parts[i:], ".")
		if _, ok := m.BlockMap[suffix]; ok {
			return true
		}
		if _, ok := m.BlacklistMap[suffix]; ok {
			return true
		}
	}

	return false
}

// IsWhitelisted checks if a domain is whitelisted (with subdomain support)
// BUT checks blacklist first for exact subdomain matches to allow blocking ad subdomains
func (m *Manager) IsWhitelisted(domain string) bool {
	m.Mutex.RLock()
	defer m.Mutex.RUnlock()

	// FIRST: Check if this exact domain is in the blacklist - if yes, NOT whitelisted
	if _, ok := m.BlacklistMap[domain]; ok {
		return false
	}
	if _, ok := m.BlockMap[domain]; ok {
		return false
	}

	// Exact whitelist match
	if _, ok := m.WhitelistMap[domain]; ok {
		return true
	}

	// Subdomain/suffix match for whitelist
	// But only if the subdomain itself is not in blacklist
	parts := strings.Split(domain, ".")
	for i := 0; i < len(parts)-1; i++ {
		suffix := strings.Join(parts[i:], ".")
		// Check if suffix is whitelisted
		if _, ok := m.WhitelistMap[suffix]; ok {
			// But the original domain must not be blacklisted
			return true
		}
	}

	return false
}
EOF

    # --- internal/dnsserver/server.go ---
cat << 'EOF' > internal/dnsserver/server.go
package dnsserver

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"frankdnsplus/internal/blocklist"
	"frankdnsplus/internal/cache"
	"frankdnsplus/internal/config"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

// Stats holds runtime statistics
type Stats struct {
	Total               uint64 `json:"total"`
	Blocked             uint64 `json:"blocked"`
	AIDetected          uint64 `json:"ai_detected"`
	Database            uint64 `json:"database"`
	NextReset           int64  `json:"next_reset"`
	NextBlocklistUpdate int64  `json:"next_blocklist_update"`
}

// LogEntry represents a single DNS query log
type LogEntry struct {
	Time     string `json:"time"`
	Domain   string `json:"domain"`
	Type     string `json:"type"`
	ClientIP string `json:"client_ip"`
	Status   string `json:"status"`
}

var (
	CurrentStats  Stats
	RecentLogs    []LogEntry
	LogsMutex     sync.Mutex
	dohClient     = &http.Client{Timeout: 5 * time.Second}
	NextResetTime time.Time

	aiKeywords = []string{
		"ads", "adservice", "adtracking", "metrics", "pixel", "tagmanager", "analytics", "telemetry",
		"tracker", "tracking", "beacon", "stat", "monitor", "logservice", "event", "segment",
		"collect", "engage", "measure", "api-ad", "marketing", "promotion", "sponsor", "optimizely",
		"hotjar", "mouseflow", "sentry", "bugsnag", "clarity", "amplitude", "mixpanel",
	}
)

// Start initializes the DNS server on the specified protocol (udp/tcp)
func Start(proto string) {
	config.Mutex.RLock()
	addr := config.Instance.ListenDNS
	config.Mutex.RUnlock()

	srv := &dns.Server{Addr: addr, Net: proto}
	srv.Handler = dns.HandlerFunc(handleRequest)

	log.Printf("Starting DNS server on %s/%s", addr, proto)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("DNS Server error (%s): %v", proto, err)
	}
}

func handleRequest(w dns.ResponseWriter, r *dns.Msg) {
	atomic.AddUint64(&CurrentStats.Total, 1)

	if len(r.Question) > 0 {
		if cachedMsg := cache.Global.Get(r.Question[0]); cachedMsg != nil {
			cachedMsg.SetReply(r)
			cachedMsg.Compress = false
			w.WriteMsg(cachedMsg)
			return
		}
	}

	m := new(dns.Msg)
	m.SetReply(r)
	m.Compress = false

	if len(r.Question) == 0 {
		w.WriteMsg(m)
		return
	}

	q := r.Question[0]
	qType := dns.TypeToString[q.Qtype]
	name := strings.ToLower(strings.TrimSuffix(q.Name, "."))
	clientIP, _, _ := net.SplitHostPort(w.RemoteAddr().String())
	status := "Allowed"

	config.Mutex.RLock()
	blockingOn := config.Instance.BlockingEnabled
	aiEnabled := config.Instance.AIDetection
	agressiveAI := config.Instance.AgressiveAIBlocking
	config.Mutex.RUnlock()

	if !blockingOn {
		forwardDNS(w, r, clientIP, "Allowed (Szünet)", name, qType)
		return
	}

	isAiDetected := false
	if aiEnabled {
		for _, kw := range aiKeywords {
			if strings.Contains(name, kw) {
				isAiDetected = true
				break
			}
		}
	}

	// Check whitelist first (with subdomain support)
	if blocklist.Global.IsWhitelisted(name) {
		forwardDNS(w, r, clientIP, "Allowed", name, qType)
		return
	}

	if isAiDetected {
		atomic.AddUint64(&CurrentStats.AIDetected, 1)
		if agressiveAI {
			atomic.AddUint64(&CurrentStats.Blocked, 1)
			AddLog(name, qType, clientIP, "Blocked (AI)")
			blockDNS(w, r)
			return
		}
		status = "Allowed (AI)"
	}

	// Check blacklist/blocklist (with subdomain support)
	if blocklist.Global.IsBlocked(name) {
		atomic.AddUint64(&CurrentStats.Blocked, 1)
		AddLog(name, qType, clientIP, "Blocked")
		blockDNS(w, r)
		return
	}

	forwardDNS(w, r, clientIP, status, name, qType)
}

func forwardDNS(w dns.ResponseWriter, r *dns.Msg, clientIP, status, name, qType string) {
	config.Mutex.RLock()
	upstreams := config.Instance.Upstreams
	blockingOn := config.Instance.BlockingEnabled
	agressiveAI := config.Instance.AgressiveAIBlocking
	aiEnabled := config.Instance.AIDetection
	config.Mutex.RUnlock()

	if len(upstreams) == 0 {
		upstreams = []string{"1.1.1.1", "8.8.8.8"}
	}

	target := upstreams[time.Now().UnixNano()%int64(len(upstreams))]
	resp := new(dns.Msg)
	var err error

	tryUpstreams := make([]string, len(upstreams))
	copy(tryUpstreams, upstreams)
	for i := 0; i < len(tryUpstreams); i++ {
		if tryUpstreams[i] == target {
			tryUpstreams[i], tryUpstreams[0] = tryUpstreams[0], tryUpstreams[i]
			break
		}
	}

	for _, u := range tryUpstreams {
		if strings.HasPrefix(u, "https://") {
			resp, err = doHQuery(r, u)
		} else if strings.HasPrefix(u, "tls://") {
			uTarget := strings.TrimPrefix(u, "tls://")
			serverName := uTarget // Eredeti hostname a TLS ellenőrzéshez
			if !strings.Contains(uTarget, ":") {
				uTarget += ":853"
			} else {
				serverName = strings.Split(uTarget, ":")[0]
			}
			c := new(dns.Client)
			c.Net = "tcp-tls"
			c.TLSConfig = &tls.Config{
				ServerName:         serverName,
				InsecureSkipVerify: false, // Biztonságos: tanúsítvány ellenőrzés BE
			}
			c.Timeout = 2 * time.Second
			resp, _, err = c.Exchange(r, uTarget)
		} else {
			uTarget := u
			if !strings.Contains(uTarget, ":") {
				uTarget += ":53"
			}
			c := new(dns.Client)
			c.Timeout = 2 * time.Second
			resp, _, err = c.Exchange(r, uTarget)
		}
		if err == nil && resp != nil {
			break
		}
	}

	if err != nil || resp == nil {
		log.Printf("[DNS] Hiba a forward során (%s): %v", name, err)
		m := new(dns.Msg)
		m.SetRcode(r, dns.RcodeServerFailure)
		w.WriteMsg(m)
		AddLog(name, qType, clientIP, "Error")
		return
	}

	if len(resp.Answer) > 0 {
		cache.Global.Set(r.Question[0], resp)
	}

	if blockingOn {
		// Check CNAME chains for hidden trackers
		for _, rr := range resp.Answer {
			if cname, ok := rr.(*dns.CNAME); ok {
				target := strings.ToLower(strings.TrimSuffix(cname.Target, "."))
				
				// Check whitelist for CNAME target
				if blocklist.Global.IsWhitelisted(target) {
					continue
				}

				// Check blacklist/blocklist for CNAME target
				if blocklist.Global.IsBlocked(target) {
					atomic.AddUint64(&CurrentStats.Blocked, 1)
					AddLog(name, qType, clientIP, "Blocked (CNAME)")
					blockDNS(w, r)
					return
				}

				// AI detection for CNAME target
				if aiEnabled && agressiveAI {
					for _, kw := range aiKeywords {
						if strings.Contains(target, kw) {
							atomic.AddUint64(&CurrentStats.AIDetected, 1)
							atomic.AddUint64(&CurrentStats.Blocked, 1)
							AddLog(name, qType, clientIP, "Blocked (AI CNAME)")
							blockDNS(w, r)
							return
						}
					}
				}
			}
		}
	}

	AddLog(name, qType, clientIP, status)
	w.WriteMsg(resp)
}

func doHQuery(r *dns.Msg, url string) (*dns.Msg, error) {
	packed, err := r.Pack()
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", url, bytes.NewReader(packed))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/dns-message")
	resp, err := dohClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("DoH error: %d", resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	m := new(dns.Msg)
	err = m.Unpack(data)
	if err != nil {
		return nil, err
	}
	m.SetReply(r)
	return m, nil
}

func blockDNS(w dns.ResponseWriter, r *dns.Msg) {
	config.Mutex.RLock()
	mode := config.Instance.ResponseMode
	config.Mutex.RUnlock()

	m := new(dns.Msg)
	m.SetReply(r)

	if mode == "nxdomain" {
		m.SetRcode(r, dns.RcodeNameError)
	} else {
		q := r.Question[0]
		if q.Qtype == dns.TypeA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 3600 IN A 0.0.0.0", q.Name))
			m.Answer = append(m.Answer, rr)
		} else if q.Qtype == dns.TypeAAAA {
			rr, _ := dns.NewRR(fmt.Sprintf("%s 3600 IN AAAA ::", q.Name))
			m.Answer = append(m.Answer, rr)
		}
	}
	w.WriteMsg(m)
}

func AddLog(domain, dnsType, clientIP, status string) {
	LogsMutex.Lock()
	defer LogsMutex.Unlock()

	config.Mutex.RLock()
	size := config.Instance.LogBufferSize
	config.Mutex.RUnlock()

	entry := LogEntry{
		Time:     time.Now().Format("15:04:05"),
		Domain:   domain,
		Type:     dnsType,
		ClientIP: clientIP,
		Status:   status,
	}
	RecentLogs = append(RecentLogs, entry)
	if len(RecentLogs) > size {
		RecentLogs = RecentLogs[1:]
	}
}

func ResetStats() {
	atomic.StoreUint64(&CurrentStats.Total, 0)
	atomic.StoreUint64(&CurrentStats.Blocked, 0)
	atomic.StoreUint64(&CurrentStats.AIDetected, 0)
}
EOF

    # --- internal/webapi/api.go ---
cat << 'EOF' > internal/webapi/api.go
package webapi

import (
	"encoding/json"
	"frankdnsplus/internal/blocklist"
	"frankdnsplus/internal/cache"
	"frankdnsplus/internal/config"
	"frankdnsplus/internal/dnsserver"
	"log"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"
)

// Start initializes the HTTP server
func Start() {
	config.Mutex.RLock()
	addr := config.Instance.ListenHTTP
	config.Mutex.RUnlock()

	http.Handle("/", http.FileServer(http.Dir("/home/robot_36/frankdnsplus/web")))
	http.HandleFunc("/api/stats", apiStats)
	http.HandleFunc("/api/logs", apiLogs)
	http.HandleFunc("/api/config", apiConfig)
	http.HandleFunc("/api/reset_stats", apiResetStats)
	http.HandleFunc("/api/update_blocklists", apiUpdateBlocklists)
	http.HandleFunc("/api/clear_cache", apiClearCache)
	http.HandleFunc("/api/blocklist_counts", apiBlocklistCounts)
	http.HandleFunc("/api/devices", apiDevices)
	http.HandleFunc("/api/update_device", apiUpdateDevice)
	http.HandleFunc("/api/delete_device", apiDeleteDevice)
	http.HandleFunc("/api/refresh_devices", apiRefreshDevices)
	http.HandleFunc("/api/restart", apiRestart)

	log.Printf("Starting Web API on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Web Server error: %v", err)
	}
}

func apiStats(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	dnsserver.CurrentStats.NextReset = dnsserver.NextResetTime.Unix()
	
	// Calculate next blocklist update time (48 hours from last update)
	blocklist.Global.Mutex.RLock()
	nextUpdate := blocklist.Global.LastUpdate.Add(48 * time.Hour).Unix()
	// Real-time database size calculation
	dbSize := uint64(len(blocklist.Global.BlockMap))
	blocklist.Global.Mutex.RUnlock()
	
	dnsserver.CurrentStats.NextBlocklistUpdate = nextUpdate
	dnsserver.CurrentStats.Database = dbSize
	
	// Update the stored stats as well
	atomic.StoreUint64(&blocklist.Global.StatsDatabase, dbSize)
	
	json.NewEncoder(w).Encode(dnsserver.CurrentStats)
}

func apiLogs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	dnsserver.LogsMutex.Lock()
	defer dnsserver.LogsMutex.Unlock()

	tempLogs := make([]dnsserver.LogEntry, len(dnsserver.RecentLogs))
	copy(tempLogs, dnsserver.RecentLogs)
	for i, j := 0, len(tempLogs)-1; i < j; i, j = i+1, j-1 {
		tempLogs[i], tempLogs[j] = tempLogs[j], tempLogs[i]
	}
	json.NewEncoder(w).Encode(tempLogs)
}

func apiConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method == "GET" {
		config.Mutex.RLock()
		json.NewEncoder(w).Encode(config.Instance)
		config.Mutex.RUnlock()
	} else if r.Method == "POST" {
		var newConfig config.Config
		if err := json.NewDecoder(r.Body).Decode(&newConfig); err != nil {
			log.Printf("[API] Config decode error: %v", err)
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		
		log.Printf("[API] Config POST received - Whitelist: %d items, Blacklist: %d items", 
			len(newConfig.Whitelist), len(newConfig.Blacklist))
		
		config.Mutex.Lock()
		*config.Instance = newConfig
		config.Mutex.Unlock()
		
		if err := config.Save(); err != nil {
			log.Printf("[API] Config save error: %v", err)
			http.Error(w, "Failed to save config: "+err.Error(), http.StatusInternalServerError)
			return
		}
		
		log.Printf("[API] Config saved successfully to disk")
		
		// AZONNAL frissítsük a blacklist/whitelist map-et (ne várjunk a lista letöltésre)
		blocklist.Global.UpdateLocalLists()
		
		// Háttérben frissítsük a távoli listákat is
		go blocklist.Global.Update()
		w.Write([]byte(`{"status":"ok"}`))
	}
}

func apiResetStats(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		dnsserver.ResetStats()
		dnsserver.NextResetTime = time.Now().Add(24 * time.Hour)
		w.Write([]byte(`{"status":"ok"}`))
	}
}

func apiRestart(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		log.Printf("[API] FrankDNS+ újraindítás kérés érkezett")
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","message":"Restarting..."}`))
		
		// Háttérben újraindítás 1 másodperc múlva
		go func() {
			time.Sleep(1 * time.Second)
			log.Printf("[API] FrankDNS+ szolgáltatás újraindítása...")
			exec.Command("systemctl", "restart", "frankdnsplus").Run()
		}()
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func apiUpdateBlocklists(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		// 1. Cache törlés ELŐBB
		cache.Global.Clear()
		log.Printf("[API] DNS cache törölve a frissítés előtt")
		
		// 2. Blocklist frissítés (szinkron)
		blocklist.Global.Update()
		
		// 3. Cache újra törlés UTÁN (biztos ami biztos)
		cache.Global.Clear()
		
		// Visszaadjuk az új statisztikát
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":   "ok",
			"message":  "Update completed",
			"database": blocklist.Global.StatsDatabase,
		})
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func apiClearCache(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		cache.Global.Clear()
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok", "message":"Cache cleared"}`))
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func apiBlocklistCounts(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	
	blocklist.Global.Mutex.RLock()
	counts := make(map[string]int)
	for url, count := range blocklist.Global.ListCounts {
		counts[url] = count
	}
	totalDomains := len(blocklist.Global.BlockMap)
	blocklist.Global.Mutex.RUnlock()
	
	response := map[string]interface{}{
		"counts": counts,
		"total":  totalDomains,
	}
	json.NewEncoder(w).Encode(response)
}

func apiDevices(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	config.Mutex.RLock()
	defer config.Mutex.RUnlock()
	json.NewEncoder(w).Encode(config.Instance.Devices)
}

func apiUpdateDevice(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var update struct {
		IP   string `json:"ip"`
		Name string `json:"name"`
	}

	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	config.Mutex.Lock()
	deviceFound := false
	for i, device := range config.Instance.Devices {
		if device.IP == update.IP {
			config.Instance.Devices[i].Name = update.Name
			config.Instance.Devices[i].LastSeen = time.Now().Format("2006-01-02 15:04:05")
			deviceFound = true
			break
		}
	}

	if !deviceFound {
		newDevice := config.Device{
			Name:     update.Name,
			IP:       update.IP,
			MAC:      "Manual",
			LastSeen: time.Now().Format("2006-01-02 15:04:05"),
		}
		config.Instance.Devices = append(config.Instance.Devices, newDevice)
	}

	config.Mutex.Unlock()
	config.Save()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "Device updated"})
}

func apiDeleteDevice(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		IP string `json:"ip"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	config.Mutex.Lock()
	newDevices := make([]config.Device, 0)
	for _, d := range config.Instance.Devices {
		if d.IP != req.IP {
			newDevices = append(newDevices, d)
		}
	}
	config.Instance.Devices = newDevices
	config.Mutex.Unlock()
	config.Save()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func apiRefreshDevices(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		go discoverDevices()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "message": "Discovery started"})
		return
	}
	http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
}

func discoverDevices() {
	newDevices := make([]config.Device, 0)
	seenIPs := make(map[string]bool)

	foundDevices := scanARP()

	// Also check DNS logs for client IPs
	dnsserver.LogsMutex.Lock()
	for _, l := range dnsserver.RecentLogs {
		if l.ClientIP != "" && l.ClientIP != "127.0.0.1" && l.ClientIP != "::1" {
			found := false
			for _, d := range foundDevices {
				if d.IP == l.ClientIP {
					found = true
					break
				}
			}
			if !found {
				foundDevices = append(foundDevices, config.Device{IP: l.ClientIP})
			}
		}
	}
	dnsserver.LogsMutex.Unlock()

	config.Mutex.RLock()
	savedDevices := config.Instance.Devices
	config.Mutex.RUnlock()

	savedMap := make(map[string]config.Device)
	for _, d := range savedDevices {
		savedMap[d.IP] = d
	}

	for _, d := range foundDevices {
		if seenIPs[d.IP] || d.IP == "127.0.0.1" || d.IP == "::1" || d.IP == "" {
			continue
		}
		seenIPs[d.IP] = true

		finalName := ""
		finalMAC := d.MAC

		// 1. First priority: saved custom name (if exists and not auto-generated)
		if saved, exists := savedMap[d.IP]; exists {
			if saved.Name != "" && !strings.HasPrefix(saved.Name, "Device_") && !strings.HasPrefix(saved.Name, "Unknown_") {
				finalName = saved.Name
			}
			if finalMAC == "" || finalMAC == "Unknown" {
				finalMAC = saved.MAC
			}
		}

		// 2. Second priority: DNS reverse lookup (PTR record)
		if finalName == "" {
			ptrNames, err := net.LookupAddr(d.IP)
			if err == nil && len(ptrNames) > 0 {
				for _, n := range ptrNames {
					n = strings.TrimSuffix(n, ".")
					if !strings.Contains(n, "in-addr.arpa") && !strings.Contains(n, "ip6.arpa") {
						// Clean up PTR name (remove domain suffixes)
						parts := strings.Split(n, ".")
						if len(parts) > 0 {
							finalName = parts[0]
							break
						}
					}
				}
			}
		}

		// 3. Third priority: Try to get MAC from ARP if not already available
		if finalMAC == "" {
			cmd := exec.Command("arp", "-n", d.IP)
			output, err := cmd.Output()
			if err == nil {
				lines := strings.Split(string(output), "\n")
				for _, line := range lines {
					parts := strings.Fields(line)
					if len(parts) >= 3 && parts[0] == d.IP {
						finalMAC = parts[2]
						break
					}
				}
			}
		}

		// 4. Fourth priority: Generate name from MAC (keep existing if already has Device_ prefix)
		if finalName == "" {
			if saved, exists := savedMap[d.IP]; exists && saved.Name != "" {
				// Keep existing name even if it's Device_xxx
				finalName = saved.Name
			} else if finalMAC != "" && finalMAC != "00:00:00:00:00:00" {
				cleanMAC := strings.ReplaceAll(finalMAC, ":", "")
				if len(cleanMAC) > 6 {
					// Use last 6 chars of MAC for consistent naming
					finalName = "Device_" + strings.ToUpper(cleanMAC[len(cleanMAC)-6:])
				} else {
					finalName = "Device_" + cleanMAC
				}
			} else {
				// 5. Final fallback: IP-based name (stable, won't change)
				finalName = "Device_" + strings.ReplaceAll(d.IP, ".", "_")
			}
		}

		newDevices = append(newDevices, config.Device{
			Name:     finalName,
			IP:       d.IP,
			MAC:      finalMAC,
			LastSeen: time.Now().Format("2006-01-02 15:04:05"),
		})
	}

	// Keep manually added devices that aren't currently online
	for _, saved := range savedDevices {
		if !seenIPs[saved.IP] {
			newDevices = append(newDevices, saved)
			seenIPs[saved.IP] = true
		}
	}

	config.Mutex.Lock()
	config.Instance.Devices = newDevices
	config.Mutex.Unlock()
	config.Save()
}

func scanARP() []config.Device {
	devices := []config.Device{}
	
	// Try arp -a first (more readable format)
	cmd := exec.Command("arp", "-a")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			parts := strings.Fields(line)
			if len(parts) >= 4 {
				ip := strings.Trim(parts[1], "()")
				mac := parts[3]
				if mac != "incomplete" && net.ParseIP(ip) != nil {
					devices = append(devices, config.Device{IP: ip, MAC: mac})
				}
			}
		}
	}
	
	// Fallback to ip neigh if arp -a fails
	if len(devices) == 0 {
		cmd = exec.Command("ip", "neigh")
		output, err = cmd.Output()
		if err == nil {
			lines := strings.Split(string(output), "\n")
			for _, line := range lines {
				parts := strings.Fields(line)
				if len(parts) >= 5 && parts[0] != "" {
					ip := parts[0]
					mac := parts[4]
					if mac != "FAILED" && mac != "INCOMPLETE" && net.ParseIP(ip) != nil {
						devices = append(devices, config.Device{IP: ip, MAC: mac})
					}
				}
			}
		}
	}
	
	return devices
}

func StartDiscoveryLoop() {
	discoverDevices()
	ticker := time.NewTicker(60 * time.Second)
	for range ticker.C {
		discoverDevices()
	}
}
EOF

    # --- cmd/frankdns/main.go ---
cat << 'EOF' > cmd/frankdns/main.go
package main

import (
	"frankdnsplus/internal/blocklist"
	"frankdnsplus/internal/cache"
	"frankdnsplus/internal/config"
	"frankdnsplus/internal/dnsserver"
	"frankdnsplus/internal/webapi"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	log.Println("FrankDNS+ 2026 Modular Engine Starting...")

	config.Load()
	log.Println("Configuration loaded.")

	go cache.StartCleanupRoutine()
	go blocklist.StartUpdateLoop()
	go webapi.StartDiscoveryLoop()

	dnsserver.NextResetTime = time.Now().Add(24 * time.Hour)
	go func() {
		for {
			time.Sleep(time.Until(dnsserver.NextResetTime))
			dnsserver.ResetStats()
			dnsserver.NextResetTime = time.Now().Add(24 * time.Hour)
		}
	}()

	go webapi.Start()
	go dnsserver.Start("udp")
	go dnsserver.Start("tcp")

	log.Println("FrankDNS+ is fully operational.")

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig

	log.Println("Shutting down...")
	config.Save()
	log.Println("Goodbye.")
}
EOF

    print_block "4. LÉPÉS: Webes Felület Generálása"

    # --- web/index.html ---
cat << 'EOF' > web/index.html
<!DOCTYPE html>
<html lang="hu">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FrankDNS+ 2026 Neon Flux</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
<div class="container">
    <div class="header">
        <div class="logo-area">
            <svg class="logo-svg" viewBox="0 0 100 100">
                <defs>
                    <linearGradient id="shieldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#00d2ff;stop-opacity:1" />
                        <stop offset="100%" style="stop-color:#39ff14;stop-opacity:1" />
                    </linearGradient>
                </defs>
                <path d="M50 5 L15 20 V50 C15 75 30 92 50 98 C70 92 85 75 85 50 V20 L50 5 Z" fill="none" stroke="url(#shieldGrad)" stroke-width="3" />
                <path d="M50 25 L35 45 L50 65 L65 45 Z" fill="url(#shieldGrad)">
                    <animate attributeName="opacity" values="0.5;1;0.5" dur="2s" repeatCount="indefinite" />
                </path>
                <circle cx="50" cy="45" r="2" fill="#fff" />
            </svg>
            <h1>FrankDNS+ <span style="font-weight:300; opacity:0.8; font-size:0.7em;">2026</span></h1>
            <div class="status-badge"><div class="blink-dot"></div>ONLINE</div>
        </div>
        <div>
            <button id="rgb-toggle" class="btn" onclick="toggleRGB()" style="margin-right: 10px; border: 1px solid rgba(255,255,255,0.3);">🌈 RGB</button>
            <button id="restart-btn" class="btn" onclick="restartService()" style="margin-right: 10px; border: 1px solid #f39c12; color: #f39c12;">🔄 Újraindítás</button>
            <button id="main-toggle" class="toggle-protection prot-on" onclick="toggleProtection()">VÉDELEM: AKTÍV</button>
        </div>
    </div>

    <div class="nav">
        <button class="nav-btn active" onclick="showTab('dashboard')">Dashboard</button>
        <button class="nav-btn" onclick="showTab('filters')">Szűrőlisták</button>
        <button class="nav-btn" onclick="showTab('exceptions')">Kivételek</button>
        <button class="nav-btn" onclick="showTab('devices')">Eszközök</button>
        <button class="nav-btn" onclick="showTab('settings')">Beállítások</button>
    </div>
    
    <div id="dashboard" class="tab-content active">
        <div class="card">
            <div style="display:flex;justify-content:space-between;align-items:center;">
                <h3>Statisztika</h3>
                <button class="btn btn-danger" style="font-size:0.8em; padding: 5px 10px;" onclick="manualReset()">Nullázás</button>
            </div>
            <div class="grid-stats">
                <div><div class="stat-label">Összes</div><div class="stat-value" id="stat-total">0</div></div>
                <div><div class="stat-label">Blokkolva</div><div class="stat-value" id="stat-blocked" style="color:var(--danger)">0</div></div>
                <div><div class="stat-label">AI Detektált</div><div class="stat-value" id="stat-ai" style="color:var(--warning)">0</div></div>
                <div><div class="stat-label">Adatbázis</div><div class="stat-value" id="stat-db" style="font-size: 1.8em; color: #888;">0</div></div>
            </div>
            <div class="reset-info" style="margin-top:20px; font-size:0.8em; color:#666;">
                Következő automata törlés: <span id="reset-timer" style="color:var(--neon-blue)">--:--:--</span>
            </div>
        </div>

        <h3>Élő Log</h3>
        <div style="margin-bottom: 20px;"><input type="text" id="log-search" placeholder="Keresés..." onkeyup="renderLogs()"></div>
        <div class="log-container">
            <table>
                <thead>
                    <tr>
                        <th style="width: 10%">Idő</th>
                        <th style="width: 30%">Domain</th>
                        <th style="width: 8%">Típus</th>
                        <th style="width: 20%">Eszköz / IP</th>
                        <th style="width: 12%">Státusz</th>
                        <th style="width: 20%; text-align: right;">Műveletek</th>
                    </tr>
                </thead>
                <tbody id="log-body"></tbody>
            </table>
        </div>
    </div>
    
    <div id="filters" class="tab-content">
        <div class="card">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
                <h3>Szűrőlisták</h3>
                <span id="blocklist-timer" style="font-size:0.8em; color:#666;">-- nap</span>
            </div>
            
            <!-- Vezérlő gombok -->
            <div style="display:flex; gap:10px; margin-bottom:20px; flex-wrap:wrap;">
                <button id="update-button" class="btn" style="flex:1; min-width:200px; border-color:var(--neon-green); color:var(--neon-green);" onclick="manualBlocklistUpdate()">
                    <span id="update-text">🔄 Frissítés Indítása</span>
                    <span id="update-status-container"><div id="spinner-loading" class="spinner"></div></span>
                </button>
                <button class="btn" style="border-color:var(--neon-blue); color:var(--neon-blue);" onclick="enableAllBlocklists()">✅ Összes BE</button>
                <button class="btn" style="border-color:var(--danger); color:var(--danger);" onclick="disableAllBlocklists()">❌ Összes KI</button>
            </div>
            
            <!-- Összesítő panel -->
            <div id="blocklist-summary" style="background:linear-gradient(135deg, rgba(0,210,255,0.1), rgba(57,255,20,0.1)); border:1px solid rgba(0,210,255,0.3); border-radius:15px; padding:20px; margin-bottom:25px;">
                <div style="display:flex; justify-content:space-around; text-align:center; flex-wrap:wrap; gap:15px;">
                    <div>
                        <div style="font-size:0.8em; color:#888; text-transform:uppercase;">Aktív listák</div>
                        <div id="summary-active" style="font-size:2em; font-weight:bold; color:var(--neon-green);">0</div>
                    </div>
                    <div>
                        <div style="font-size:0.8em; color:#888; text-transform:uppercase;">Inaktív listák</div>
                        <div id="summary-inactive" style="font-size:2em; font-weight:bold; color:var(--danger);">0</div>
                    </div>
                    <div>
                        <div style="font-size:0.8em; color:#888; text-transform:uppercase;">Összes domain</div>
                        <div id="summary-total" style="font-size:2em; font-weight:bold; color:var(--neon-blue);">0</div>
                    </div>
                </div>
            </div>
            
            <div id="blocklist-editor"></div>
            
            <!-- Alsó összesítő -->
            <div id="blocklist-total-bar" style="background:#111; border:1px solid #333; border-radius:10px; padding:15px; margin-top:20px; display:flex; justify-content:space-between; align-items:center;">
                <span style="color:#888;">📊 Összesen betöltött domain:</span>
                <span id="total-domains-count" style="font-size:1.5em; font-weight:bold; color:var(--neon-green);">0</span>
            </div>
            
            <button class="btn" style="width:100%; margin-top:15px; border-style:dashed; color:#666;" onclick="addNewBlocklist()">+ Lista hozzáadása</button>
            <button class="btn" style="width:100%; margin-top:10px;" onclick="saveBlocklists()">💾 Mentés</button>
        </div>
    </div>

    <div id="exceptions" class="tab-content">
        <div class="card">
            <h3>Fehérlista (Whitelist)</h3>
            <textarea id="txt-whitelist" placeholder="facebook.com..."></textarea>
            <h3 style="margin-top: 30px;">Feketelista (Blacklist)</h3>
            <textarea id="txt-blacklist" placeholder="ads.example.com..."></textarea>
            <button class="btn" style="margin-top:20px;" onclick="saveLists()">Mentés</button>
        </div>
    </div>
    
    <div id="devices" class="tab-content">
        <div class="card">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                <h3>Eszközkezelő</h3>
                <button class="btn" onclick="refreshDevices()">
                    <span id="refresh-text">🔁 Frissítés</span>
                    <div id="spinner-refresh" class="spinner"></div>
                </button>
            </div>
            
            <div style="margin-bottom: 20px; padding: 15px; background: rgba(0,0,0,0.3); border-radius: 10px;">
                <h4 style="margin-top: 0; color: var(--neon-blue);">Manuális eszköz hozzáadása</h4>
                <div class="device-field">
                    <label>IP cím:</label>
                    <input type="text" id="new-device-ip" placeholder="192.168.1.100">
                </div>
                <div class="device-field">
                    <label>Eszköznév:</label>
                    <input type="text" id="new-device-name" placeholder="pl. Peter laptopja">
                </div>
                <div class="device-actions">
                    <button class="btn" onclick="addNewDevice()">➕ Mentés</button>
                </div>
            </div>
            
            <h4>Felfedezett eszközök</h4>
            <table>
                <thead>
                    <tr>
                        <th style="width: 25%">Eszköznév</th>
                        <th style="width: 20%">IP cím</th>
                        <th style="width: 20%">MAC cím</th>
                        <th style="width: 20%">Utolsó látva</th>
                        <th style="width: 15%">Műveletek</th>
                    </tr>
                </thead>
                <tbody id="device-table-body">
                    <tr><td colspan="5" style="text-align: center; padding: 30px; color: #666;">Eszközök betöltése...</td></tr>
                </tbody>
            </table>
        </div>
    </div>
    
    <div id="settings" class="tab-content">
        <div class="card">
            <h3 id="dns-header">DNS Szerverek (TLS)</h3>
            <div style="margin-bottom:15px;">
                <button id="btn-cloudflare-dot" class="btn-dns" onclick="toggleDNS('Cloudflare DoT')">Cloudflare</button>
                <button id="btn-quad9-dot" class="btn-dns" onclick="toggleDNS('Quad9 DoT')">Quad9</button>
                <button id="btn-google-dot" class="btn-dns" onclick="toggleDNS('Google DoT')">Google</button>
            </div>
            <textarea id="txt-upstream" onkeyup="updateDNSButtons()" style="height:100px;"></textarea>
            
            <h3 style="margin-top:30px;">AI Védelem</h3>
            <div style="display:flex; align-items:center; margin-bottom:15px;">
                <div style="flex-grow:1;">AI Detektálás <span id="ai-status-text" style="font-size:0.8em; color:var(--warning)">(BE)</span></div>
                <label class="switch"><input type="checkbox" id="chk-ai" onchange="updateAIText()"><span class="slider"></span></label>
            </div>
            <div style="display:flex; align-items:center;">
                <div style="flex-grow:1;">Agresszív Blokkolás <span id="ai-aggro-text" style="font-size:0.8em; color:#666">(KI)</span></div>
                <label class="switch"><input type="checkbox" id="chk-ai-aggro" onchange="updateAIAggroText()"><span class="slider"></span></label>
            </div>
            
            <h3 style="margin-top:30px;">Egyéb</h3>
            <div style="display:flex; align-items:center;">
                <div style="flex-grow:1;">Blokkolási mód</div>
                <select id="sel-mode" style="width:150px;"><option value="zero">0.0.0.0</option><option value="nxdomain">NXDOMAIN</option></select>
            </div>
            
            <button class="btn" style="margin-top:30px; width:100%;" onclick="saveSettings()">Beállítások Mentése</button>
        </div>
    </div>
</div>
<div id="toast">Üzenet...</div>
<script src="app.js"></script>
</body>
</html>
EOF

    # --- web/style.css ---
cat << 'EOF' > web/style.css
:root {
    --bg-dark: #050505;
    --card-dark: #101010;
    --text-main: #f0f0f0;
    --neon-blue: #00d2ff;
    --neon-pink: #d9138a;
    --neon-green: #39ff14;
    --danger: #ff416c;
    --warning: #f7971e;
}
body { 
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; 
    background: var(--bg-dark); 
    color: var(--text-main); 
    margin: 0; padding: 20px; 
    min-height: 100vh;
}
.container { max-width: 1400px; margin: 0 auto; }

.card, .log-container { 
    position: relative;
    background: var(--card-dark);
    border-radius: 20px;
    padding: 25px;
    margin-bottom: 30px;
    overflow: hidden;
    z-index: 1;
}

.card::before, .log-container::before {
    content: '';
    position: absolute;
    top: -50%; left: -50%;
    width: 200%; height: 200%;
    background: conic-gradient(transparent, transparent, transparent, var(--neon-blue));
    animation: rotate 4s linear infinite;
    z-index: -2;
    transition: all 0.5s ease;
}

body.rgb-active .card::before, body.rgb-active .log-container::before {
    background: conic-gradient(transparent, transparent, transparent, #ff0000, #ffff00, #00ff00, #00ffff, #0000ff, #ff00ff, #ff0000);
    animation: rotate 4s linear infinite;
}

.card::after, .log-container::after {
    content: '';
    position: absolute;
    inset: 3px;
    background: var(--card-dark);
    border-radius: 17px;
    z-index: -1;
}

.card > *, .log-container > * { position: relative; z-index: 2; }

@keyframes rotate { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

h1, h2, h3 { margin-top: 0; color: #fff; letter-spacing: 1px; font-weight: 600; }

h1 {
    background: linear-gradient(90deg, #00d2ff, #39ff14);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-shadow: 0 0 20px rgba(0, 210, 255, 0.3);
    font-weight: 800;
}

.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 40px; }
.logo-area { display: flex; align-items: center; gap: 20px; }
.logo-svg { width: 70px; height: 70px; filter: drop-shadow(0 0 10px var(--neon-blue)); }

.nav { display: flex; gap: 10px; margin-bottom: 30px; flex-wrap: wrap; }
.nav-btn { 
    background: transparent; 
    color: #888; 
    border: 1px solid #333; 
    padding: 12px 25px; 
    border-radius: 30px; 
    cursor: pointer; 
    font-weight: 500;
    transition: 0.3s;
}
.nav-btn:hover { border-color: var(--neon-blue); color: #fff; box-shadow: 0 0 10px rgba(0,210,255,0.3); }
.nav-btn.active { 
    background: rgba(0, 210, 255, 0.1); 
    border-color: var(--neon-blue); 
    color: var(--neon-blue); 
    box-shadow: 0 0 15px rgba(0, 210, 255, 0.2); 
}

input[type="text"], textarea, select {
    width: 100%; padding: 15px; 
    background: #000;
    border: 1px solid #333;
    border-radius: 10px;
    color: #fff;
    box-sizing: border-box;
    transition: 0.3s;
}
input:focus, textarea:focus { 
    border-color: var(--neon-blue); 
    box-shadow: 0 0 15px rgba(0, 210, 255, 0.2); 
    outline: none; 
}

#txt-whitelist, #txt-blacklist {
    border: 2px solid #333; 
    background: #080808;
    min-height: 250px;
    font-family: monospace;
}
#txt-whitelist:focus, #txt-blacklist:focus {
    border-color: var(--neon-blue);
    box-shadow: 0 0 20px rgba(0, 210, 255, 0.3);
}

table { width: 100%; border-collapse: collapse; }
th { text-align: left; padding: 15px; color: #666; font-size: 0.8em; text-transform: uppercase; border-bottom: 1px solid #333; }
td { padding: 15px; border-bottom: 1px solid #222; font-size: 0.9em; vertical-align: middle; }
tr:hover td { background: rgba(255,255,255,0.02); }

.status-badge { display: flex; align-items: center; gap: 12px; padding: 8px 25px; border-radius: 30px; border: 1px solid #333; font-weight: 800; font-size: 1.3em; letter-spacing: 2px; }
.blink-dot { width: 15px; height: 15px; background: var(--neon-green); border-radius: 50%; box-shadow: 0 0 15px var(--neon-green); animation: blink 2s infinite; }
@keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

.badge { padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
.badge-allowed { color: var(--neon-green); background: rgba(57, 255, 20, 0.1); border: 1px solid rgba(57, 255, 20, 0.2); }
.badge-blocked { color: var(--danger); background: rgba(255, 65, 108, 0.1); border: 1px solid rgba(255, 65, 108, 0.2); }
.badge-ai { color: var(--warning); background: rgba(247, 151, 30, 0.1); border: 1px solid rgba(247, 151, 30, 0.2); }

.btn {
    background: #111;
    border: 1px solid #444;
    color: #fff;
    padding: 10px 20px;
    border-radius: 8px;
    cursor: pointer;
    transition: 0.3s;
    font-weight: 600;
}
.btn:hover { border-color: var(--neon-blue); color: var(--neon-blue); box-shadow: 0 0 15px rgba(0, 210, 255, 0.2); }
.btn-danger { color: var(--danger); border-color: var(--danger); }
.btn-danger:hover { background: var(--danger); color: #fff; }

.btn-action { padding: 5px 10px; font-size: 0.8em; border-radius: 5px; cursor: pointer; border: 1px solid #333; background: transparent; color: #aaa; margin-left: 5px; }
.btn-action:hover { border-color: #fff; color: #fff; }

.grid-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
.stat-value { font-size: 2.5em; font-weight: 700; margin-top: 10px; }
.stat-label { font-size: 0.8em; text-transform: uppercase; color: #666; }

.switch { position: relative; display: inline-block; width: 40px; height: 20px; vertical-align: middle; margin-left: 10px; }
.switch input { opacity: 0; width: 0; height: 0; }
.slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #333; transition: .4s; border-radius: 20px; }
.slider:before { position: absolute; content: ""; height: 14px; width: 14px; left: 3px; bottom: 3px; background-color: white; transition: .4s; border-radius: 50%; }
input:checked + .slider { background-color: var(--neon-blue); }
input:checked + .slider:before { transform: translateX(20px); }

.toggle-protection {
    background: transparent;
    border: 1px solid var(--neon-green);
    color: var(--neon-green);
    padding: 10px 25px;
    border-radius: 30px;
    cursor: pointer;
    font-weight: bold;
    transition: 0.3s;
    box-shadow: 0 0 10px rgba(57, 255, 20, 0.1);
}
.toggle-protection.prot-off {
    border-color: var(--danger);
    color: var(--danger);
    box-shadow: 0 0 10px rgba(255, 65, 108, 0.1);
    animation: pulse 2s infinite;
}
@keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.5; } }

#toast { visibility: hidden; min-width: 250px; background: #222; color: #fff; text-align: center; border-radius: 50px; padding: 15px 25px; position: fixed; z-index: 99; left: 50%; bottom: 30px; transform: translateX(-50%); border: 1px solid #444; }
#toast.show { visibility: visible; animation: fadein 0.5s, fadeout 0.5s 2.5s; }
.tab-content { display: none; }
.tab-content.active { display: block; animation: fadeIn 0.3s; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }

.filter-item { background: rgba(255,255,255,0.03); padding: 15px; border-radius: 10px; margin-bottom: 10px; display: flex; justify-content: space-between; align-items: center; }

.btn-dns { padding: 8px 15px; border-radius: 20px; border: 1px solid #444; background: transparent; color: #888; cursor: pointer; margin-right: 5px; transition: 0.3s; }
.btn-dns-on { border-color: var(--neon-green); color: var(--neon-green); box-shadow: 0 0 10px rgba(57, 255, 20, 0.2); }

.spinner { width: 18px; height: 18px; border: 2px solid #333; border-top: 2px solid var(--neon-green); border-radius: 50%; animation: spin 1s linear infinite; display: none; vertical-align: middle; margin-left: 10px; }
@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

.device-editor {
    display: flex;
    flex-direction: column;
    gap: 15px;
    margin-top: 20px;
    padding: 20px;
    background: rgba(0,0,0,0.3);
    border-radius: 10px;
    border: 1px solid #333;
}
.device-field {
    display: flex;
    align-items: center;
    gap: 10px;
}
.device-field label { width: 120px; font-weight: bold; color: #aaa; }
.device-field input { flex: 1; padding: 10px; background: #222; border: 1px solid #444; border-radius: 5px; color: #fff; }
.device-actions { display: flex; gap: 10px; margin-top: 20px; }
.device-refresh-btn { margin-top: 10px; margin-bottom: 20px; }
.device-table-actions { display: flex; gap: 5px; }
.device-table-actions button { padding: 3px 8px; font-size: 0.8em; }
EOF

    # --- web/app.js ---
cat << 'EOF' > web/app.js
let currentConfig = {};
let devicesCache = [];
let cachedLogs = [];
let nextResetTimestamp = 0;
let nextBlocklistUpdateTimestamp = 0;

window.onload = function() {
    refreshData();
    loadConfig();
    loadDevices();
    setInterval(refreshData, 1000);
    setInterval(updateCountdown, 1000);
    setInterval(updateBlocklistCountdown, 1000);
};

function toggleRGB() {
    document.body.classList.toggle('rgb-active');
}

function showTab(id) {
    document.querySelectorAll('.tab-content').forEach(e => e.classList.remove('active'));
    document.querySelectorAll('.nav-btn').forEach(e => e.classList.remove('active'));
    document.getElementById(id).classList.add('active');
    // Find and activate the clicked button
    document.querySelectorAll('.nav-btn').forEach(btn => {
        if (btn.getAttribute('onclick') && btn.getAttribute('onclick').includes("'" + id + "'")) {
            btn.classList.add('active');
        }
    });
    if (id === 'devices') {
        loadDevices();
    }
}

async function safeFetch(url, opt = {}) {
    try {
        const r = await fetch(url, opt);
        if (!r.ok) {
            if (opt.method === 'GET') throw new Error("API not available.");
            return await r.json();
        }
        return await r.json();
    } catch (e) {
        console.error(e);
        return [];
    }
}

async function loadDevices() {
    try {
        const devices = await safeFetch('/api/devices');
        if (Array.isArray(devices)) {
            devicesCache = devices;
            renderDevicesTable();
        }
    } catch (e) {
        console.error("Failed to load devices:", e);
    }
}

function renderDevicesTable() {
    const tableBody = document.getElementById('device-table-body');
    
    if (!devicesCache || devicesCache.length === 0) {
        tableBody.innerHTML = `<tr><td colspan="5" style="text-align: center; padding: 30px; color: #666;">Nincsenek felfedezett eszközök.</td></tr>`;
        return;
    }

    let html = '';
    devicesCache.forEach(device => {
        html += `
            <tr>
                <td><strong>${device.name || 'Névtelen'}</strong></td>
                <td style="white-space: nowrap;"><code style="color:var(--neon-blue)">${device.ip}</code></td>
                <td><code>${device.mac || '-'}</code></td>
                <td>${device.last_seen || '-'}</td>
                <td>
                    <div class="device-table-actions">
                        <button class="btn-action" onclick="editDevice('${device.ip}', '${device.name}')" title="Szerkesztés">✏️</button>
                        <button class="btn-action" onclick="deleteDevice('${device.ip}', '${device.name}')" title="Törlés" style="color: var(--danger);">🗑️</button>
                    </div>
                </td>
            </tr>
        `;
    });
    tableBody.innerHTML = html;
}

async function editDevice(ip, currentName) {
    const newName = prompt("Add meg az eszköz nevét (Ez felülírja az automatikus felismerést):", currentName);
    if (newName === null) return;
    if (newName.trim() === '') return;

    try {
        const response = await fetch('/api/update_device', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ip, name: newName.trim() })
        });

        if (response.ok) {
            showToast("Eszköz neve mentve!");
            const idx = devicesCache.findIndex(d => d.ip === ip);
            if (idx !== -1) {
                devicesCache[idx].name = newName.trim();
                renderDevicesTable();
            }
            await loadDevices();
        } else {
            showToast("Hiba a mentés során!");
        }
    } catch (e) { showToast("Kommunikációs hiba!"); }
}

async function deleteDevice(ip, name) {
    if (!confirm(`Törlöd ezt az eszközt: ${name} (${ip})?`)) return;
    try {
        const response = await fetch('/api/delete_device', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ip })
        });
        if (response.ok) {
            showToast("Eszköz törölve!");
            await loadDevices();
        }
    } catch (e) { showToast("Hiba!"); }
}

async function addNewDevice() {
    const ip = document.getElementById('new-device-ip').value.trim();
    const name = document.getElementById('new-device-name').value.trim();
    if (!ip || !name) { showToast("Minden mező kötelező!"); return; }

    try {
        await fetch('/api/update_device', {
            method: 'POST', headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ ip, name })
        });
        showToast("Mentve!");
        document.getElementById('new-device-ip').value = '';
        document.getElementById('new-device-name').value = '';
        await loadDevices();
    } catch (e) { showToast("Hiba!"); }
}

async function refreshDevices() {
    const spinner = document.getElementById('spinner-refresh');
    spinner.style.display = 'inline-block';
    
    try {
        await fetch('/api/refresh_devices', { method: 'POST' });
        showToast("Frissítés elindítva...");
        setTimeout(async () => {
            await loadDevices();
            spinner.style.display = 'none';
        }, 2000);
    } catch (e) {
        spinner.style.display = 'none';
    }
}

async function refreshData() {
    try {
        const s = await safeFetch('/api/stats');
        if(s.total !== undefined) {
            document.getElementById('stat-total').innerText = s.total;
            document.getElementById('stat-blocked').innerText = s.blocked;
            document.getElementById('stat-ai').innerText = s.ai_detected;
            document.getElementById('stat-db').innerText = s.database;
            nextResetTimestamp = s.next_reset;
            nextBlocklistUpdateTimestamp = s.next_blocklist_update;
        }
        const l = await safeFetch('/api/logs');
        cachedLogs = l;
        renderLogs();
    } catch (e) {}
}

function renderLogs() {
    const b = document.getElementById('log-body');
    const s = document.getElementById('log-search').value.toLowerCase();
    b.innerHTML = '';
    
    if (!cachedLogs || cachedLogs.length === 0) return;

    cachedLogs.forEach(l => {
        if (s && !l.domain.toLowerCase().includes(s) && !l.client_ip.includes(s)) return;
        const tr = document.createElement('tr');
        let bc = 'badge-allowed', btn = '';

        let clientDisplay = l.client_ip;
        const knownDevice = devicesCache.find(d => d.ip === l.client_ip);
        if (knownDevice && knownDevice.name && !knownDevice.name.startsWith("Device_")) {
            clientDisplay = `<span title="${l.client_ip}" style="color:var(--neon-blue); border-bottom:1px dotted #666; cursor:help;">${knownDevice.name}</span>`;
        }

        if (l.status.startsWith('Blocked')) {
            bc = 'badge-blocked';
            btn = `<button class="btn-action" style="color:var(--neon-green);border-color:var(--neon-green)" onclick="quickAllow('${l.domain}')">Enged</button>`;
        } else {
            if (l.status.includes('AI')) bc = 'badge-ai';
            btn = `<button class="btn-action" style="color:var(--danger);border-color:var(--danger)" onclick="quickBlock('${l.domain}')">Tilt</button>`;
        }

        tr.innerHTML = `
            <td>${l.time}</td>
            <td style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${l.domain}</td>
            <td><span class="badge" style="background:#222;color:#888; border:1px solid #333">${l.type || '-'}</span></td>
            <td>${clientDisplay}</td>
            <td><span class="badge ${bc}">${l.status}</span></td>
            <td style="text-align: right; white-space: nowrap;">${btn}</td>
        `;
        b.appendChild(tr);
    });
}

async function loadConfig() {
    try {
        currentConfig = await safeFetch('/api/config');
        document.getElementById('txt-whitelist').value = (currentConfig.whitelist || []).join('\n');
        document.getElementById('txt-blacklist').value = (currentConfig.blacklist || []).join('\n');
        
        // Blocklist domain számok betöltése
        await fetchBlocklistCounts();
        
        document.getElementById('txt-upstream').value = (currentConfig.upstreams || []).join('\n');
        updateDNSButtons();
        document.getElementById('sel-mode').value = currentConfig.response_mode || 'zero';
        document.getElementById('chk-ai').checked = currentConfig.ai_detection;
        document.getElementById('chk-ai-aggro').checked = currentConfig.agressive_ai_blocking;
        updateAIText(); updateAIAggroText(); updateMainToggle();
    } catch(e) {}
}

async function postConfig(c, m) {
    try {
        const response = await fetch('/api/config', { 
            method: 'POST', 
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(c) 
        });
        if (!response.ok) {
            throw new Error('Server error: ' + response.status);
        }
        const result = await response.json();
        console.log('Config saved:', result);
        if (m) showToast(m);
        // Várunk egy kicsit, hogy a szerver feldolgozza
        setTimeout(() => loadConfig(), 500);
    } catch (e) { 
        console.error('postConfig error:', e);
        showToast("Hiba a mentésnél: " + e.message); 
    }
}

function updateCountdown() {
    if (!nextResetTimestamp) return;
    const now = Math.floor(Date.now() / 1000);
    let diff = nextResetTimestamp - now;
    if (diff < 0) diff = 0;
    const h = Math.floor(diff / 3600), m = Math.floor((diff % 3600) / 60), s = diff % 60;
    document.getElementById('reset-timer').innerText = `${h}:${m}:${s}`;
}

function updateBlocklistCountdown() {
     if (!nextBlocklistUpdateTimestamp) return;
     let diff = nextBlocklistUpdateTimestamp - Math.floor(Date.now() / 1000);
     if (diff < 0) diff = 0;
     const days = Math.floor(diff / 86400);
     const hours = Math.floor((diff % 86400) / 3600);
     document.getElementById('blocklist-timer').innerText = `${days} nap ${hours} óra`;
}

function showToast(m) {
    const x = document.getElementById("toast");
    x.innerText = m; x.className = "show";
    setTimeout(() => x.className = x.className.replace("show", ""), 3000);
}

function toggleProtection() {
    currentConfig.blocking_enabled = !currentConfig.blocking_enabled;
    postConfig(currentConfig, currentConfig.blocking_enabled ? "Védelem BE" : "Védelem SZÜNET");
}

function updateMainToggle() {
    const btn = document.getElementById('main-toggle');
    if (currentConfig.blocking_enabled) { btn.className = 'toggle-protection prot-on'; btn.innerText = 'VÉDELEM: AKTÍV'; }
    else { btn.className = 'toggle-protection prot-off'; btn.innerText = 'VÉDELEM: SZÜNETEL'; }
}

async function restartService() {
    if (!confirm('Biztosan újraindítod a FrankDNS+ szolgáltatást?\\n\\nEz pár másodpercig tarthat és a DNS átmenetileg nem lesz elérhető.')) return;
    
    const btn = document.getElementById('restart-btn');
    btn.disabled = true;
    btn.innerHTML = '⏳ Újraindítás...';
    btn.style.opacity = '0.5';
    
    showToast("FrankDNS+ újraindítása...");
    
    try {
        await fetch('/api/restart', {method:'POST'});
        showToast("✅ FrankDNS+ újraindítva!");
        setTimeout(() => location.reload(), 2000);
    } catch(e) {
        showToast("⚠️ Újraindítás folyamatban, oldal újratöltése...");
        setTimeout(() => location.reload(), 3000);
    }
}

function saveSettings() {
    currentConfig.upstreams = document.getElementById('txt-upstream').value.split('\n').filter(s => s.trim());
    currentConfig.response_mode = document.getElementById('sel-mode').value;
    currentConfig.ai_detection = document.getElementById('chk-ai').checked;
    currentConfig.agressive_ai_blocking = document.getElementById('chk-ai-aggro').checked;
    postConfig(currentConfig, "Mentve!");
}

function manualReset() { fetch('/api/reset_stats', {method:'POST'}).then(()=>refreshData()); }

async function manualBlocklistUpdate() { 
    const btn = document.getElementById('update-button');
    const spinner = document.getElementById('spinner-loading');
    const text = document.getElementById('update-text');
    
    // Disable button and show spinner
    btn.disabled = true;
    spinner.style.display = 'inline-block';
    text.innerText = 'Frissítés folyamatban...';
    
    showToast("Szűrőlisták frissítése... Ez eltarthat pár percig!");
    
    try {
        const response = await fetch('/api/update_blocklists', {method:'POST'});
        const data = await response.json();
        
        if (data.status === 'ok') {
            showToast(`✅ Frissítés kész! Adatbázis: ${data.database} domain`);
            // Refresh stats immediately
            await refreshData();
            // Update blocklist counts
            await fetchBlocklistCounts();
        } else {
            showToast("❌ Hiba a frissítés során!");
        }
    } catch (e) {
        showToast("❌ Kommunikációs hiba!");
    } finally {
        // Re-enable button
        btn.disabled = false;
        spinner.style.display = 'none';
        text.innerText = '🔄 Frissítés Indítása';
    }
}

// Blocklist domain számlálók tárolása
let blocklistCounts = {};

// Összes lista bekapcsolása
function enableAllBlocklists() {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists.forEach((l, i) => {
        currentConfig.blocklists[i].enabled = true;
    });
    renderBlocklistEditor();
    updateBlocklistSummary();
    showToast("✅ Összes lista bekapcsolva! Ne felejtsd el menteni!");
}

// Összes lista kikapcsolása
function disableAllBlocklists() {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists.forEach((l, i) => {
        currentConfig.blocklists[i].enabled = false;
    });
    renderBlocklistEditor();
    updateBlocklistSummary();
    showToast("❌ Összes lista kikapcsolva! Ne felejtsd el menteni!");
}

// Összesítő frissítése
function updateBlocklistSummary() {
    if (!currentConfig.blocklists) return;
    
    let activeCount = 0;
    let inactiveCount = 0;
    let totalDomains = 0;
    
    currentConfig.blocklists.forEach(l => {
        if (l.enabled) {
            activeCount++;
            // Ha van tárolt domain szám ehhez a listához
            const count = blocklistCounts[l.url] || 0;
            totalDomains += count;
        } else {
            inactiveCount++;
        }
    });
    
    document.getElementById('summary-active').innerText = activeCount;
    document.getElementById('summary-inactive').innerText = inactiveCount;
    document.getElementById('summary-total').innerText = totalDomains.toLocaleString('hu-HU');
    document.getElementById('total-domains-count').innerText = totalDomains.toLocaleString('hu-HU');
}

// Domain számok lekérése a szerverről
async function fetchBlocklistCounts() {
    try {
        const response = await fetch('/api/blocklist_counts');
        if (response.ok) {
            const data = await response.json();
            blocklistCounts = data.counts || {};
            renderBlocklistEditor();
            updateBlocklistSummary();
        }
    } catch (e) {
        console.log("Blocklist counts not available yet");
    }
}

function renderBlocklistEditor() {
    const c = document.getElementById('blocklist-editor');
    c.innerHTML = '';
    const lists = currentConfig.blocklists || [];
    
    lists.forEach((l, i) => {
        const d = document.createElement('div');
        d.className = 'filter-item';
        
        // Domain szám lekérése (ha van)
        const domainCount = blocklistCounts[l.url] || 0;
        const countDisplay = domainCount > 0 
            ? `<span style="color:var(--neon-green); font-weight:bold;">${domainCount.toLocaleString('hu-HU')}</span>` 
            : `<span style="color:#666;">---</span>`;
        
        const statusColor = l.enabled ? 'var(--neon-green)' : 'var(--danger)';
        const statusIcon = l.enabled ? '🟢' : '🔴';
        
        d.innerHTML = `
            <div style="flex-grow: 1; margin-right: 15px;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:5px;">
                    <input type="text" style="flex:1; padding:8px; background:#222; border:1px solid #333; color:#fff; font-weight:bold;" 
                           value="${l.name}" onchange="updateBlocklistName(${i}, this.value)">
                    <div style="margin-left:15px; padding:5px 12px; background:rgba(0,0,0,0.5); border-radius:20px; font-size:0.85em;">
                        📊 ${countDisplay} domain
                    </div>
                </div>
                <input type="text" style="width:100%; padding:8px; background:#111; border:1px solid #222; color:#888; font-size:0.85em;" 
                       value="${l.url}" onchange="updateBlocklistURL(${i}, this.value)">
            </div>
            <div style="display:flex; align-items:center; gap:10px;">
                <span style="font-size:1.2em;">${statusIcon}</span>
                <label class="switch">
                    <input type="checkbox" ${l.enabled ? 'checked' : ''} onchange="updateBlocklistStatus(${i},this.checked); updateBlocklistSummary();">
                    <span class="slider"></span>
                </label>
                <button class="btn-action" onclick="removeBlocklist(${i})" style="color:var(--danger);">🗑️</button>
            </div>
        `;
        c.appendChild(d);
    });
    
    updateBlocklistSummary();
}

function updateBlocklistName(i, name) {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists[i].name = name;
}

function updateBlocklistURL(i, url) {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists[i].url = url;
}

function updateBlocklistStatus(i, e) {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists[i].enabled = e;
}

function removeBlocklist(i) {
    if (!currentConfig.blocklists || !confirm("Törlöd ezt a szűrőlistát?")) return;
    currentConfig.blocklists.splice(i, 1);
    renderBlocklistEditor();
}

function addNewBlocklist() {
    const name = prompt("Lista neve:", "Új lista");
    if (!name) return;
    const url = prompt("Lista URL-je:", "https://");
    if (!url) return;
    if (!currentConfig.blocklists) currentConfig.blocklists = [];
    currentConfig.blocklists.push({ name, url, enabled: true });
    renderBlocklistEditor();
}

function saveBlocklists() {
    postConfig(currentConfig, "Szűrőlisták mentve!");
}

async function saveLists() { 
    console.log('saveLists called');
    const whitelistValue = document.getElementById('txt-whitelist').value;
    const blacklistValue = document.getElementById('txt-blacklist').value;
    
    console.log('Whitelist textarea value:', whitelistValue);
    console.log('Blacklist textarea value:', blacklistValue);
    
    currentConfig.whitelist = whitelistValue.split('\n').filter(s=>s.trim());
    currentConfig.blacklist = blacklistValue.split('\n').filter(s=>s.trim());
    
    console.log('Whitelist array:', currentConfig.whitelist);
    console.log('Blacklist array:', currentConfig.blacklist);
    console.log('Full config to save:', JSON.stringify(currentConfig, null, 2));
    
    await postConfig(currentConfig, "Kivételek mentve!"); 
}

const dnsProviders = {'Cloudflare DoT': ['tls://1.1.1.1', 'tls://1.0.0.1'], 'Google DoT': ['tls://8.8.8.8', 'tls://8.8.4.4'], 'Quad9 DoT': ['tls://9.9.9.9', 'tls://149.112.112.112']};

function toggleDNS(p) {
    const ips = dnsProviders[p];
    let c = document.getElementById('txt-upstream').value.split('\n').map(s => s.trim()).filter(s => s);
    const allPresent = ips.every(ip => c.includes(ip));
    
    if (allPresent) {
        c = c.filter(ip => !ips.includes(ip));
    } else {
        c = [...c, ...ips];
    }
    c = [...new Set(c)];
    document.getElementById('txt-upstream').value = c.join('\n');
    updateDNSButtons();
}

function updateDNSButtons() {
    const val = document.getElementById('txt-upstream').value;
    const c = val.split('\n').map(s => s.trim());
    for (const [key, ips] of Object.entries(dnsProviders)) {
        let btnId = '';
        if(key.includes('Cloudflare')) btnId = 'btn-cloudflare-dot';
        else if(key.includes('Quad9')) btnId = 'btn-quad9-dot';
        else if(key.includes('Google')) btnId = 'btn-google-dot';
        
        const btn = document.getElementById(btnId);
        if(btn) {
            if (ips.every(ip => c.includes(ip))) {
                btn.classList.add('btn-dns-on');
            } else {
                btn.classList.remove('btn-dns-on');
            }
        }
    }
}

function updateAIText() { document.getElementById('ai-status-text').innerText = document.getElementById('chk-ai').checked ? "(BE)" : "(KI)"; }
function updateAIAggroText() { document.getElementById('ai-aggro-text').innerText = document.getElementById('chk-ai-aggro').checked ? "(AKTÍV)" : "(KI)"; }

function quickBlock(d) {
    if(!currentConfig.blacklist) currentConfig.blacklist=[];
    currentConfig.blacklist.push(d); postConfig(currentConfig, "Blokkolva!");
}
function quickAllow(d) {
    if(!currentConfig.whitelist) currentConfig.whitelist=[];
    currentConfig.whitelist.push(d); postConfig(currentConfig, "Engedélyezve!");
}
EOF

    print_block "5. LÉPÉS: Fordítás és Szolgáltatás"

    if [ ! -f "go.mod" ]; then
        go mod init frankdnsplus
        go get github.com/miekg/dns
    fi
    
    echo "🔨 Modulok letöltése..."
    go mod tidy

    echo "🔨 Fordítás (Modular Build)..."
    go build -ldflags="-s -w" -o main cmd/frankdns/main.go
    chmod +x main

    echo "⚙️  Service létrehozása..."
cat << 'EOF' > /etc/systemd/system/frankdnsplus.service
[Unit]
Description=FrankDNS+ 2026 Modular DNS Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/robot_36/frankdnsplus
ExecStart=/home/robot_36/frankdnsplus/main
Restart=always
RestartSec=5
LimitNOFILE=65535
Environment="GODEBUG=madvdontneed=1"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frankdnsplus
    systemctl start frankdnsplus

    echo "🛠️  Vezérlő script (frank) telepítése..."
cat << 'EOF' > /usr/local/bin/frank
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}    ${GREEN}FrankDNS+ 2026 Vezérlőpult v3.2${NC}    ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "1. 📊 Státusz"
echo "2. 📜 Logok (Utolsó 20 sor)"
echo "3. 🔄 Újraindítás"
echo "4. 📱 Eszközkezelő Log"
echo "5. 🗑️  Cache törlés"
echo "6. 📋 Blocklist frissítés log"
echo "7. 🚪 Kilépés"
echo ""
read -p "Válassz (1-7): " opt
case $opt in
    1) systemctl status frankdnsplus --no-pager ;;
    2) journalctl -u frankdnsplus -n 20 --no-pager ;;
    3) systemctl restart frankdnsplus; echo -e "${GREEN}✅ Újraindítva!${NC}" ;;
    4) journalctl -u frankdnsplus --no-pager | grep -i "device" | tail -20 ;;
    5) curl -s -X POST http://localhost:8000/api/clear_cache; echo -e "${GREEN}✅ Cache törölve!${NC}" ;;
    6) journalctl -u frankdnsplus --no-pager | grep -i "blocklist" | tail -30 ;;
    *) ;;
esac
EOF
    chmod +x /usr/local/bin/frank

    IP_CIM=$(hostname -I | awk '{print $1}')
    print_block "TELEPÍTÉS KÉSZ! ✅"
    echo -e "Webes felület: ${GREEN}http://$IP_CIM:8000${NC}"
    echo ""
    echo -e "${YELLOW}FRANKDNS+ v3.2.0 - MODULÁRIS ARCHITEKTÚRA:${NC}"
    echo -e "  ✓ cmd/frankdns/main.go (Orchestrator)"
    echo -e "  ✓ internal/ (Config, Cache, Blocklist, WebAPI, DNS motor)"
    echo -e "  ✓ web/ (HTML, CSS, JS - Neon dashboard)"
    echo ""
    echo -e "${GREEN}ÚJ FUNKCIÓK v3.2.0:${NC}"
    echo -e "  ✓ TLS biztonság javítva"
    echo -e "  ✓ Real-time adatbázis statisztika"
    echo -e "  ✓ Cache automatikus törlés frissítéskor"
    echo -e "  ✓ Részletes blocklist loggolás"
    echo ""
    read -p "Nyomj Entert a menübe való visszatéréshez..."
    show_main_menu
}

show_main_menu