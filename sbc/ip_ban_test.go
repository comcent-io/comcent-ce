package main

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/emiago/sipgo/sip"
)

const scannerIP = "192.0.2.66" // TEST-NET-1: public, so nothing exempts it

// testBan is an IPBan of 10 failures in 60 s, banning for 15 min, on a clock
// the test moves by hand.
func testBan(neverBan func(string) bool) (*IPBan, *time.Time) {
	now := time.Date(2026, 10, 9, 5, 0, 0, 0, time.UTC)
	b := newIPBan(10, time.Minute, 15*time.Minute, neverBan)
	b.now = func() time.Time { return now }
	return b, &now
}

func failN(b *IPBan, ip string, n int) {
	for range n {
		b.Fail(ip)
	}
}

func TestBanAfterMaxFailuresInWindowAndExpiry(t *testing.T) {
	b, now := testBan(func(string) bool { return false })

	failN(b, scannerIP, 9)
	if b.Banned(scannerIP) {
		t.Fatal("banned after 9 failures, want 10")
	}
	b.Fail(scannerIP)
	if !b.Banned(scannerIP) {
		t.Fatal("not banned after 10 failures")
	}
	if b.Banned("192.0.2.67") {
		t.Fatal("another IP is banned too")
	}

	*now = now.Add(15*time.Minute - time.Second)
	if !b.Banned(scannerIP) {
		t.Fatal("ban ended before 15 min")
	}
	*now = now.Add(time.Second)
	if b.Banned(scannerIP) {
		t.Fatal("still banned after 15 min")
	}

	// A repeat offender is banned twice as long.
	failN(b, scannerIP, 10)
	*now = now.Add(30*time.Minute - time.Second)
	if !b.Banned(scannerIP) {
		t.Fatal("second ban ended before 30 min")
	}
	*now = now.Add(time.Second)
	if b.Banned(scannerIP) {
		t.Fatal("still banned after 30 min")
	}
}

func TestFailuresSpreadOverWindowsDontBan(t *testing.T) {
	b, now := testBan(func(string) bool { return false })
	for range 5 {
		failN(b, scannerIP, 9)
		*now = now.Add(time.Minute)
	}
	if b.Banned(scannerIP) {
		t.Fatal("banned for 9 failures a minute, want only 10 within a minute")
	}
}

func TestBanTimeDoublingIsCapped(t *testing.T) {
	b, now := testBan(func(string) bool { return false })
	for range 12 {
		failN(b, scannerIP, 10)
		*now = now.Add(maxBanTime)
	}
	failN(b, scannerIP, 10)
	*now = now.Add(maxBanTime)
	if b.Banned(scannerIP) {
		t.Fatalf("banned for longer than %v", maxBanTime)
	}
}

func TestZeroSettingTurnsBanningOff(t *testing.T) {
	for _, b := range []*IPBan{
		newIPBan(0, time.Minute, time.Minute, nil),
		newIPBan(10, 0, time.Minute, nil),
		newIPBan(10, time.Minute, 0, nil),
	} {
		if b != nil {
			t.Fatalf("got %+v, want banning off", b)
		}
		failN(b, scannerIP, 100) // a nil IPBan must be safe to use
		if b.Banned(scannerIP) {
			t.Fatal("banned with banning off")
		}
	}
}

func TestTrunkPrivateAndRegisteredSourcesAreNeverBanned(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"inboundIps":["203.0.113.0/28"],"outboundContact":"trunk.example.com:5060"}`))
	}))
	defer srv.Close()

	reg := newRegistrar()
	reg.Register("alice@northwind.sip.example.com", &Contact{Address: "198.51.100.7:40312", ExpiresAt: time.Now().Add(time.Minute)})
	reg.Register("lapsed@northwind.sip.example.com", &Contact{Address: "198.51.100.8:5060", ExpiresAt: time.Now().Add(-time.Second)})
	disp := newDispatcher(Config{})
	disp.AddTarget("sip:198.51.100.20:5070")
	p := &Proxy{reg: reg, dispatcher: disp, api: &InternalAPI{baseURL: srv.URL, client: srv.Client()}}
	if _, err := p.api.GetSIPTrunk("15550100"); err != nil {
		t.Fatal(err)
	}
	b, _ := testBan(p.neverBan)

	for _, ip := range []string{
		"203.0.113.9",    // a trunk's inbound range
		"198.51.100.7",   // registered (from another port, too)
		"198.51.100.20",  // FreeSWITCH
		"172.29.17.20",   // the docker network the e2e stack runs on
		"10.200.0.10",    // behind the e2e NAT router
		"127.0.0.1",      // loopback
		"fd00::1",        // private IPv6
		"not-an-address", // unparseable: never guess
	} {
		failN(b, ip, 50)
		if b.Banned(ip) {
			t.Errorf("%s was banned", ip)
		}
	}
	for _, ip := range []string{"203.0.113.16", "198.51.100.8", scannerIP} {
		failN(b, ip, 10)
		if !b.Banned(ip) {
			t.Errorf("%s (outside the trunk range, lapsed registration, scanner) was not banned", ip)
		}
	}
}

func TestDropBannedNeverReachesTheHandler(t *testing.T) {
	b, _ := testBan(func(string) bool { return false })
	failN(b, scannerIP, 10)
	p := &Proxy{ban: b}

	var handled []string
	h := p.dropBanned(func(req *sip.Request, tx sip.ServerTransaction) {
		handled = append(handled, req.Source())
	})
	for _, src := range []string{scannerIP + ":5060", "192.0.2.67:5060"} {
		req := sip.NewRequest(sip.INVITE, sip.Uri{User: "7330015108929741", Host: "192.0.2.1"})
		req.SetSource(src)
		h(req, nil)
	}
	if len(handled) != 1 || handled[0] != "192.0.2.67:5060" {
		t.Fatalf("handler saw %v, want only the unbanned source", handled)
	}
}

func TestOnlyFailedCredentialsCountAgainstASource(t *testing.T) {
	cases := []struct {
		name      string
		withAuth  bool
		lookupErr error
		counted   bool
	}{
		{"first request, challenged without credentials", false, nil, false},
		{"wrong password", true, nil, true},
		{"unknown user", true, errNotFound, true},
		{"internal API unreachable", true, errors.New("connection refused"), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			b, _ := testBan(func(string) bool { return false })
			p := &Proxy{ban: b}
			req := sip.NewRequest(sip.REGISTER, sip.Uri{Host: "northwind.sip.example.com"})
			req.SetSource(scannerIP + ":5060")
			if tc.withAuth {
				req.AppendHeader(sip.NewHeader("Authorization", `Digest username="101", response="00"`))
			}
			for range 10 {
				p.failedAuth(req, tc.lookupErr)
			}
			if got := b.Banned(scannerIP); got != tc.counted {
				t.Fatalf("banned = %v, want %v", got, tc.counted)
			}
		})
	}
}

func TestUnknownTrunkNumberIsCachedForAMinute(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.Error(w, "Number not found", http.StatusNotFound)
	}))
	defer srv.Close()
	api := &InternalAPI{baseURL: srv.URL, client: srv.Client()}

	for range 3 {
		if _, err := api.GetSIPTrunk("7330015108929741"); !errors.Is(err, errNotFound) {
			t.Fatalf("err = %v, want errNotFound", err)
		}
	}
	if n := hits.Load(); n != 1 {
		t.Fatalf("server asked %d times, want once", n)
	}

	v, _ := api.trunkCache.Load("7330015108929741")
	entry := v.(*trunkCacheEntry)
	if ttl := time.Until(entry.expiresAt); ttl > unknownTrunkTTL || ttl < unknownTrunkTTL-5*time.Second {
		t.Fatalf("unknown number cached for %v, want about %v", ttl, unknownTrunkTTL)
	}
	entry.expiresAt = time.Now().Add(-time.Second)
	if _, err := api.GetSIPTrunk("7330015108929741"); !errors.Is(err, errNotFound) {
		t.Fatalf("err = %v, want errNotFound", err)
	}
	if n := hits.Load(); n != 2 {
		t.Fatalf("server asked %d times after expiry, want twice", n)
	}
}

func TestServerErrorIsNotCachedOrCountedAsNotFound(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()
	api := &InternalAPI{baseURL: srv.URL, client: srv.Client()}

	for range 2 {
		if _, err := api.GetSIPTrunk("15550100"); err == nil || errors.Is(err, errNotFound) {
			t.Fatalf("err = %v, want a non-404 error", err)
		}
	}
	if n := hits.Load(); n != 2 {
		t.Fatalf("server asked %d times, want every time", n)
	}
}

func TestAckMissedIsLoggedAtDebug(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(quietScannerLogs{slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo})}).With("caller", "TransactionLayer")
	log.Warn("ACK missed", "callid", "abc")
	log.Warn("Something else")
	if out := buf.String(); strings.Contains(out, "ACK missed") || !strings.Contains(out, "Something else") {
		t.Fatalf("log output %q, want only the other warning", out)
	}

	buf.Reset()
	debug := slog.New(quietScannerLogs{slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug})})
	debug.Log(context.Background(), slog.LevelWarn, "ACK missed")
	if out := buf.String(); !strings.Contains(out, "level=DEBUG") {
		t.Fatalf("log output %q, want it at DEBUG", out)
	}
}

func TestRejectedCallsExpire(t *testing.T) {
	var r rejectedCalls
	invite := sip.NewRequest(sip.INVITE, sip.Uri{User: "7330015108929741", Host: "192.0.2.1"})
	callID := sip.CallIDHeader("scan-1")
	invite.AppendHeader(&callID)
	register := sip.NewRequest(sip.REGISTER, sip.Uri{Host: "192.0.2.1"})
	regID := sip.CallIDHeader("reg-1")
	register.AppendHeader(&regID)

	r.add(invite)
	r.add(register)
	if !r.has("scan-1") || r.has("reg-1") {
		t.Fatal("want only the rejected INVITE remembered")
	}
	r.ids["scan-1"] = time.Now().Add(-rejectedCallTTL)
	if r.has("scan-1") {
		t.Fatal("rejected call remembered past its TTL")
	}
}
