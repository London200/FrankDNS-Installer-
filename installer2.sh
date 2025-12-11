#!/bin/bash
set -e

# ==============================================================================
#  FRANKDNS+ 2026 - FULL INSTALLER (v4.0)
#  ARCHITEKTÚRA: Go module + internal/ + web/
#  INSTALL DIR: /home/robot_36/frankdnsplus
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_USER="robot_36"
INSTALL_GROUP="robot_36"
INSTALL_DIR="/home/robot_36/frankdnsplus"
CONFIG_BACKUP="/tmp/frankdnsplus_config_backup.json"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}HIBA: Kérlek, futtasd root jogosultsággal!${NC}"
  echo -e "${YELLOW}Példa:${NC} sudo ./installer.sh"
  exit 1
fi

print_block() {
    echo -e "\n${BLUE}############################################################${NC}"
    echo -e "${BLUE}#${NC} ${YELLOW}${BOLD}$1${NC}"
    echo -e "${BLUE}############################################################${NC}"
    sleep 1
}

show_main_menu() {
    clear
    echo -e "${BLUE}############################################################${NC}"
    echo -e "${BLUE}#${NC}       ${BOLD}FRANKDNS+ 2026 - MODULAR SYSTEM v4.0${NC}       ${BLUE}#${NC}"
    echo -e "${BLUE}############################################################${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} 🚀 TELEPÍTÉS / JAVÍTÁS"
    echo -e "  ${YELLOW}2)${NC} 🔄 RENDSZER FRISSÍTÉS + TELEPÍTÉS"
    echo -e "  ${YELLOW}3)${NC} 🎛️  VEZÉRLŐPULT"
    echo -e "  ${YELLOW}4)${NC} 🚪 Kilépés"
    echo ""
    read -p "Mit szeretnél tenni? (1-4): " choice

    case "$choice" in
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
                echo ""
                read -p "Nyomj Entert a menübe való visszatéréshez..." _
                show_main_menu
            else
                echo -e "${RED}❌ A FrankDNS+ nincs telepítve!${NC}"
                sleep 2
                show_main_menu
            fi
            ;;
        4)
            exit 0
            ;;
        *)
            show_main_menu
            ;;
    esac
}

run_installer() {
    print_block "1. LÉPÉS: TAKARÍTÁS ÉS ELŐKÉSZÍTÉS"

    echo "🛑 Régi szolgáltatások leállítása..."
    systemctl stop frankdnsplus 2>/dev/null || true
    systemctl disable frankdnsplus 2>/dev/null || true

    echo "🔓 Portok felszabadítása..."
    fuser -k 3000/tcp 2>/dev/null || true
    fuser -k 8080/tcp 2>/dev/null || true
    fuser -k 53/tcp 2>/dev/null || true
    fuser -k 53/udp 2>/dev/null || true

    echo "💾 Konfiguráció mentése (config.json, ha van)..."
    if [ -f "$INSTALL_DIR/config.json" ]; then
        cp "$INSTALL_DIR/config.json" "$CONFIG_BACKUP"
        echo "   → $CONFIG_BACKUP"
    fi
    if [ -f "/opt/frankdnsplus/config.json" ] && [ ! -f "$CONFIG_BACKUP" ]; then
        cp "/opt/frankdnsplus/config.json" "$CONFIG_BACKUP"
        echo "   → /opt/frankdnsplus/config.json → $CONFIG_BACKUP"
    fi

    echo "🗑️ Régi telepítés törlése..."
    rm -rf "$INSTALL_DIR"
    rm -rf /opt/frankdnsplus
    rm -f /etc/systemd/system/frankdnsplus.service

    echo "🌐 DNS ideiglenes beállítása..."
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    echo "📁 Könyvtárstruktúra létrehozása: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/cmd/frankdns"
    mkdir -p "$INSTALL_DIR/internal/config"
    mkdir -p "$INSTALL_DIR/internal/dnsserver"
    mkdir -p "$INSTALL_DIR/internal/discovery"
    mkdir -p "$INSTALL_DIR/internal/webapi"
    mkdir -p "$INSTALL_DIR/web"

    echo "🧾 Jogosultságok beállítása (root:root, 755)..."
    chown -R root:root "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    print_block "SYSTEM UPDATE"

    echo "📦 Rendszer frissítése (apt-get update)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y

    if [ "$FULL_UPDATE" = true ]; then
        echo "📦 Teljes rendszer upgrade (apt-get upgrade)..."
        apt-get upgrade -y
    fi

    echo "📦 Függőségek telepítése (git, curl, lsof, wget, tar, psmisc, net-tools, ca-certificates, libcap2-bin)..."
    apt-get install -y git curl lsof wget tar psmisc net-tools ca-certificates libcap2-bin

    print_block "2. LÉPÉS: GO MOTOR TELEPÍTÉSE"

    echo "🧹 Régi Go eltávolítása..."
    rm -rf /usr/local/go

    RAW_ARCH=$(dpkg --print-architecture)
    case "$RAW_ARCH" in
        amd64) GO_ARCH="amd64" ;;
        arm64) GO_ARCH="arm64" ;;
        armhf) GO_ARCH="armv6l" ;;
        i386)  GO_ARCH="386" ;;
        *)     GO_ARCH="amd64" ;;
    esac

    echo "🔍 Architektúra detektálva: $GO_ARCH"

    if wget -q --spider "https://go.dev/dl/go1.23.4.linux-$GO_ARCH.tar.gz"; then
        GO_VER="1.23.4"
    else
        GO_VER="1.22.6"
    fi

    echo "⬇️ Go $GO_VER letöltése..."
    wget -q "https://go.dev/dl/go$GO_VER.linux-$GO_ARCH.tar.gz" -O /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz

    export PATH=$PATH:/usr/local/go/bin
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    print_block "3. LÉPÉS: GO FORRÁSKÓD GENERÁLÁSA"

    cd "$INSTALL_DIR"

    ###########################################################################
    # go.mod
    ###########################################################################
    cat << 'EOF' > go.mod
module frankdnsplus

go 1.22

require (
    github.com/miekg/dns v1.1.62
)
EOF

    ###########################################################################
    # internal/config/config.go
    ###########################################################################
    cat << 'EOF' > internal/config/config.go
package config

import (
	"encoding/json"
	"os"
	"sync"
)

var (
	Instance *Config
	Mutex    sync.RWMutex
	Path     = "/home/robot_36/frankdnsplus/config.json"
)

type BlocklistConfig struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Enabled bool   `json:"enabled"`
}

type Device struct {
	Name     string `json:"name"`
	IP       string `json:"ip"`
	MAC      string `json:"mac"`
	LastSeen string `json:"last_seen"`
}

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

func Default() Config {
	return Config{
		ListenDNS:     ":53",
		ListenHTTP:    ":3000",
		Upstreams:     []string{"tls://1.1.1.1", "tls://1.0.0.1"},
		ResponseMode:  "zero",
		LogBufferSize: 3000,

		AIDetection:         true,
		BlockingEnabled:     true,
		AgressiveAIBlocking: false,
		Devices:             []Device{},

		Whitelist: []string{},

		Blacklist: []string{
			"adtago.s3.amazonaws.com",
			"analyticsengine.s3.amazonaws.com",
			"analytics.s3.amazonaws.com",
			"advice-ads.s3.amazonaws.com",
			"advertising-api-eu.amazon.com",

			"pagead2.googlesyndication.com",
			"adservice.google.com",
			"pagead2.googleadservices.com",
			"afs.googlesyndication.com",

			"stats.g.doubleclick.net",
			"ad.doubleclick.net",
			"static.doubleclick.net",
			"m.doubleclick.net",
			"mediavisor.doubleclick.net",

			"ads30.adcolony.com",
			"adc3-launch.adcolony.com",
			"events3alt.adcolony.com",
			"wd.adcolony.com",

			"static.media.net",
			"media.net",
			"adservetx.media.net",

			"analytics.google.com",
			"click.googleanalytics.com",
			"google-analytics.com",
			"ssl.google-analytics.com",

			"connect.facebook.net",
			"graph.facebook.com",
			"staticxx.facebook.com",
			"star.c10r.facebook.com",
			"star-mini.c10r.facebook.com",
			"b-api.facebook.com",
			"b-graph.facebook.com",
			"rupload.facebook.com",
			"external-lhr.xx.fbcdn.net",
			"external-lht.xx.fbcdn.net",
			"scontent-lhr.xx.fbcdn.net",
			"static.xx.fbcdn.net",
			"creative.ak.fbcdn.net",
			"advertising.facebook.com",
			"ads.facebook.com",
			"pixel.facebook.com",
			"an.facebook.com",
		},

		Blocklists: []BlocklistConfig{
			{
				Name:    "FRANK SUPERBLOCK — ULTRA+ 2026",
				URL:     "https://raw.githubusercontent.com/London200/FRANK-SUPERBLOCK-ULTRA-2026/main/HEAD/FRANK%20SUPERBLOCK%20ULTRA%202026%20DNS%20v29.12.2026.txt",
				Enabled: true,
			},
			{
				Name:    "AdGuard DNS Filter",
				URL:     "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt",
				Enabled: true,
			},
			{
				Name:    "NoTracking",
				URL:     "https://raw.githubusercontent.com/notracking/hosts-blocklists/master/adblock/adblock.txt",
				Enabled: true,
			},
			{
				Name:    "Goodbye Ads",
				URL:     "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt",
				Enabled: true,
			},
			{
				Name:    "Hagezi Pro Plus",
				URL:     "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt",
				Enabled: true,
			},
			{
				Name:    "AdGuard Mobile Ads",
				URL:     "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt",
				Enabled: true,
			},
			{
				Name:    "AdGuard Social Media",
				URL:     "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt",
				Enabled: true,
			},
			{
				Name:    "AdGuard Tracking Protection",
				URL:     "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt",
				Enabled: true,
			},
			{
				Name:    "OISD Big",
				URL:     "https://big.oisd.nl",
				Enabled: true,
			},
		},
	}
}

func Load() {
	file, err := os.Open(Path)
	if err != nil {
		cfg := Default()
		Instance = &cfg
		Save()
		return
	}
	defer file.Close()

	cfg := Default()
	if err := json.NewDecoder(file).Decode(&cfg); err != nil {
		Instance = &cfg
		return
	}
	Instance = &cfg
}

func Save() error {
	data, err := json.MarshalIndent(Instance, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(Path, data, 0644)
}
EOF

    ###########################################################################
    # internal/discovery/discovery.go  (IP → MAC → eszköz frissítés)
    ###########################################################################
    cat << 'EOF' > internal/discovery/discovery.go
package discovery

import (
	"bufio"
	"log"
	"os/exec"
	"strings"
	"time"

	"frankdnsplus/internal/config"
)

func ResolveMAC(ip string) string {
	if ip == "" {
		return ""
	}

	out, err := exec.Command("arp", "-n", ip).Output()
	if err != nil || len(out) == 0 {
		return ""
	}

	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, ip) {
			continue
		}
		parts := strings.Fields(line)
		for _, p := range parts {
			if strings.Count(p, ":") == 5 {
				return strings.ToLower(p)
			}
		}
	}
	return ""
}

func guessNameFromMAC(mac string) string {
	m := strings.ToLower(mac)

	switch {
	case strings.HasPrefix(m, "dc:a6:32"), strings.HasPrefix(m, "28:6c:07"):
		return "Apple_Device"
	case strings.HasPrefix(m, "fc:48:ef"), strings.HasPrefix(m, "c8:3a:35"):
		return "Samsung_Device"
	case strings.HasPrefix(m, "44:65:0d"), strings.HasPrefix(m, "f0:27:65"):
		return "Amazon_Echo"
	case strings.HasPrefix(m, "d8:31:cf"):
		return "Xiaomi_Device"
	default:
		return "Device_" + strings.ReplaceAll(mac, ":", "")
	}
}

func UpdateDeviceLastSeen(ip, mac string) {
	if ip == "" || mac == "" || config.Instance == nil {
		return
	}

	config.Mutex.Lock()
	defer config.Mutex.Unlock()

	now := time.Now().Format(time.RFC3339)
	for i, d := range config.Instance.Devices {
		if d.IP == ip {
			config.Instance.Devices[i].MAC = mac
			if d.Name == "" {
				config.Instance.Devices[i].Name = guessNameFromMAC(mac)
			}
			config.Instance.Devices[i].LastSeen = now
			if err := config.Save(); err != nil {
				log.Println("❌ [DISCOVERY] Mentési hiba:", err)
			}
			return
		}
	}

	// új eszköz
	config.Instance.Devices = append(config.Instance.Devices, config.Device{
		IP:       ip,
		MAC:      mac,
		Name:     guessNameFromMAC(mac),
		LastSeen: now,
	})
	if err := config.Save(); err != nil {
		log.Println("❌ [DISCOVERY] Mentési hiba:", err)
	}
}
EOF

    ###########################################################################
    # internal/dnsserver/dns.go  (DNS motor + blokkolás + eszköz naplózás)
    ###########################################################################
    cat << 'EOF' > internal/dnsserver/dns.go
package dnsserver

import (
	"bufio"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/miekg/dns"
	"frankdnsplus/internal/config"
	"frankdnsplus/internal/discovery"
)

var (
	blockedDomains = make(map[string]bool)
)

// StartDNS indítja el a DNS szervert (UDP :53-on vagy amit a configban beállítasz)
func StartDNS() {
	if config.Instance == nil {
		cfg := config.Default()
		config.Instance = &cfg
	}

	addr := config.Instance.ListenDNS
	if addr == "" {
		addr = ":53"
	}

	// alap handler
	dns.HandleFunc(".", handleDNS)

	server := &dns.Server{
		Addr: addr,
		Net:  "udp",
	}

	log.Println("[DNS] Szerver indul:", addr)

	go func() {
		if err := server.ListenAndServe(); err != nil {
			log.Println("❌ [DNS] Hiba a ListenAndServe-ben:", err)
		}
	}()
}

// DNS kérés kezelése
func handleDNS(w dns.ResponseWriter, r *dns.Msg) {
	reply := new(dns.Msg)
	reply.SetReply(r)

	if len(r.Question) == 0 {
		_ = w.WriteMsg(reply)
		return
	}

	q := r.Question[0]
	domain := strings.TrimSuffix(strings.ToLower(q.Name), ".")

	// 💡 kliens IP → MAC → eszköz naplózás
	clientIP := clientIPFromAddr(w.RemoteAddr())
	if clientIP != "" {
		mac := discovery.ResolveMAC(clientIP)
		if mac != "" {
			discovery.UpdateDeviceLastSeen(clientIP, mac)
		}
	}

	// WHITELIST: ha egyezés van, akkor mindig engedjük
	if inDomainList(domain, config.Instance.Whitelist) {
		log.Printf("[DNS] ALLOW (whitelist) %s\n", domain)
		proxyUpstream(w, r, reply)
		return
	}

	// AI detektálás és agresszív blokkolás
	if config.Instance.AIDetection && config.Instance.AgressiveAIBlocking && isAI(domain) {
		log.Printf("[DNS] BLOCK (AI) %s\n", domain)
		blockDomain(w, reply, q)
		return
	}

	// Feketelista (memória-cache a blocklistből)
	if config.Instance.BlockingEnabled && BlockedInCache(domain) {
		log.Printf("[DNS] BLOCK (blocklist) %s\n", domain)
		blockDomain(w, reply, q)
		return
	}

	// Ha se whitelist, se blocklist → továbbítás upstream felé
	proxyUpstream(w, r, reply)
}

func clientIPFromAddr(a net.Addr) string {
	if a == nil {
		return ""
	}
	switch v := a.(type) {
	case *net.UDPAddr:
		return v.IP.String()
	case *net.TCPAddr:
		return v.IP.String()
	default:
		host, _, err := net.SplitHostPort(a.String())
		if err != nil {
			return ""
		}
		return host
	}
}

func inDomainList(domain string, list []string) bool {
	d := strings.ToLower(domain)
	for _, item := range list {
		item = strings.ToLower(strings.TrimSpace(item))
		if item == "" {
			continue
		}
		if d == item || strings.HasSuffix(d, "."+item) {
			return true
		}
	}
	return false
}

// Egyszerű 0.0.0.0 válasz blokkolásnál
func blockDomain(w dns.ResponseWriter, reply *dns.Msg, q dns.Question) {
	rr := &dns.A{
		Hdr: dns.RR_Header{
			Name:   q.Name,
			Rrtype: dns.TypeA,
			Class:  dns.ClassINET,
			Ttl:    1,
		},
		A: net.IPv4(0, 0, 0, 0),
	}
	reply.Answer = []dns.RR{rr}
	_ = w.WriteMsg(reply)
}

// Upstream továbbítás (Cloudflare / saját upstream lista szerint)
func proxyUpstream(w dns.ResponseWriter, r *dns.Msg, fallback *dns.Msg) {
	upstream := "1.1.1.1:53"

	// Ha vannak megadott upstream-ek, az első értelmeset használjuk
	if len(config.Instance.Upstreams) > 0 {
		for _, u := range config.Instance.Upstreams {
			u = strings.TrimSpace(u)
			if u == "" {
				continue
			}
			u = strings.TrimPrefix(u, "tls://")
			if !strings.Contains(u, ":") {
				u = u + ":53"
			}
			upstream = u
			break
		}
	}

	c := &dns.Client{
		Net:     "udp",
		Timeout: 4 * time.Second,
	}

	resp, _, err := c.Exchange(r, upstream)
	if err != nil || resp == nil {
		log.Println("❌ [DNS] Upstream hiba:", err)
		_ = w.WriteMsg(fallback)
		return
	}

	_ = w.WriteMsg(resp)
}

// ===== Blocklist kezelés =====

func RefreshBlocklists() {
	log.Println("🔄 Blocklist frissítés indul...")
	newMap := make(map[string]bool)

	for _, bl := range config.Instance.Blocklists {
		if !bl.Enabled || strings.TrimSpace(bl.URL) == "" {
			continue
		}
		log.Println("  → Töltés:", bl.Name, bl.URL)
		if err := loadBlocklistURL(bl.URL, newMap); err != nil {
			log.Println("   ❌ Hiba:", err)
		}
	}

	blockedDomains = newMap
	log.Printf("✅ Blocklist frissítve, %d elem.\n", len(blockedDomains))
}

func loadBlocklistURL(url string, target map[string]bool) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "!") || strings.HasPrefix(line, "#") {
			continue
		}

		line = strings.TrimPrefix(line, "||")
		line = strings.TrimSuffix(line, "^")

		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		target[strings.ToLower(line)] = true
	}

	return scanner.Err()
}

func BlockedInCache(domain string) bool {
	d := strings.ToLower(domain)
	if blockedDomains[d] {
		return true
	}

	// aldomain → fő domain
	for {
		i := strings.Index(d, ".")
		if i < 0 {
			break
		}
		d = d[i+1:]
		if blockedDomains[d] {
			return true
		}
	}
	return false
}

func isAI(domain string) bool {
	d := strings.ToLower(domain)
	aiList := []string{
		"openai.com",
		"chatgpt.com",
		"anthropic.com",
		"deepseek.com",
		"deepseek.ai",
		"claude.ai",
		"perplexity.ai",
		"copilot.microsoft.com",
	}
	for _, a := range aiList {
		if d == a || strings.HasSuffix(d, "."+a) {
			return true
		}
	}
	return false
}
EOF

    ###########################################################################
    # internal/webapi/webapi.go  (config API + device API + blocklist update)
    ###########################################################################
    cat << 'EOF' > internal/webapi/webapi.go
package webapi

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"frankdnsplus/internal/config"
	"frankdnsplus/internal/dnsserver"
)

func StartHTTP() {
	if config.Instance == nil {
		cfg := config.Default()
		config.Instance = &cfg
	}

	addr := config.Instance.ListenHTTP
	if addr == "" {
		addr = ":3000"
	}

	mux := http.NewServeMux()

	// Static web UI
	fs := http.FileServer(http.Dir("web"))
	mux.Handle("/", fs)

	// API-k
	mux.HandleFunc("/api/config/get", handleGetConfig)
	mux.HandleFunc("/api/config/save", handleSaveConfig)
	mux.HandleFunc("/api/blocklists/update", handleBlocklistUpdate)
	mux.HandleFunc("/api/devices/update", handleDeviceUpdate)

	log.Println("[HTTP] Web felület indul:", addr)

	go func() {
		if err := http.ListenAndServe(addr, mux); err != nil {
			log.Println("❌ [HTTP] Hiba:", err)
		}
	}()
}

func handleGetConfig(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(config.Instance); err != nil {
		http.Error(w, "JSON hiba", 500)
	}
}

func handleSaveConfig(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	var newCfg config.Config
	if err := json.NewDecoder(r.Body).Decode(&newCfg); err != nil {
		http.Error(w, "Hibás JSON", 400)
		return
	}

	config.Mutex.Lock()
	*config.Instance = newCfg
	config.Mutex.Unlock()

	if err := config.Save(); err != nil {
		http.Error(w, "Mentési hiba", 500)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok"}`))
}

func handleBlocklistUpdate(w http.ResponseWriter, r *http.Request) {
	go dnsserver.RefreshBlocklists()
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"started"}`))
}

func handleDeviceUpdate(w http.ResponseWriter, r *http.Request) {
	type Req struct {
		Name string `json:"name"`
		IP   string `json:"ip"`
		MAC  string `json:"mac"`
	}

	defer r.Body.Close()
	var req Req
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Hibás JSON", 400)
		return
	}

	if req.IP == "" {
		http.Error(w, "IP kötelező", 400)
		return
	}

	config.Mutex.Lock()
	defer config.Mutex.Unlock()

	now := time.Now().Format(time.RFC3339)
	for i, d := range config.Instance.Devices {
		if d.IP == req.IP {
			if req.Name != "" {
				config.Instance.Devices[i].Name = req.Name
			}
			if req.MAC != "" {
				config.Instance.Devices[i].MAC = req.MAC
			}
			config.Instance.Devices[i].LastSeen = now
			_ = config.Save()
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(`{"status":"saved"}`))
			return
		}
	}

	// új eszköz
	config.Instance.Devices = append(config.Instance.Devices, config.Device{
		Name:     req.Name,
		IP:       req.IP,
		MAC:      req.MAC,
		LastSeen: now,
	})

	_ = config.Save()
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"added"}`))
}
EOF

    ###########################################################################
    # cmd/frankdns/main.go  (belépési pont)
    ###########################################################################
    cat << 'EOF' > cmd/frankdns/main.go
package main

import (
	"log"
	"time"

	"frankdnsplus/internal/config"
	"frankdnsplus/internal/dnsserver"
	"frankdnsplus/internal/webapi"
)

func main() {
	log.Println("🚀 FrankDNS+ 2026 indul...")

	// Konfig betöltése (ha nincs fájl, létrejön egy default)
	config.Load()
	log.Println("📘 Konfig betöltve.")

	// Blocklist cache első feltöltése induláskor
	go func() {
		log.Println("🔄 Blocklist első frissítése indul...")
		dnsserver.RefreshBlocklists()
		log.Println("✅ Blocklist frissítés kész.")
	}()

	// Web felület + API
	webapi.StartHTTP()

	// DNS motor
	dnsserver.StartDNS()

	log.Println("✅ FrankDNS+ fut. Nyomd meg a Ctrl+C-t a leállításhoz (service esetén systemctl).")
	for {
		time.Sleep(1 * time.Hour)
	}
}
EOF

    ###########################################################################
    # web/index.html  (régi jellegű 3 tabos felület)
    ###########################################################################
    cat << 'EOF' > web/index.html
<!DOCTYPE html>
<html lang="hu">
<head>
    <meta charset="UTF-8">
    <title>FrankDNS+ 2026</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="/style.css">
</head>
<body>
<div class="container">
    <header class="header">
        <h1>FrankDNS+ <span>2026</span></h1>
        <div class="status">
            <span class="dot"></span>
            <span class="text">DNS motor fut</span>
        </div>
    </header>

    <nav class="tabs">
        <button class="tab-button active" data-tab="config">Beállítások</button>
        <button class="tab-button" data-tab="lists">Fehér / Fekete lista</button>
        <button class="tab-button" data-tab="devices">Eszközök</button>
    </nav>

    <main>
        <section id="tab-config" class="tab-content active">
            <h2>DNS beállítások</h2>

            <div class="card">
                <label>DNS szerver port (ListenDNS)</label>
                <input type="text" id="cfg-listen-dns" placeholder=":53">

                <label>Web felület port (ListenHTTP)</label>
                <input type="text" id="cfg-listen-http" placeholder=":3000">

                <label>Upstream szerverek (soronként egy)</label>
                <textarea id="cfg-upstreams" placeholder="tls://1.1.1.1&#10;tls://1.0.0.1"></textarea>

                <button class="btn primary" onclick="saveConfig()">Beállítások mentése</button>
                <button class="btn" onclick="refreshConfig()">Visszatöltés</button>
            </div>

            <div class="card">
                <h3>Szűrőlisták (Blocklists)</h3>
                <div id="blocklist-container"></div>
                <button class="btn" onclick="addBlocklist()">+ Új lista</button>
                <button class="btn primary" onclick="saveConfig()">Listák mentése</button>
                <button class="btn danger" onclick="updateBlocklists()">Szűrőlisták frissítése most</button>
            </div>
        </section>

        <section id="tab-lists" class="tab-content">
            <h2>Fehérlista / Feketelista</h2>
            <div class="card">
                <h3>Fehérlista (Whitelist)</h3>
                <p class="hint">Ezeket a domaineket soha nem blokkolja a rendszer.</p>
                <textarea id="cfg-whitelist" placeholder="example.com&#10;openai.com"></textarea>

                <h3>Feketelista (Blacklist)</h3>
                <p class="hint">Ezeket a domaineket mindig blokkolja a rendszer.</p>
                <textarea id="cfg-blacklist" placeholder="badads.example.com&#10;tracking.example.com"></textarea>

                <button class="btn primary" onclick="saveConfig()">Kivételek mentése</button>
                <button class="btn" onclick="refreshConfig()">Visszatöltés</button>
            </div>
        </section>

        <section id="tab-devices" class="tab-content">
            <h2>Eszközök</h2>
            <div class="card">
                <p class="hint">
                    Az eszköz neveket automatikusan felismerjük (ARP + MAC), de itt átírhatod és elmentheted.
                </p>
                <div class="device-list-header">
                    <span>Eszköznév</span>
                    <span>IP</span>
                    <span>MAC</span>
                    <span>Utolsó látva</span>
                    <span>Művelet</span>
                </div>
                <div id="device-list"></div>

                <h3>Új eszköz manuális hozzáadása</h3>
                <div class="device-form">
                    <input type="text" id="new-dev-ip" placeholder="IP (pl. 192.168.3.10)">
                    <input type="text" id="new-dev-mac" placeholder="MAC (pl. aa:bb:cc:dd:ee:ff)">
                    <input type="text" id="new-dev-name" placeholder="Eszköznév (pl. Frank iPhone)">
                    <button class="btn primary" onclick="addDevice()">Hozzáadás</button>
                </div>
            </div>
        </section>
    </main>
</div>

<div id="toast"></div>

<script src="/app.js"></script>
</body>
</html>
EOF

    ###########################################################################
    # web/style.css
    ###########################################################################
    cat << 'EOF' > web/style.css
:root {
    --bg: #05060a;
    --card: #111218;
    --border: #23252f;
    --accent: #00d2ff;
    --accent-soft: rgba(0,210,255,0.12);
    --danger: #ff4b6a;
    --text: #f5f5f7;
    --muted: #9b9dac;
    --radius: 18px;
    --shadow-soft: 0 18px 45px rgba(0,0,0,0.65);
}

* { box-sizing: border-box; }

body {
    margin: 0;
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: radial-gradient(circle at top, #101524 0, #05060a 45%, #020308 100%);
    color: var(--text);
    min-height: 100vh;
    padding: 20px;
}

.container {
    max-width: 1100px;
    margin: 0 auto;
}

.header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 25px;
}

.header h1 {
    font-size: 1.9rem;
    margin: 0;
    letter-spacing: 0.05em;
}

.header h1 span {
    font-size: 0.75em;
    font-weight: 400;
    opacity: 0.7;
}

.status {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    border-radius: 999px;
    border: 1px solid rgba(0,210,255,0.35);
    background: radial-gradient(circle at top left, rgba(0,210,255,0.2), transparent 55%);
    font-size: 0.85rem;
}

.status .dot {
    width: 9px;
    height: 9px;
    border-radius: 999px;
    background: #39ff14;
    box-shadow: 0 0 12px rgba(57,255,20,0.9);
    animation: blink 1.5s infinite;
}

.status .text { opacity: 0.85; }

@keyframes blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.35; }
}

.tabs {
    display: inline-flex;
    gap: 8px;
    border-radius: 999px;
    padding: 4px;
    background: rgba(8,10,18,0.9);
    border: 1px solid rgba(46,50,75,0.9);
    margin-bottom: 20px;
}

.tab-button {
    border: none;
    background: transparent;
    color: var(--muted);
    padding: 8px 18px;
    border-radius: 999px;
    font-size: 0.9rem;
    cursor: pointer;
    transition: all 0.18s ease;
}

.tab-button:hover { color: var(--text); }

.tab-button.active {
    background: var(--accent-soft);
    color: var(--accent);
    box-shadow: 0 0 18px rgba(0,210,255,0.25);
}

main { display: block; }
.tab-content { display: none; }
.tab-content.active { display: block; }

.card {
    background: radial-gradient(circle at top left, rgba(0,210,255,0.12), transparent 60%), var(--card);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    padding: 18px 20px 20px;
    box-shadow: var(--shadow-soft);
    margin-bottom: 18px;
}

h2 {
    margin: 0 0 14px;
    font-size: 1.3rem;
}

h3 {
    margin: 12px 0 10px;
    font-size: 1rem;
}

label {
    display: block;
    font-size: 0.85rem;
    color: var(--muted);
    margin-bottom: 4px;
    margin-top: 8px;
}

input[type="text"],
textarea {
    width: 100%;
    background: #05060b;
    color: var(--text);
    border-radius: 10px;
    border: 1px solid #262938;
    padding: 8px 10px;
    font-size: 0.9rem;
    resize: vertical;
    min-height: 38px;
    outline: none;
    transition: border-color 0.18s ease, box-shadow 0.18s ease, background 0.18s ease;
}

input[type="text"]:focus,
textarea:focus {
    border-color: var(--accent);
    box-shadow: 0 0 0 1px rgba(0,210,255,0.35);
    background: #070815;
}

textarea {
    min-height: 90px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
}

.btn {
    border-radius: 999px;
    border: 1px solid #2f3245;
    background: #10121d;
    color: var(--text);
    font-size: 0.85rem;
    padding: 7px 16px;
    cursor: pointer;
    margin-top: 10px;
    margin-right: 8px;
    transition: all 0.18s ease;
}

.btn.primary {
    border-color: rgba(0,210,255,0.7);
    background: linear-gradient(90deg, #00b4ff, #00e0ff);
    color: #000;
    box-shadow: 0 12px 30px rgba(0,210,255,0.35);
}

.btn.primary:hover { filter: brightness(1.05); }

.btn.danger {
    border-color: rgba(255,75,106,0.75);
    color: #ffdbe1;
    background: radial-gradient(circle at top left, rgba(255,75,106,0.25), #18111a);
}

.btn:hover {
    transform: translateY(-1px);
    box-shadow: 0 10px 24px rgba(0,0,0,0.4);
}

.hint {
    font-size: 0.8rem;
    color: var(--muted);
    margin-top: 4px;
    margin-bottom: 10px;
}

#blocklist-container {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 8px;
}

.blocklist-row {
    display: grid;
    grid-template-columns: minmax(120px, 180px) minmax(200px, 1fr) auto;
    gap: 6px;
    align-items: center;
}

.blocklist-row input[type="text"] {
    min-height: 32px;
}

.blocklist-row .bl-toggle {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 0.8rem;
    color: var(--muted);
}

.device-list-header {
    display: grid;
    grid-template-columns: 2fr 1.4fr 1.6fr 1.6fr auto;
    gap: 6px;
    font-size: 0.8rem;
    color: var(--muted);
    margin-bottom: 6px;
}

.device-row {
    display: grid;
    grid-template-columns: 2fr 1.4fr 1.6fr 1.6fr auto;
    gap: 6px;
    align-items: center;
    padding: 5px 0;
    border-bottom: 1px dashed #242637;
    font-size: 0.85rem;
}

.device-row:last-child {
    border-bottom: none;
}

.device-row input[type="text"] {
    min-height: 32px;
}

.device-form {
    display: grid;
    grid-template-columns: 1.4fr 1.4fr 1.7fr auto;
    gap: 6px;
    margin-top: 8px;
}

.badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 999px;
    padding: 4px 9px;
    font-size: 0.7rem;
    border: 1px solid rgba(255,255,255,0.2);
    color: var(--muted);
}

.badge.small-btn {
    cursor: pointer;
    border-color: rgba(0,210,255,0.65);
    color: var(--accent);
}

.badge.small-btn:hover {
    background: var(--accent-soft);
}

#toast {
    position: fixed;
    left: 50%;
    bottom: 22px;
    transform: translateX(-50%);
    background: #11111a;
    color: var(--text);
    padding: 9px 16px;
    border-radius: 999px;
    font-size: 0.8rem;
    border: 1px solid #303248;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.18s ease, transform 0.18s ease;
    box-shadow: 0 12px 30px rgba(0,0,0,0.75);
}

#toast.show {
    opacity: 1;
    transform: translateX(-50%) translateY(-4px);
}
EOF

    ###########################################################################
    # web/app.js
    ###########################################################################
    cat << 'EOF' > web/app.js
let currentConfig = null;

window.addEventListener('DOMContentLoaded', () => {
    setupTabs();
    refreshConfig();
});

function setupTabs() {
    const buttons = document.querySelectorAll('.tab-button');
    buttons.forEach(btn => {
        btn.addEventListener('click', () => {
            buttons.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            const target = btn.dataset.tab;
            document.querySelectorAll('.tab-content').forEach(sec => {
                sec.classList.remove('active');
            });
            const sec = document.querySelector('#tab-' + target);
            if (sec) sec.classList.add('active');
        });
    });
}

function showToast(msg) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2200);
}

async function refreshConfig() {
    try {
        const res = await fetch('/api/config/get');
        if (!res.ok) throw new Error("Hiba /api/config/get");

        currentConfig = await res.json();

        document.getElementById('cfg-listen-dns').value = currentConfig.listen_dns || ":53";
        document.getElementById('cfg-listen-http').value = currentConfig.listen_http || ":3000";
        document.getElementById('cfg-upstreams').value = (currentConfig.upstreams || []).join('\n');
        document.getElementById('cfg-whitelist').value = (currentConfig.whitelist || []).join('\n');
        document.getElementById('cfg-blacklist').value = (currentConfig.blacklist || []).join('\n');

        renderBlocklists();
        renderDevices();

    } catch (e) {
        console.error(e);
        showToast("Hiba a beállítások betöltésekor");
    }
}

function renderBlocklists() {
    const container = document.getElementById('blocklist-container');
    container.innerHTML = '';
    if (!currentConfig || !currentConfig.blocklists) return;

    currentConfig.blocklists.forEach((bl, idx) => {
        const row = document.createElement('div');
        row.className = 'blocklist-row';
        row.innerHTML = `
            <input type="text" value="${bl.name || ''}" placeholder="Név" data-idx="${idx}" data-field="name">
            <input type="text" value="${bl.url || ''}" placeholder="URL" data-idx="${idx}" data-field="url">
            <label class="bl-toggle">
                <input type="checkbox" ${bl.enabled ? 'checked' : ''} data-idx="${idx}" data-field="enabled">
                Engedélyezve
            </label>
        `;
        container.appendChild(row);
    });

    container.querySelectorAll('input[type="text"]').forEach(inp => {
        inp.addEventListener('input', () => {
            const i = parseInt(inp.dataset.idx, 10);
            const f = inp.dataset.field;
            currentConfig.blocklists[i][f] = inp.value;
        });
    });

    container.querySelectorAll('input[type="checkbox"]').forEach(chk => {
        chk.addEventListener('change', () => {
            const i = parseInt(chk.dataset.idx, 10);
            currentConfig.blocklists[i].enabled = chk.checked;
        });
    });
}

function addBlocklist() {
    if (!currentConfig.blocklists) currentConfig.blocklists = [];
    currentConfig.blocklists.push({
        name: "Új lista",
        url: "",
        enabled: true
    });
    renderBlocklists();
}

function renderDevices() {
    const box = document.getElementById('device-list');
    box.innerHTML = '';

    if (!currentConfig || !currentConfig.devices || currentConfig.devices.length === 0) {
        box.innerHTML = `<p class="hint">Még nincsenek ismert eszközök. DNS használat után megjelennek.</p>`;
        return;
    }

    currentConfig.devices.forEach((d, idx) => {
        const row = document.createElement('div');
        row.className = 'device-row';

        row.innerHTML = `
            <input type="text" value="${d.name || ''}" data-idx="${idx}" data-field="name">
            <span>${d.ip || '-'}</span>
            <span>${d.mac || '-'}</span>
            <span>${d.last_seen || '-'}</span>
            <span><span class="badge small-btn" onclick="saveDeviceName(${idx})">Mentés</span></span>
        `;
        box.appendChild(row);
    });
}

async function saveDeviceName(idx) {
    const dev = currentConfig.devices[idx];
    if (!dev) return;

    try {
        const res = await fetch('/api/devices/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                name: dev.name,
                ip: dev.ip,
                mac: dev.mac
            })
        });

        if (!res.ok) throw new Error("Mentés hiba");

        showToast("Eszköz név mentve");
        await refreshConfig();

    } catch (e) {
        console.error(e);
        showToast("Hiba az eszköz mentésekor");
    }
}

async function addDevice() {
    const ip = document.getElementById('new-dev-ip').value.trim();
    const mac = document.getElementById('new-dev-mac').value.trim();
    const name = document.getElementById('new-dev-name').value.trim();

    if (!ip || !name) {
        showToast("IP és név kötelező");
        return;
    }

    try {
        const res = await fetch('/api/devices/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ip, mac, name })
        });

        if (!res.ok) throw new Error("Hiba a POST-nál");

        showToast("Eszköz hozzáadva");
        document.getElementById('new-dev-ip').value = '';
        document.getElementById('new-dev-mac').value = '';
        document.getElementById('new-dev-name').value = '';

        await refreshConfig();

    } catch (e) {
        console.error(e);
        showToast("Hiba eszköz hozzáadásakor");
    }
}

async function updateBlocklists() {
    try {
        const res = await fetch('/api/blocklists/update', { method: 'POST' });
        if (!res.ok) throw new Error("Update hiba");

        showToast("Szűrőlisták frissítése elindítva");

    } catch (e) {
        console.error(e);
        showToast("Hiba a frissítésnél");
    }
}

async function saveConfig() {
    if (!currentConfig) {
        showToast("Nincs config betöltve");
        return;
    }

    currentConfig.listen_dns = document.getElementById('cfg-listen-dns').value.trim() || ":53";
    currentConfig.listen_http = document.getElementById('cfg-listen-http').value.trim() || ":3000";

    currentConfig.upstreams = document.getElementById('cfg-upstreams').value
        .split('\n').map(s => s.trim()).filter(Boolean);

    currentConfig.whitelist = document.getElementById('cfg-whitelist').value
        .split('\n').map(s => s.trim()).filter(Boolean);

    currentConfig.blacklist = document.getElementById('cfg-blacklist').value
        .split('\n').map(s => s.trim()).filter(Boolean);

    try {
        const res = await fetch('/api/config/save', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(currentConfig)
        });

        if (!res.ok) throw new Error("Config mentési hiba");

        showToast("Beállítások mentve");
        await refreshConfig();

    } catch (e) {
        console.error(e);
        showToast("Hiba mentéskor");
    }
}
EOF

    print_block "5. LÉPÉS: Go fordítás és szolgáltatás telepítése"

    cd "$INSTALL_DIR"

    echo "🔨 go mod tidy..."
    /usr/local/go/bin/go mod tidy

    echo "🔨 Bináris fordítása..."
    /usr/local/go/bin/go build -o main cmd/frankdns/main.go

    echo "🔑 Jogosultságok beállítása..."
    chown -R "$INSTALL_USER:$INSTALL_GROUP" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR" || true

    if command -v setcap >/dev/null 2>&1; then
        echo "🔐 CAP_NET_BIND_SERVICE engedélyezése (:53 root nélkül)..."
        setcap 'cap_net_bind_service=+ep' "$INSTALL_DIR/main" 2>/dev/null || true
    fi

    echo "⚙️ Systemd szolgáltatás létrehozása: frankdnsplus.service"

    cat << EOF > /etc/systemd/system/frankdnsplus.service
[Unit]
Description=FrankDNS+ 2026 Modular DNS Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/main
Restart=always
RestartSec=5
LimitNOFILE=65535
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frankdnsplus --now

    echo "🛠️  Vezérlő script telepítése: frank"

    cat << 'EOF' > /usr/local/bin/frank
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}FrankDNS+ Vezérlő${NC}"
echo "1. Státusz"
echo "2. Logok (utolsó 50 sor)"
echo "3. Újraindítás"
echo "4. Szolgáltatás leállítás"
echo "5. Kilépés"
read -p "Válassz: " opt
case "$opt" in
    1) systemctl status frankdnsplus ;;
    2) journalctl -u frankdnsplus -n 50 -f ;;
    3) systemctl restart frankdnsplus && echo -e "${GREEN}Újraindítva!${NC}" ;;
    4) systemctl stop frankdnsplus && echo -e "${RED}Leállítva!${NC}" ;;
    *) ;;
esac
EOF

    chmod +x /usr/local/bin/frank

    IP_CIM=$(hostname -I | awk '{print $1}')

    print_block "TELEPÍTÉS BEFEJEZVE! ✔️"
    echo -e "🌐 Webes felület elérhető: ${GREEN}http://$IP_CIM:3000${NC}"
    echo -e "🛠  Vezérlő: ${YELLOW}sudo frank${NC}"
    echo ""
    read -p "Nyomj Entert a főmenübe..." _
    show_main_menu
}

show_main_menu
