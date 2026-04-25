package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log/slog"
	"sync"
	"time"
)

// certReloader serves a TLS cert from disk and reloads it periodically so
// Let's Encrypt renewals (written by traefik-certs-dumper or similar) take
// effect without an SBC restart.
type certReloader struct {
	certPath, keyPath string
	refreshEvery      time.Duration

	mu          sync.RWMutex
	cert        *tls.Certificate
	refreshedAt time.Time
}

func newCertReloader(certPath, keyPath string) (*certReloader, error) {
	r := &certReloader{
		certPath:     certPath,
		keyPath:      keyPath,
		refreshEvery: 5 * time.Minute,
	}
	if err := r.refresh(); err != nil {
		return nil, fmt.Errorf("initial cert load: %w", err)
	}
	return r, nil
}

// waitForCertReloader retries until the cert files exist (e.g. while
// traefik-certs-dumper is still warming up after first ACME issuance).
func waitForCertReloader(ctx context.Context, certPath, keyPath string) (*certReloader, error) {
	for {
		r, err := newCertReloader(certPath, keyPath)
		if err == nil {
			return r, nil
		}
		slog.Info("Waiting for WSS cert", "certPath", certPath, "error", err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(30 * time.Second):
		}
	}
}

func (r *certReloader) refresh() error {
	cert, err := tls.LoadX509KeyPair(r.certPath, r.keyPath)
	if err != nil {
		return err
	}
	r.mu.Lock()
	r.cert = &cert
	r.refreshedAt = time.Now()
	r.mu.Unlock()
	return nil
}

func (r *certReloader) Get(*tls.ClientHelloInfo) (*tls.Certificate, error) {
	r.mu.RLock()
	stale := time.Since(r.refreshedAt) > r.refreshEvery
	cert := r.cert
	r.mu.RUnlock()

	if !stale {
		return cert, nil
	}
	if err := r.refresh(); err != nil {
		slog.Warn("cert reload failed; serving previous cert", "error", err)
		return cert, nil
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.cert, nil
}
