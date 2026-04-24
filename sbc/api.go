package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
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
}

type credCacheEntry struct {
	password  string
	expiresAt time.Time
}

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
	return &data, nil
}

func (a *InternalAPI) GetWalletBalance(subdomain string) (float64, error) {
	resp, err := a.post("/org/walletBalance", url.Values{
		"subdomain": {subdomain},
	})
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return 0, fmt.Errorf("wallet API returned %d", resp.StatusCode)
	}

	var result struct {
		Balance float64 `json:"balance"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, err
	}
	return result.Balance, nil
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
