package main

import (
	"fmt"
	"log/slog"
	"strings"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

// CRLF-injection checks for every SIP message entering or leaving the SBC.
//
// sipgo's parser splits header lines only on CRLF, so a bare CR or LF inside a
// header line ends up in the header's value. Forwarded as is, a peer that
// accepts bare LF line endings (FreeSWITCH does) reads it as a second header:
// "Subject: x\nX-Comcent-Org: other" becomes an injected header. sipgo v1.4.2
// announced sip.ValidateRequest / sip.ValidateResponse for this, but the
// functions never shipped in a release (up to v1.6.0), so the SBC does the
// same check itself.

func validateRequest(req *sip.Request) error {
	if hasCRLF(req.StartLine()) {
		return fmt.Errorf("invalid CRLF in request line")
	}
	return validateHeaders(req.Headers())
}

func validateResponse(res *sip.Response) error {
	if hasCRLF(res.StartLine()) {
		return fmt.Errorf("invalid CRLF in status line")
	}
	return validateHeaders(res.Headers())
}

func validateHeaders(headers []sip.Header) error {
	for _, h := range headers {
		if hasCRLF(h.Name()) || hasCRLF(h.Value()) {
			return fmt.Errorf("invalid CRLF in %s header", h.Name())
		}
	}
	return nil
}

func hasCRLF(s string) bool {
	return strings.ContainsAny(s, "\r\n")
}

// validateOutgoing is a sipgo client option that refuses to send a request
// carrying CR or LF in its request line or headers. Pass it after any option
// that adds headers (e.g. sipgo.ClientRequestAddVia) so they are checked too.
func validateOutgoing(_ *sipgo.Client, req *sip.Request) error {
	return validateRequest(req)
}

// validateMessages rejects an incoming request with CR or LF in its request
// line or headers before h sees it, and checks every response h sends.
func validateMessages(h sipgo.RequestHandler) sipgo.RequestHandler {
	return func(req *sip.Request, tx sip.ServerTransaction) {
		if err := validateRequest(req); err != nil {
			slog.Warn("Rejecting request with invalid CRLF", "method", req.Method, "source", req.Source(), "error", err)
			if !req.IsAck() {
				tx.Respond(sip.NewResponseFromRequest(req, 400, "Bad Request", nil))
			}
			return
		}
		h(req, &validatingTx{ServerTransaction: tx, req: req})
	}
}

type validatingTx struct {
	sip.ServerTransaction
	req *sip.Request
}

// Respond drops a response with CR or LF in its status line or headers. A final
// response is replaced by a clean 502 so the transaction still completes.
func (t *validatingTx) Respond(res *sip.Response) error {
	err := validateResponse(res)
	if err == nil {
		return t.ServerTransaction.Respond(res)
	}
	slog.Warn("Dropping response with invalid CRLF", "status", res.StatusCode, "callid", t.req.CallID().Value(), "error", err)
	if res.StatusCode >= 200 {
		return t.ServerTransaction.Respond(sip.NewResponseFromRequest(t.req, 502, "Bad Gateway", nil))
	}
	return err
}
