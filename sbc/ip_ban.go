package main

import (
	"context"
	"log/slog"
	"net"
	"sync"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

// Internet SIP scanners send us an INVITE or REGISTER every second or so,
// forever, and every one of them used to cost a 403 and an internal API call.
// Like fail2ban (or OpenSIPS/Kamailio pike), the SBC counts failures per source
// IP: 403s, and digest auth that fails after a challenge. An IP that fails
// BAN_FAILURES times within BAN_WINDOW is dropped silently for BAN_TIME, twice
// as long on each repeat, so the scanner gets no answer at all.

// maxBanTime caps the doubling of a repeat offender's ban.
const maxBanTime = 24 * time.Hour

type ipBanRecord struct {
	failures    int
	windowStart time.Time
	bans        int // bans so far, for doubling; forgotten after maxBanTime of quiet
	bannedUntil time.Time
}

type IPBan struct {
	maxFailures int
	window      time.Duration
	banTime     time.Duration
	// neverBan reports a source that must never be counted: a trunk, our own
	// network, or a registered phone.
	neverBan func(ip string) bool
	now      func() time.Time

	mu        sync.Mutex
	sources   map[string]*ipBanRecord
	lastSweep time.Time
}

// newIPBan returns nil, which bans nothing, when any setting is 0.
func newIPBan(maxFailures int, window, banTime time.Duration, neverBan func(ip string) bool) *IPBan {
	if maxFailures <= 0 || window <= 0 || banTime <= 0 {
		return nil
	}
	return &IPBan{
		maxFailures: maxFailures,
		window:      window,
		banTime:     banTime,
		neverBan:    neverBan,
		now:         time.Now,
		sources:     make(map[string]*ipBanRecord),
	}
}

// Banned reports whether requests from ip are currently dropped.
func (b *IPBan) Banned(ip string) bool {
	if b == nil {
		return false
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	r, ok := b.sources[ip]
	return ok && b.now().Before(r.bannedUntil)
}

// Fail records one failed request from ip and bans it once it reaches the
// limit within the window.
func (b *IPBan) Fail(ip string) {
	if b == nil || ip == "" || b.neverBan(ip) {
		return
	}
	now := b.now()
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sweep(now)

	r, ok := b.sources[ip]
	if !ok {
		r = &ipBanRecord{}
		b.sources[ip] = r
	}
	if now.Before(r.bannedUntil) {
		return
	}
	if r.bans > 0 && now.Sub(r.bannedUntil) >= maxBanTime {
		r.bans = 0
	}
	if now.Sub(r.windowStart) >= b.window {
		r.failures, r.windowStart = 0, now
	}
	r.failures++
	if r.failures < b.maxFailures {
		return
	}

	ban := b.banTime
	for i := 0; i < r.bans && ban < maxBanTime; i++ {
		ban *= 2
	}
	ban = min(ban, maxBanTime)
	r.bans++
	r.bannedUntil = now.Add(ban)
	slog.Info("Banned SIP source", "ip", ip, "failures", r.failures, "until", r.bannedUntil.UTC().Format(time.RFC3339))
	r.failures = 0
}

// sweep forgets, at most once a window, the sources with nothing left to
// remember: no failures in the current window, no ban, and quiet long enough
// that a new ban wouldn't double. Called with mu held.
func (b *IPBan) sweep(now time.Time) {
	if now.Sub(b.lastSweep) < b.window {
		return
	}
	b.lastSweep = now
	for ip, r := range b.sources {
		windowOver := now.Sub(r.windowStart) >= b.window
		if windowOver && (r.bans == 0 || now.Sub(r.bannedUntil) >= maxBanTime) {
			delete(b.sources, ip)
		}
	}
}

// neverBan reports a source the SBC must keep answering however often it
// fails: our own private network (FreeSWITCH, Traefik, the e2e containers), a
// configured trunk's inbound IP, and an IP that holds a live registration.
func (p *Proxy) neverBan(ip string) bool {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return true
	}
	if parsed.IsPrivate() || parsed.IsLoopback() || parsed.IsLinkLocalUnicast() || parsed.IsUnspecified() {
		return true
	}
	return p.dispatcher.IsFromFS(ip) || p.api.IsTrunkIP(ip) || p.reg.HasSourceIP(ip)
}

// failed counts a rejected request against its source IP.
func (p *Proxy) failed(req *sip.Request) {
	p.ban.Fail(sourceIPFromRequest(req))
}

// dropBanned drops every request from a banned source without answering it.
func (p *Proxy) dropBanned(h sipgo.RequestHandler) sipgo.RequestHandler {
	return func(req *sip.Request, tx sip.ServerTransaction) {
		if ip := sourceIPFromRequest(req); p.ban.Banned(ip) {
			slog.Debug("Dropped request from banned source", "ip", ip, "method", req.Method)
			return
		}
		h(req, tx)
	}
}

// rejectedCalls remembers for a minute the Call-IDs of INVITEs the SBC turned
// away itself, so the ACK to that rejection (no dialog to forward it to) can
// be logged quietly; an unmatched ACK for any other call still logs at Info.
type rejectedCalls struct {
	mu        sync.Mutex
	ids       map[string]time.Time
	lastSweep time.Time
}

const rejectedCallTTL = time.Minute

func (r *rejectedCalls) add(req *sip.Request) {
	if req.Method != sip.INVITE || req.CallID() == nil {
		return
	}
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.ids == nil {
		r.ids = make(map[string]time.Time)
	}
	if now.Sub(r.lastSweep) >= rejectedCallTTL {
		r.lastSweep = now
		for id, at := range r.ids {
			if now.Sub(at) >= rejectedCallTTL {
				delete(r.ids, id)
			}
		}
	}
	r.ids[req.CallID().Value()] = now
}

func (r *rejectedCalls) has(callID string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	at, ok := r.ids[callID]
	return ok && time.Since(at) < rejectedCallTTL
}

// quietScannerLogs is the log handler for sipgo. Its "ACK missed" warning
// fires when an INVITE we answered with a non-2xx response gets its ACK after
// the transaction is gone, which is what scanners do on every attempt; it is
// logged at Debug instead.
type quietScannerLogs struct{ slog.Handler }

func (h quietScannerLogs) Handle(ctx context.Context, r slog.Record) error {
	if r.Message == "ACK missed" {
		r.Level = slog.LevelDebug
		if !h.Handler.Enabled(ctx, r.Level) {
			return nil
		}
	}
	return h.Handler.Handle(ctx, r)
}

func (h quietScannerLogs) WithAttrs(attrs []slog.Attr) slog.Handler {
	return quietScannerLogs{h.Handler.WithAttrs(attrs)}
}

func (h quietScannerLogs) WithGroup(name string) slog.Handler {
	return quietScannerLogs{h.Handler.WithGroup(name)}
}
