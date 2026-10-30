package main

import (
	"testing"

	"github.com/emiago/sipgo/sip"
)

// sipgo splits header lines only on CRLF, so a bare LF stays inside a header
// value. Forwarded to FreeSWITCH, which accepts bare LF, it would become a
// second, injected header. The SBC must answer 400 and never run the handler.
func TestValidateMessagesRejectsBareLFInHeader(t *testing.T) {
	raw := "INVITE sip:1000@acme.example.com SIP/2.0\r\n" +
		"Via: SIP/2.0/UDP 203.0.113.7:5060;branch=z9hG4bK1\r\n" +
		"From: <sip:caller@example.com>;tag=1\r\n" +
		"To: <sip:1000@acme.example.com>\r\n" +
		"Call-ID: crlf-test\r\n" +
		"CSeq: 1 INVITE\r\n" +
		"Subject: hello\nX-Comcent-Org: contoso\r\n" +
		"Content-Length: 0\r\n\r\n"
	msg, err := sip.ParseMessage([]byte(raw))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	req := msg.(*sip.Request)

	tx := &recordingTx{}
	called := false
	validateMessages(func(*sip.Request, sip.ServerTransaction) { called = true })(req, tx)

	if called {
		t.Error("handler ran for a request with a bare LF in a header")
	}
	if tx.sent == nil || tx.sent.StatusCode != 400 {
		t.Errorf("response = %v, want 400 Bad Request", tx.sent)
	}
}

func TestValidateMessagesPassesCleanRequest(t *testing.T) {
	req := sip.NewRequest(sip.OPTIONS, sip.Uri{Host: "acme.example.com"})
	req.AppendHeader(sip.NewHeader("Via", "SIP/2.0/UDP 203.0.113.7:5060;branch=z9hG4bK1"))
	req.AppendHeader(sip.NewHeader("Call-ID", "clean"))

	tx := &recordingTx{}
	validateMessages(func(req *sip.Request, tx sip.ServerTransaction) {
		tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
	})(req, tx)

	if tx.sent == nil || tx.sent.StatusCode != 200 {
		t.Errorf("response = %v, want 200 OK", tx.sent)
	}
}

// A final response relayed from a peer with an injected header is replaced by a
// clean 502, so the caller's transaction still completes.
func TestValidateMessagesReplacesInjectedFinalResponse(t *testing.T) {
	req := sip.NewRequest(sip.INVITE, sip.Uri{Host: "acme.example.com"})
	req.AppendHeader(sip.NewHeader("Via", "SIP/2.0/UDP 203.0.113.7:5060;branch=z9hG4bK1"))
	req.AppendHeader(sip.NewHeader("Call-ID", "relay"))

	tx := &recordingTx{}
	validateMessages(func(req *sip.Request, tx sip.ServerTransaction) {
		res := sip.NewResponseFromRequest(req, 200, "OK", nil)
		res.AppendHeader(sip.NewHeader("Subject", "x\r\nContent-Length: 0"))
		tx.Respond(res)
	})(req, tx)

	if tx.sent == nil || tx.sent.StatusCode != 502 {
		t.Errorf("response = %v, want 502 Bad Gateway", tx.sent)
	}
}

func TestValidateOutgoingRejectsInjectedHeader(t *testing.T) {
	req := sip.NewRequest(sip.BYE, sip.Uri{Host: "acme.example.com"})
	req.AppendHeader(sip.NewHeader("X-Reason", "done\r\nX-Comcent-Org: contoso"))
	if err := validateOutgoing(nil, req); err == nil {
		t.Error("validateOutgoing accepted a header with CRLF")
	}

	clean := sip.NewRequest(sip.BYE, sip.Uri{Host: "acme.example.com"})
	clean.AppendHeader(sip.NewHeader("X-Reason", "done"))
	if err := validateOutgoing(nil, clean); err != nil {
		t.Errorf("validateOutgoing rejected a clean request: %v", err)
	}
}
