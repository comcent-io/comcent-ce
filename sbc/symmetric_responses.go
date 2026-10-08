package main

import (
	"strings"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

// symmetricResponses makes h answer a UDP request at the address it came from,
// as if the client's Via carried rport (RFC 3581), like OpenSIPS/Kamailio's
// force_rport(). Without rport, RFC 3261 sends the response to the packet's
// source IP but the port in the Via. Behind a NAT that port is the phone's
// LAN port, not the router's, so the router drops the response and the phone
// can't even register. sipgo fixes the response address when it creates the
// server transaction, before any handler runs, so it is overridden here on
// each response instead.
func symmetricResponses(h sipgo.RequestHandler) sipgo.RequestHandler {
	return func(req *sip.Request, tx sip.ServerTransaction) {
		if isUDP(req.Transport()) && req.Source() != "" {
			tx = &symmetricTx{ServerTransaction: tx, source: req.Source()}
		}
		h(req, tx)
	}
}

type symmetricTx struct {
	sip.ServerTransaction
	source string
}

func (t *symmetricTx) Respond(res *sip.Response) error {
	res.SetDestination(t.source)
	return t.ServerTransaction.Respond(res)
}

func isUDP(transport string) bool {
	return strings.EqualFold(transport, "udp")
}
