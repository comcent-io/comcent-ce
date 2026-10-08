package main

import (
	"testing"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

func TestBehindNAT(t *testing.T) {
	cases := []struct {
		contact, source string
		want            bool
	}{
		{"sip:alice@203.0.113.7:5060", "203.0.113.7:5060", false},
		{"sip:alice@203.0.113.7", "203.0.113.7:5060", false}, // default port
		{"sip:alice@192.168.1.20:5060;transport=udp", "203.0.113.7:40312", true},
		{"sip:alice@203.0.113.7:5060", "203.0.113.7:40312", true}, // port rewritten
		{"sip:alice@phone.example.com:5060", "203.0.113.7:5060", true},
		{"not a uri", "203.0.113.7:5060", true},
	}
	for _, c := range cases {
		if got := behindNAT(c.contact, c.source); got != c.want {
			t.Errorf("behindNAT(%q, %q) = %v, want %v", c.contact, c.source, got, c.want)
		}
	}
}

func TestNATContactsAreTheLiveNATedOnes(t *testing.T) {
	now := time.Now()
	r := newRegistrar()
	r.Register("nated@acme.example.com", &Contact{URI: "sip:nated@192.168.1.20:5060", Address: "203.0.113.7:40312", NAT: true, ExpiresAt: now.Add(time.Minute)})
	r.Register("direct@acme.example.com", &Contact{URI: "sip:direct@203.0.113.8:5060", Address: "203.0.113.8:5060", ExpiresAt: now.Add(time.Minute)})
	r.Register("expired@acme.example.com", &Contact{URI: "sip:expired@192.168.1.21:5060", Address: "203.0.113.9:40313", NAT: true, ExpiresAt: now.Add(-time.Second)})

	got := r.natContacts(now)
	if len(got) != 1 || got[0].aor != "nated@acme.example.com" || got[0].address != "203.0.113.7:40312" {
		t.Fatalf("natContacts = %+v, want only the live NATed contact", got)
	}
	if got[0].uri.Host != "192.168.1.20" {
		t.Errorf("ping URI host = %q, want the Contact's", got[0].uri.Host)
	}
}

func TestMissedPingsUnregisterTheContactAfterMax(t *testing.T) {
	r := newRegistrar()
	aor := "alice@acme.example.com"
	r.Register(aor, &Contact{Address: "203.0.113.7:40312", NAT: true, ExpiresAt: time.Now().Add(time.Minute)})

	if r.pingMissed(aor, "203.0.113.7:40312", 3) || r.pingMissed(aor, "203.0.113.7:40312", 3) {
		t.Fatal("contact dropped before 3 missed pings")
	}
	// An answer in between starts the count again.
	r.pingAnswered(aor, "203.0.113.7:40312")
	r.pingMissed(aor, "203.0.113.7:40312", 3)
	r.pingMissed(aor, "203.0.113.7:40312", 3)
	if !r.IsRegistered(aor) {
		t.Fatal("an answered ping did not reset the count")
	}

	if !r.pingMissed(aor, "203.0.113.7:40312", 3) {
		t.Fatal("third missed ping in a row did not report the AOR emptied")
	}
	if r.IsRegistered(aor) {
		t.Fatal("contact still registered after 3 missed pings")
	}
}

func TestMissedPingsKeepTheAORsOtherContacts(t *testing.T) {
	r := newRegistrar()
	aor := "alice@acme.example.com"
	r.Register(aor, &Contact{Address: "203.0.113.7:40312", NAT: true, ExpiresAt: time.Now().Add(time.Minute)})
	r.Register(aor, &Contact{Address: "203.0.113.8:5060", ExpiresAt: time.Now().Add(time.Minute)})

	if r.pingMissed(aor, "203.0.113.7:40312", 1) {
		t.Fatal("AOR reported emptied while another contact is registered")
	}
	if got := r.LookupAll(aor); len(got) != 1 || got[0].Address != "203.0.113.8:5060" {
		t.Fatalf("contacts left = %+v, want only the other one", got)
	}
}

func TestPingForAGoneContactIsIgnored(t *testing.T) {
	r := newRegistrar()
	if r.pingMissed("nobody@acme.example.com", "203.0.113.7:40312", 1) {
		t.Fatal("missed ping for an unknown contact reported an emptied AOR")
	}
	r.pingAnswered("nobody@acme.example.com", "203.0.113.7:40312")
}

// With a client that pins its local address (as the public client does), the
// ping must still leave through the listener socket: sipgo's default build
// would set Laddr and make the transport bind :5060 again, which fails.
func TestPingBuildLeavesTheSocketToTheTransport(t *testing.T) {
	ua, err := sipgo.NewUA()
	if err != nil {
		t.Fatal(err)
	}
	defer ua.Close()
	client, err := sipgo.NewClient(ua,
		sipgo.WithClientHostname("203.0.113.1"),
		sipgo.WithClientPort(5060),
		sipgo.WithClientConnectionAddr("0.0.0.0:5060"),
	)
	if err != nil {
		t.Fatal(err)
	}

	req := sip.NewRequest(sip.OPTIONS, sip.Uri{User: "alice", Host: "192.168.1.20", Port: 5060})
	if err := buildFromListener(client, req); err != nil {
		t.Fatal(err)
	}
	if req.Laddr.IP != nil || req.Laddr.Port != 0 {
		t.Errorf("Laddr = %v, want unset", req.Laddr)
	}
	if req.Via() == nil || req.From() == nil || req.To() == nil || req.CallID() == nil || req.CSeq() == nil {
		t.Errorf("missing headers in\n%s", req)
	}
}

type recordingTx struct {
	sip.ServerTransaction
	sent *sip.Response
}

func (t *recordingTx) Respond(res *sip.Response) error {
	t.sent = res
	return nil
}

func TestSymmetricResponsesAnswerTheSourcePort(t *testing.T) {
	req := sip.NewRequest(sip.REGISTER, sip.Uri{Host: "acme.example.com"})
	req.AppendHeader(sip.NewHeader("Via", "SIP/2.0/UDP 192.168.1.20:5060;branch=z9hG4bK1"))
	req.SetTransport("UDP")
	req.SetSource("203.0.113.7:40312")

	inner := &recordingTx{}
	symmetricResponses(func(req *sip.Request, tx sip.ServerTransaction) {
		tx.Respond(sip.NewResponseFromRequest(req, 401, "Unauthorized", nil))
	})(req, inner)

	if inner.sent == nil {
		t.Fatal("no response sent")
	}
	if got := inner.sent.Destination(); got != "203.0.113.7:40312" {
		t.Errorf("response sent to %s, want the request's source 203.0.113.7:40312", got)
	}
}
