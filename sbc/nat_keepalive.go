package main

import (
	"context"
	"log/slog"
	"net"
	"strconv"
	"time"

	"github.com/emiago/sipgo/sip"
)

// A phone behind a home router registers from the router's address, and the
// router keeps that UDP mapping open only while traffic flows: after 30 s to a
// few minutes of silence it forgets it, and the next INVITE we send to the
// registered address is dropped there. The phone then misses every call until
// it registers again. Like OpenSIPS/Kamailio nathelper with sipping, we send
// each such contact an OPTIONS every NAT_PING_INTERVAL from the socket its
// REGISTER arrived on, which keeps the mapping open, and drop a contact that
// stops answering.

// behindNAT reports whether a UDP contact registered from somewhere other
// than the address in its Contact: a router rewrote the source on the way.
// Like nathelper's nat_uac_test, it doesn't try to tell why.
func behindNAT(contactURI, source string) bool {
	var uri sip.Uri
	if err := sip.ParseUri(contactURI, &uri); err != nil {
		return true
	}
	host, port, err := net.SplitHostPort(source)
	if err != nil {
		return true
	}
	contactPort := uri.Port
	if contactPort == 0 {
		contactPort = 5060
	}
	return uri.Host != host || strconv.Itoa(contactPort) != port
}

// natKeepalive pings every NATed UDP contact once per interval until ctx ends.
func (p *Proxy) natKeepalive(ctx context.Context, interval time.Duration, maxMissed int) {
	slog.Info("NAT keepalive", "interval", interval, "maxMissed", maxMissed)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		for _, c := range p.reg.natContacts(time.Now()) {
			go p.pingContact(ctx, c, interval, maxMissed)
		}
	}
}

// pingContact sends one OPTIONS to c and records whether it was answered.
// Any response counts: the phone heard us, so the mapping is open. Waiting at
// most one interval keeps pings to the same contact from overlapping.
func (p *Proxy) pingContact(ctx context.Context, c natContact, wait time.Duration, maxMissed int) {
	req := sip.NewRequest(sip.OPTIONS, c.uri)
	req.SetDestination(c.address)
	req.AppendHeader(sip.NewHeader("Content-Length", "0"))

	ctx, cancel := context.WithTimeout(ctx, wait)
	defer cancel()
	if _, err := p.publicClient.Do(ctx, req); err == nil {
		p.reg.pingAnswered(c.aor, c.address)
		return
	}

	if p.reg.pingMissed(c.aor, c.address, maxMissed) {
		slog.Info("NAT keepalive: contact stopped answering, unregistered",
			"aor", c.aor, "address", c.address, "missed", maxMissed)
		p.registrationLapsed(c.aor)
	}
}

// natContact is a snapshot of a contact to ping, taken under the registrar's
// lock so the pinging goroutine doesn't share the Contact.
type natContact struct {
	aor     string
	uri     sip.Uri
	address string
}

// natContacts returns the live UDP contacts registered from behind a NAT.
func (r *Registrar) natContacts(now time.Time) []natContact {
	r.mu.RLock()
	defer r.mu.RUnlock()
	var out []natContact
	for aor, list := range r.contacts {
		for _, c := range list {
			if !c.NAT || !now.Before(c.ExpiresAt) {
				continue
			}
			var uri sip.Uri
			if err := sip.ParseUri(c.URI, &uri); err != nil {
				continue
			}
			out = append(out, natContact{aor: aor, uri: uri, address: c.Address})
		}
	}
	return out
}

// pingAnswered clears the contact's missed pings.
func (r *Registrar) pingAnswered(aor, address string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if c := r.find(aor, address); c != nil {
		c.missedPings = 0
	}
}

// pingMissed counts a missed ping and, at maxMissed in a row, removes the
// contact. It reports whether that left the AOR with no contact at all.
func (r *Registrar) pingMissed(aor, address string, maxMissed int) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	c := r.find(aor, address)
	if c == nil {
		return false
	}
	c.missedPings++
	if c.missedPings < maxMissed {
		return false
	}
	list := r.contacts[aor]
	kept := list[:0]
	for _, other := range list {
		if other != c {
			kept = append(kept, other)
		}
	}
	if len(kept) == 0 {
		delete(r.contacts, aor)
		return true
	}
	r.contacts[aor] = kept
	return false
}

// find returns aor's contact registered from address. Callers hold r.mu.
func (r *Registrar) find(aor, address string) *Contact {
	for _, c := range r.contacts[aor] {
		if c.Address == address {
			return c
		}
	}
	return nil
}
