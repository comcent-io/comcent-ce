package main

import (
	"context"
	"log/slog"
	"strings"
	"sync"
	"time"
)

type Contact struct {
	URI       string // logical Contact URI advertised by the UA
	Address   string // routable destination for the current registration hop
	Transport string
	IsWebRTC  bool
	ExpiresAt time.Time
}

type Registrar struct {
	mu       sync.RWMutex
	contacts map[string][]*Contact // key: user@domain → list of contacts
}

func newRegistrar(ctx context.Context) *Registrar {
	r := &Registrar{
		contacts: make(map[string][]*Contact),
	}
	go r.reapExpired(ctx)
	return r
}

func (r *Registrar) Register(aor string, c *Contact) {
	r.mu.Lock()
	defer r.mu.Unlock()

	list := r.contacts[aor]

	// Replace existing contact with same address, or append
	found := false
	for i, existing := range list {
		if existing.Address == c.Address {
			list[i] = c
			found = true
			break
		}
	}
	if !found {
		list = append(list, c)
	}
	r.contacts[aor] = list
	slog.Info("Registered", "aor", aor, "address", c.Address, "webrtc", c.IsWebRTC, "total", len(list))
}

func (r *Registrar) Unregister(aor string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.contacts, aor)
	slog.Info("Unregistered", "aor", aor)
}

func (r *Registrar) UnregisterContact(aor string, address string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	list := r.contacts[aor]
	for i, c := range list {
		if c.Address == address {
			r.contacts[aor] = append(list[:i], list[i+1:]...)
			slog.Info("Unregistered contact", "aor", aor, "address", address)
			return
		}
	}
}

// LookupAll returns all non-expired contacts for an AOR
func (r *Registrar) LookupAll(aor string) []*Contact {
	r.mu.RLock()
	defer r.mu.RUnlock()

	now := time.Now()
	var result []*Contact
	for _, c := range r.contacts[aor] {
		if now.Before(c.ExpiresAt) {
			result = append(result, c)
		}
	}
	return result
}

// LookupByType returns contacts filtered by WebRTC or SIP
func (r *Registrar) LookupByType(aor string, webrtc bool) []*Contact {
	all := r.LookupAll(aor)
	var result []*Contact
	for _, c := range all {
		if c.IsWebRTC == webrtc {
			result = append(result, c)
		}
	}
	return result
}

func (r *Registrar) IsRegistered(aor string) bool {
	return len(r.LookupAll(aor)) > 0
}

func (r *Registrar) reapExpired(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		r.mu.Lock()
		now := time.Now()
		for aor, list := range r.contacts {
			var live []*Contact
			for _, c := range list {
				if now.Before(c.ExpiresAt) {
					live = append(live, c)
				} else {
					slog.Info("Registration expired", "aor", aor, "address", c.Address)
				}
			}
			if len(live) == 0 {
				delete(r.contacts, aor)
			} else {
				r.contacts[aor] = live
			}
		}
		r.mu.Unlock()
	}
}

// isWebRTCSDP checks if an SDP body uses WebRTC transport (SAVP/SAVPF)
func isWebRTCSDP(body []byte) bool {
	s := string(body)
	return strings.Contains(s, "RTP/SAVPF") ||
		strings.Contains(s, "RTP/SAVP") ||
		strings.Contains(s, "UDP/TLS/RTP/SAVPF")
}
