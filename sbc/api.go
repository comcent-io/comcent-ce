package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type InternalAPI struct {
	baseURL  string
	username string
	password string
	client   *http.Client

	credCache  sync.Map // key: "user@domain" → *credCacheEntry
	trunkCache sync.Map // key: number → *trunkCacheEntry

	// Every trunk inbound CIDR seen since startup. These sources are never
	// banned (see ip_ban.go), even after their numbers drop out of trunkCache.
	trunkNetsMu sync.RWMutex
	trunkNets   map[string]*net.IPNet
}

// errNotFound is a 404 from the internal API: the user or number doesn't
// exist, as opposed to the API being unreachable.
var errNotFound = errors.New("not found")

type credCacheEntry struct {
	password  string
	expiresAt time.Time
}

// trunkCacheEntry with nil data caches a number the server doesn't know.
type trunkCacheEntry struct {
	data      *TrunkData
	expiresAt time.Time
}

type TrunkData struct {
	InboundIPs      []string `json:"inboundIps"`
	OutboundContact string   `json:"outboundContact"`
	OutboundUser    string   `json:"outboundUsername"`
	OutboundPass    string   `json:"outboundPassword"`
}

const cacheTTL = 5 * time.Minute

// unknownTrunkTTL is how long a number with no trunk is remembered, so a
// scanner dialling made-up numbers doesn't query the server on every INVITE,
// while a number just added in the app works within a minute.
const unknownTrunkTTL = time.Minute

func newInternalAPI(cfg Config) *InternalAPI {
	return &InternalAPI{
		baseURL:  cfg.InternalAPIBaseURL,
		username: cfg.InternalAPIUser,
		password: cfg.InternalAPIPass,
		client:   &http.Client{Timeout: 5 * time.Second},
	}
}

func (a *InternalAPI) GetUserPassword(username, domain string) (string, error) {
	key := username + "@" + domain
	if v, ok := a.credCache.Load(key); ok {
		entry := v.(*credCacheEntry)
		if time.Now().Before(entry.expiresAt) {
			return entry.password, nil
		}
		a.credCache.Delete(key)
	}

	resp, err := a.post("/user/credentials", url.Values{
		"username": {username},
		"domain":   {domain},
	})
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("credentials for %s: %w", key, errNotFound)
	}
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("credentials API returned %d", resp.StatusCode)
	}

	var result struct {
		P string `json:"p"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if result.P == "" {
		return "", fmt.Errorf("no password returned for %s", key)
	}

	a.credCache.Store(key, &credCacheEntry{
		password:  result.P,
		expiresAt: time.Now().Add(cacheTTL),
	})
	return result.P, nil
}

func (a *InternalAPI) GetSIPTrunk(number string) (*TrunkData, error) {
	if v, ok := a.trunkCache.Load(number); ok {
		entry := v.(*trunkCacheEntry)
		if time.Now().Before(entry.expiresAt) {
			if entry.data == nil {
				return nil, fmt.Errorf("sip trunk for %s: %w", number, errNotFound)
			}
			return entry.data, nil
		}
		a.trunkCache.Delete(number)
	}

	resp, err := a.post("/number/sip-trunk", url.Values{
		"number": {number},
	})
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		a.trunkCache.Store(number, &trunkCacheEntry{expiresAt: time.Now().Add(unknownTrunkTTL)})
		return nil, fmt.Errorf("sip trunk for %s: %w", number, errNotFound)
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("sip-trunk API returned %d for %s", resp.StatusCode, number)
	}

	var data TrunkData
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, err
	}

	a.trunkCache.Store(number, &trunkCacheEntry{
		data:      &data,
		expiresAt: time.Now().Add(cacheTTL),
	})
	a.rememberTrunkNets(data.InboundIPs)
	return &data, nil
}

func (a *InternalAPI) rememberTrunkNets(cidrs []string) {
	a.trunkNetsMu.Lock()
	defer a.trunkNetsMu.Unlock()
	if a.trunkNets == nil {
		a.trunkNets = make(map[string]*net.IPNet)
	}
	for _, cidr := range cidrs {
		if _, ok := a.trunkNets[cidr]; ok {
			continue
		}
		if _, network, err := net.ParseCIDR(cidr); err == nil {
			a.trunkNets[cidr] = network
		}
	}
}

// IsTrunkIP reports whether ip is inside the inbound IPs of any trunk looked
// up since startup.
func (a *InternalAPI) IsTrunkIP(ip string) bool {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return false
	}
	a.trunkNetsMu.RLock()
	defer a.trunkNetsMu.RUnlock()
	for _, network := range a.trunkNets {
		if network.Contains(parsed) {
			return true
		}
	}
	return false
}

func (a *InternalAPI) UpdateUserPresence(subdomain, action, username string) {
	resp, err := a.post("/user/presence", url.Values{
		"subdomain": {subdomain},
		"action":    {action},
		"username":  {username},
	})
	if err != nil {
		slog.Error("Failed to update presence", "error", err, "username", username)
		return
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		slog.Error("Presence update failed", "status", resp.StatusCode, "username", username)
	}
}

func (a *InternalAPI) InvalidateCredCache(username, domain string) {
	a.credCache.Delete(username + "@" + domain)
}

func (a *InternalAPI) InvalidateTrunkCache(number string) {
	a.trunkCache.Delete(number)
}

func (a *InternalAPI) post(path string, form url.Values) (*http.Response, error) {
	body := strings.NewReader(form.Encode())
	req, err := http.NewRequest("POST", a.baseURL+path, body)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(a.username, a.password)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return a.client.Do(req)
}
