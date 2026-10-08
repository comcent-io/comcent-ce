package main

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	PublicIP           string
	PrivateIP          string
	// PublicSIPPort is the EXTERNALLY reachable port that peers see SBC on.
	// Internally the SBC always binds 5060/5065. In dev (Docker port-mapping
	// host:6060 → container:5060) PUBLIC_SIP_PORT=6060 so Record-Route headers
	// point at the host-side port. In prod (no NAT) it stays 5060.
	PublicSIPPort      int
	PrivateSIPPort     int
	InternalAPIBaseURL string
	InternalAPIUser    string
	InternalAPIPass    string
	RPCAPIToken        string
	SIPUserRootDomain  string
	WSSCertPath        string
	WSSKeyPath         string
	WSSPort            int

	// How often UDP contacts behind a NAT are pinged to keep the router's
	// mapping open; 0 turns the keepalive off. Routers drop an idle UDP
	// mapping after 30 s at the earliest, so the default stays under that.
	NATPingInterval time.Duration
	// Consecutive unanswered pings after which a contact is unregistered.
	NATPingMaxMissed int
	// Longest registration a UDP contact behind a NAT is given, as a backstop
	// for a phone whose pings get through but whose mapping still changed.
	// 0 leaves the client's requested lifetime alone.
	NATMaxExpires int
}

func loadConfig() Config {
	return Config{
		PublicIP:           envOrDefault("PUBLIC_IP", "127.0.0.1"),
		PrivateIP:          envOrDefault("PRIVATE_IP", "127.0.0.1"),
		PublicSIPPort:      envIntOrDefault("PUBLIC_SIP_PORT", 5060),
		PrivateSIPPort:     envIntOrDefault("PRIVATE_SIP_PORT", 5065),
		InternalAPIBaseURL: envOrDefault("INTERNAL_API_BASE_URL", "http://server:4000/internal-api"),
		InternalAPIUser:    envOrDefault("INTERNAL_API_USERNAME", ""),
		InternalAPIPass:    envOrDefault("INTERNAL_API_PASSWORD", ""),
		RPCAPIToken:        envOrDefault("RPC_API_TOKEN", ""),
		SIPUserRootDomain:  envOrDefault("SIP_USER_ROOT_DOMAIN", "example.com"),
		WSSCertPath:        os.Getenv("WSS_CERT_PATH"),
		WSSKeyPath:         os.Getenv("WSS_KEY_PATH"),
		WSSPort:            envIntOrDefault("WSS_PORT", 443),
		NATPingInterval:    time.Duration(envIntOrDefault("NAT_PING_INTERVAL", 20)) * time.Second,
		NATPingMaxMissed:   envIntOrDefault("NAT_PING_MAX_MISSED", 3),
		NATMaxExpires:      envIntOrDefault("NAT_MAX_EXPIRES", 600),
	}
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envIntOrDefault(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
