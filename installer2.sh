#!/bin/bash

# ==============================================================================
#  FRANKDNS+ 2026 - MODULAR SYSTEM INSTALLER (v3.0.0)
#  ARCHITEKTÚRA: Modular Go (cmd/internal layout)
#  MÓDOSÍTÁS DÁTUMA: 2025-12-10
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
    echo -e "${BLUE}#${NC}       ${BOLD}FRANKDNS+ 2026 - MODULAR SYSTEM v3.0${NC}       ${BLUE}#${NC}"
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
    echo -e "  ${YELLOW}4)${NC} 🚪 Kilépés"
    echo ""
    read -p "Mit szeretnél tenni? (1-4): " choice

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
        4) echo -e "\nViszlát!"; exit 0 ;;
        *) show_main_menu ;;
    esac
}

run_installer() {
    print_block() {
        echo -e "\n${BLUE}############################################################${NC}"
        echo -e "${BLUE}#${NC} ${YELLOW}${BOLD}$1${NC}"
        echo -e "${BLUE}############################################################${NC}"
        sleep 1
    }

    print_block "1. LÉPÉS: TAKARÍTÁS ÉS ELŐKÉSZÍTÉS"

    echo "🛑 Régi szolgáltatások leállítása..."
    systemctl stop frankdnsplus 2>/dev/null
    systemctl disable frankdnsplus 2>/dev/null
    
    echo "🔓 Portok felszabadítása..."
    fuser -k 8080/tcp 2>/dev/null
    fuser -k 53/tcp 2>/dev/null
    fuser -k 53/udp 2>/dev/null

    echo "🗑️ Régi fájlok archiválása..."
    # Config mentése
    if [ -f "/opt/frankdnsplus/config.json" ]; then
        cp /opt/frankdnsplus/config.json /tmp/frank_config_backup.json
        echo "💾 Konfiguráció mentve..."
    fi

    rm -rf /opt/frankdnsplus
    
    if lsof -i :53 | grep -q systemd-r; then
        echo "⚠️  systemd-resolved leállítása..."
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved 2>/dev/null
    fi

    echo "🌐 DNS ideiglenes beállítása..."
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    INSTALL_DIR="/opt/frankdnsplus"
    mkdir -p $INSTALL_DIR
    mkdir -p $INSTALL_DIR/cmd/frankdns
    mkdir -p $INSTALL_DIR/internal/config
    mkdir -p $INSTALL_DIR/internal/cache
    mkdir -p $INSTALL_DIR/internal/blocklist
    mkdir -p $INSTALL_DIR/internal/dnsserver
    mkdir -p $INSTALL_DIR/internal/webapi
    mkdir -p $INSTALL_DIR/web

    # Config visszaállítása
    if [ -f "/tmp/frank_config_backup.json" ]; then
        cp /tmp/frank_config_backup.json $INSTALL_DIR/config.json
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
    
    # Próbáljuk letölteni a legfrissebbet
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

    cd $INSTALL_DIR

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
	Path     = "/opt/frankdnsplus/config.json"
)

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
		ListenHTTP:          ":8080",
		Upstreams:           []string{"tls://1.1.1.1", "tls://1.0.0.1"},
		ResponseMode:        "zero",
		LogBufferSize:       100,
		AIDetection:         true,
		BlockingEnabled:     true,
		AgressiveAIBlocking: false,
		Devices:             []Device{},
		Whitelist:           []string{},
		Blacklist:           []string{},
		Blocklists: []BlocklistConfig{
			{"AdGuard DNS Filter", "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt", true},
			{"AdGuard Mobile Ads", "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt", true},
		},
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
	key := fmt.Sprintf("%s:%d", question.Name, question.Qtype)

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

	// Calculate TTL based on the shortest TTL in the answer section
	minTTL := uint32(3600)
	for _, rr := range msg.Answer {
		if rr.Header().Ttl < minTTL {
			minTTL = rr.Header().Ttl
		}
	}

	if minTTL == 0 {
		return
	}

	key := fmt.Sprintf("%s:%d", question.Name, question.Qtype)

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
	Mutex         sync.RWMutex
	StatsDatabase uint64
}

// Global instance
var Global = &Manager{
	BlockMap:     make(map[string]struct{}),
	WhitelistMap: make(map[string]struct{}),
	BlacklistMap: make(map[string]struct{}),
}

// Update downloads and parses all enabled blocklists
func (m *Manager) Update() {
	newBlockMap := make(map[string]struct{})

	config.Mutex.RLock()
	lists := config.Instance.Blocklists
	config.Mutex.RUnlock()

	client := http.Client{Timeout: 15 * time.Second}

	for _, list := range lists {
		if !list.Enabled {
			continue
		}

		resp, err := client.Get(list.URL)
		if err != nil {
			continue
		}

		scanner := bufio.NewScanner(resp.Body)
		// Increase buffer size for long lines
		buf := make([]byte, 0, 64*1024)
		scanner.Buffer(buf, 1024*1024)

		for scanner.Scan() {
			domain := parseLine(scanner.Text())
			if domain != "" {
				newBlockMap[domain] = struct{}{}
			}
		}
		resp.Body.Close()
	}

	// Rebuild local whitelist/blacklist maps from config
	newWhitelist := make(map[string]struct{})
	newBlacklist := make(map[string]struct{})

	// Default mandatory whitelist
	defaults := []string{
		"facebook.com", "facebook.net", "fbcdn.net", "fbsbx.com",
		"tiktokcdn.com", "ttacdn.com", "googlevideo.com", "youtube-nocookie.com",
		"asuscomm.com", "tplinkcloud.com", "amazon.com", "openai.com",
		"instagram.com", "whatsapp.com",
	}
	for _, d := range defaults {
		newWhitelist[strings.ToLower(d)] = struct{}{}
	}

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

	m.Mutex.Lock()
	m.BlockMap = newBlockMap
	m.WhitelistMap = newWhitelist
	m.BlacklistMap = newBlacklist
	m.Mutex.Unlock()

	atomic.StoreUint64(&m.StatsDatabase, uint64(len(newBlockMap)))
}

// StartUpdateLoop runs the update periodically
func StartUpdateLoop() {
	// Initial update
	Global.Update()

	ticker := time.NewTicker(48 * time.Hour)
	for range ticker.C {
		Global.Update()
	}
}

// parseLine handles various blocklist formats (AdBlock, Hosts, Dnsmasq)
func parseLine(line string) string {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "!") {
		return ""
	}

	// Remove inline comments
	if idx := strings.Index(line, "#"); idx != -1 {
		line = strings.TrimSpace(line[:idx])
	}

	// AdBlock style: ||domain.com^
	if strings.HasPrefix(line, "||") {
		line = strings.TrimPrefix(line, "||")
		if idx := strings.IndexAny(line, "^/"); idx != -1 {
			line = line[:idx]
		}
		return cleanDomain(line)
	}

	// Dnsmasq style: address=/domain.com/
	if strings.HasPrefix(line, "address=/") {
		parts := strings.Split(line, "/")
		if len(parts) >= 2 {
			return cleanDomain(parts[1])
		}
	}

	// Hosts file style: 0.0.0.0 domain.com
	fields := strings.Fields(line)
	if len(fields) >= 2 {
		ip := fields[0]
		if ip == "0.0.0.0" || ip == "127.0.0.1" || ip == "::1" {
			domain := fields[1]
			if domain == "localhost" || domain == "localhost.localdomain" || domain == "local" {
				return ""
			}
			return cleanDomain(domain)
		}
	}

	// Just a domain name?
	if len(fields) == 1 && net.ParseIP(fields[0]) == nil {
		return cleanDomain(fields[0])
	}

	return ""
}

func cleanDomain(d string) string {
	d = strings.ToLower(d)
	d = strings.TrimSuffix(d, ".")
	// Basic sanity checks
	if len(d) < 3 || strings.Contains(d, "/") {
		return ""
	}
	return d
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

	// Check Cache
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

	// AI Detection logic
	isAiDetected := false
	if aiEnabled {
		for _, kw := range aiKeywords {
			if strings.Contains(name, kw) {
				isAiDetected = true
				break
			}
		}
	}

	// Check Local Lists
	blocklist.Global.Mutex.RLock()
	_, whitelisted := blocklist.Global.WhitelistMap[name]
	if !whitelisted {
		// Check for suffix match in whitelist
		for domain := range blocklist.Global.WhitelistMap {
			if strings.HasSuffix(name, "."+domain) {
				whitelisted = true
				break
			}
		}
	}
	_, blacklisted := blocklist.Global.BlacklistMap[name]
	_, blocked := blocklist.Global.BlockMap[name]
	blocklist.Global.Mutex.RUnlock()

	if whitelisted {
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

	if blacklisted || blocked {
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

	// Simple load balancing
	target := upstreams[time.Now().UnixNano()%int64(len(upstreams))]
	resp := new(dns.Msg)
	var err error

	// Reorder to try target first
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
			if !strings.Contains(uTarget, ":") {
				uTarget += ":853"
			}
			c := new(dns.Client)
			c.Net = "tcp-tls"
			c.TLSConfig = &tls.Config{InsecureSkipVerify: true}
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
		m := new(dns.Msg)
		m.SetRcode(r, dns.RcodeServerFailure)
		w.WriteMsg(m)
		AddLog(name, qType, clientIP, "Error")
		return
	}

	// Cache successful response
	if len(resp.Answer) > 0 {
		cache.Global.Set(r.Question[0], resp)
	}

	// CNAME Cloaking Protection
	if blockingOn {
		blocklist.Global.Mutex.RLock()
		for _, rr := range resp.Answer {
			if cname, ok := rr.(*dns.CNAME); ok {
				target := strings.ToLower(strings.TrimSuffix(cname.Target, "."))
				// Check Whitelist
				_, whitelisted := blocklist.Global.WhitelistMap[target]
				if !whitelisted {
					for domain := range blocklist.Global.WhitelistMap {
						if strings.HasSuffix(target, "."+domain) {
							whitelisted = true
							break
						}
					}
				}

				if !whitelisted {
					_, blacklisted := blocklist.Global.BlacklistMap[target]
					_, blocked := blocklist.Global.BlockMap[target]
					if blacklisted || blocked {
						blocklist.Global.Mutex.RUnlock()
						atomic.AddUint64(&CurrentStats.Blocked, 1)
						AddLog(name, qType, clientIP, "Blocked (CNAME)")
						blockDNS(w, r)
						return
					}
				}

				if aiEnabled && agressiveAI {
					for _, kw := range aiKeywords {
						if strings.Contains(target, kw) {
							blocklist.Global.Mutex.RUnlock()
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
		blocklist.Global.Mutex.RUnlock()
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

// AddLog appends a new entry to the in-memory log
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

// ResetStats zeroes out counters
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
	"frankdnsplus/internal/config"
	"frankdnsplus/internal/dnsserver"
	"log"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// Start initializes the HTTP server
func Start() {
	config.Mutex.RLock()
	addr := config.Instance.ListenHTTP
	config.Mutex.RUnlock()

	http.Handle("/", http.FileServer(http.Dir("/opt/frankdnsplus/web")))
	http.HandleFunc("/api/stats", apiStats)
	http.HandleFunc("/api/logs", apiLogs)
	http.HandleFunc("/api/config", apiConfig)
	http.HandleFunc("/api/reset_stats", apiResetStats)
	http.HandleFunc("/api/update_blocklists", apiUpdateBlocklists)
	http.HandleFunc("/api/devices", apiDevices)
	http.HandleFunc("/api/update_device", apiUpdateDevice)
	http.HandleFunc("/api/delete_device", apiDeleteDevice)
	http.HandleFunc("/api/refresh_devices", apiRefreshDevices)

	log.Printf("Starting Web API on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Web Server error: %v", err)
	}
}

func apiStats(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	dnsserver.CurrentStats.NextReset = dnsserver.NextResetTime.Unix()
	json.NewEncoder(w).Encode(dnsserver.CurrentStats)
}

func apiLogs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	dnsserver.LogsMutex.Lock()
	defer dnsserver.LogsMutex.Unlock()

	// Reverse logs for display (newest first)
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
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		config.Mutex.Lock()
		*config.Instance = newConfig
		config.Mutex.Unlock()
		config.Save()
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

func apiUpdateBlocklists(w http.ResponseWriter, r *http.Request) {
	if r.Method == "POST" {
		go blocklist.Global.Update()
		w.Write([]byte(`{"status":"ok", "message":"Update started"}`))
		return
	}
	w.WriteHeader(http.StatusMethodNotAllowed)
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

// Device Discovery Logic
func discoverDevices() {
	newDevices := make([]config.Device, 0)
	seenIPs := make(map[string]bool)

	// ARP Scan
	foundDevices := scanARP()

	// Add from logs (active clients)
	dnsserver.LogsMutex.Lock()
	for _, l := range dnsserver.RecentLogs {
		if l.ClientIP != "" && l.ClientIP != "127.0.0.1" {
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
		if seenIPs[d.IP] || d.IP == "127.0.0.1" || d.IP == "" {
			continue
		}
		seenIPs[d.IP] = true

		finalName := ""
		finalMAC := d.MAC

		if saved, exists := savedMap[d.IP]; exists {
			if saved.Name != "" && !strings.HasPrefix(saved.Name, "Device_") {
				finalName = saved.Name
			}
			if finalMAC == "" || finalMAC == "Unknown" {
				finalMAC = saved.MAC
			}
		}

		// Reverse DNS Lookup if no name
		if finalName == "" {
			ptrNames, err := net.LookupAddr(d.IP)
			if err == nil && len(ptrNames) > 0 {
				candidates := []string{}
				for _, n := range ptrNames {
					n = strings.TrimSuffix(n, ".")
					if !strings.Contains(n, "in-addr.arpa") {
						candidates = append(candidates, n)
					}
				}
				if len(candidates) > 0 {
					finalName = candidates[0]
				}
			}
			if finalName == "" {
				if finalMAC != "" {
					finalName = "Device_" + strings.ReplaceAll(finalMAC, ":", "")[6:]
				} else {
					finalName = "Device_" + strings.ReplaceAll(d.IP, ".", "_")
				}
			}
		}

		newDevices = append(newDevices, config.Device{
			Name:     finalName,
			IP:       d.IP,
			MAC:      finalMAC,
			LastSeen: time.Now().Format("2006-01-02 15:04:05"),
		})
	}

	// Keep old devices that weren't found this scan
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
	cmd := exec.Command("arp", "-a")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			parts := strings.Fields(line)
			if len(parts) >= 4 {
				ip := strings.Trim(parts[1], "()")
				mac := parts[3]
				if net.ParseIP(ip) != nil {
					devices = append(devices, config.Device{IP: ip, MAC: mac})
				}
			}
		}
	}
	return devices
}

// StartDiscoveryLoop runs discovery periodically
func StartDiscoveryLoop() {
	discoverDevices() // Initial run
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

	// 1. Load Configuration
	config.Load()
	log.Println("Configuration loaded.")

	// 2. Start Background Routines
	go cache.StartCleanupRoutine()
	go blocklist.StartUpdateLoop()
	go webapi.StartDiscoveryLoop()

	// 3. Initialize Stats Auto-Reset
	dnsserver.NextResetTime = time.Now().Add(24 * time.Hour)
	go func() {
		for {
			time.Sleep(time.Until(dnsserver.NextResetTime))
			dnsserver.ResetStats()
			dnsserver.NextResetTime = time.Now().Add(24 * time.Hour)
		}
	}()

	// 4. Start Servers
	go webapi.Start()
	go dnsserver.Start("udp")
	go dnsserver.Start("tcp")

	log.Println("FrankDNS+ is fully operational.")

	// 5. Wait for Shutdown Signal
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
            <button id="rgb-toggle" class="btn" onclick="toggleRGB()" style="margin-right: 15px; border: 1px solid rgba(255,255,255,0.3);">🌈 RGB</button>
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
            
            <button id="update-button" class="btn" style="width:100%; margin-bottom:20px; border-color:var(--neon-green); color:var(--neon-green);" onclick="manualBlocklistUpdate()">
                <span id="update-text">Frissítés Indítása</span>
                <span id="update-status-container"><div id="spinner-loading" class="spinner"></div></span>
            </button>
            
            <div id="blocklist-editor"></div>
            <button class="btn" style="width:100%; margin-top:15px; border-style:dashed; color:#666;" onclick="addNewBlocklist()">+ Lista hozzáadása</button>
            <button class="btn" style="width:100%; margin-top:10px;" onclick="saveBlocklists()">Mentés</button>
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

/* DEVICE MANAGER STYLES */
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
    event.target.classList.add('active');
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
    const button = document.querySelector('#devices .btn');
    const spinner = document.getElementById('spinner-refresh');
    button.disabled = true; spinner.style.display = 'inline-block';
    
    try {
        await fetch('/api/refresh_devices', { method: 'POST' });
        showToast("Frissítés elindítva...");
        setTimeout(async () => {
            await loadDevices();
            button.disabled = false; spinner.style.display = 'none';
        }, 2000);
    } catch (e) {
        button.disabled = false; spinner.style.display = 'none';
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
        renderBlocklistEditor();
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
        await fetch('/api/config', { method: 'POST', body: JSON.stringify(c) });
        if (m) showToast(m);
        loadConfig();
    } catch (e) { showToast("Hiba!"); }
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
     document.getElementById('blocklist-timer').innerText = Math.floor(diff / 86400) + " nap";
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

function saveSettings() {
    currentConfig.upstreams = document.getElementById('txt-upstream').value.split('\n').filter(s => s.trim());
    currentConfig.response_mode = document.getElementById('sel-mode').value;
    currentConfig.ai_detection = document.getElementById('chk-ai').checked;
    currentConfig.agressive_ai_blocking = document.getElementById('chk-ai-aggro').checked;
    postConfig(currentConfig, "Mentve!");
}

function manualReset() { fetch('/api/reset_stats', {method:'POST'}).then(()=>refreshData()); }
function manualBlocklistUpdate() { fetch('/api/update_blocklists', {method:'POST'}); showToast("Frissítés indítva..."); }

function renderBlocklistEditor() {
    const c = document.getElementById('blocklist-editor');
    c.innerHTML = '';
    const lists = currentConfig.blocklists || [];
    lists.forEach((l, i) => {
        const d = document.createElement('div');
        d.className = 'filter-item';
        d.innerHTML = `
            <div style="flex-grow: 1; margin-right: 15px;">
                <strong style="color: #fff; display: block;">${l.name}</strong>
                <span style="font-size: 0.8em; color: #666; display: block; word-break: break-all;">${l.url}</span>
            </div>
            <label class="switch">
                <input type="checkbox" ${l.enabled ? 'checked' : ''} onchange="updateBlocklistStatus(${i},this.checked)">
                <span class="slider"></span>
            </label>
        `;
        c.appendChild(d);
    });
}

function updateBlocklistStatus(i, e) {
    if (!currentConfig.blocklists) return;
    currentConfig.blocklists[i].enabled = e;
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

function saveLists() { 
    currentConfig.whitelist = document.getElementById('txt-whitelist').value.split('\n').filter(s=>s.trim());
    currentConfig.blacklist = document.getElementById('txt-blacklist').value.split('\n').filter(s=>s.trim());
    postConfig(currentConfig, "Kivételek mentve!"); 
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

    # Go mod init if missing (unlikely due to generation above but safe)
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
WorkingDirectory=/opt/frankdnsplus
ExecStart=/opt/frankdnsplus/main
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
NC='\033[0m'

echo -e "${BLUE}FrankDNS+ Vezérlő${NC}"
echo "1. Státusz"
echo "2. Logok (Utolsó 20 sor)"
echo "3. Újraindítás"
echo "4. Eszközkezelő Log"
echo "5. Kilépés"
read -p "Válassz: " opt
case $opt in
    1) systemctl status frankdnsplus ;;
    2) journalctl -u frankdnsplus -n 20 -f ;;
    3) systemctl restart frankdnsplus; echo "Újraindítva!" ;;
    4) journalctl -u frankdnsplus | grep -i "device" | tail -20 ;;
    *) ;;
esac
EOF
    chmod +x /usr/local/bin/frank

    IP_CIM=$(hostname -I | awk '{print $1}')
    print_block "TELEPÍTÉS KÉSZ! ✅"
    echo -e "Webes felület: ${GREEN}http://$IP_CIM:8080${NC}"
    echo ""
    echo -e "${YELLOW}MODULÁRIS ARCHITEKTÚRA (v3.0):${NC}"
    echo -e "  ✓ cmd/frankdns/main.go (Orchestrator)"
    echo -e "  ✓ internal/ (Config, Cache, Blocklist, WebAPI)"
    echo -e "  ✓ web/ (HTML, CSS, JS)"
    echo ""
    read -p "Nyomj Entert a menübe való visszatéréshez..."
    show_main_menu
}

show_main_menu
