package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
)

// callState tracks an active call for in-dialog request routing.
// In proxy mode there is one dialog end-to-end; the SBC stays in the
// path via double Record-Route and needs to know where each side lives.
type callState struct {
	fsAddr      string   // FS address (ip:port) handling this call
	fsURI       string   // FS dialog target/contact URI
	userAddr    string   // user's registered contact address (ip:port)
	userURI     string   // user's logical Contact URI
	userAORs    []string // comcent users pinned to this FS leg
	isWebRTC    bool     // user is a WebRTC agent (needs ws transport)
	spoofedUser string   // spoofed caller cached against the real SIP trunk
}

type Proxy struct {
	publicClient  *sipgo.Client // for external SIP (trunks, agents)
	privateClient *sipgo.Client // for internal FS communication
	reg           *Registrar
	api           *InternalAPI
	dispatcher    *Dispatcher
	cfg           Config

	// Active call tracking for in-dialog routing
	callsMu sync.RWMutex
	calls   map[string]*callState // Call-ID → state

	// Active INVITE transactions for CANCEL propagation
	activeTx sync.Map // Call-ID → *activeTx

	// Spoofed trunk number cache (original From for auth challenges)
	spoofCache sync.Map

	// User → FreeSWITCH stickiness used while calls are active.
	affinityMu sync.RWMutex
	affinity   map[string]map[string]string // user AOR → call-id → fsAddr
}

type activeTxEntry struct {
	tx     sip.ClientTransaction
	req    *sip.Request // the forwarded INVITE (needed to build CANCEL)
	client *sipgo.Client
}

func newProxy(publicClient, privateClient *sipgo.Client, reg *Registrar, api *InternalAPI, disp *Dispatcher, cfg Config) *Proxy {
	return &Proxy{
		publicClient:  publicClient,
		privateClient: privateClient,
		reg:           reg,
		api:           api,
		dispatcher:    disp,
		cfg:           cfg,
		calls:         make(map[string]*callState),
		affinity:      make(map[string]map[string]string),
	}
}

// ---------------------------------------------------------------------------
// REGISTER
// ---------------------------------------------------------------------------

func (p *Proxy) handleRegister(req *sip.Request, tx sip.ServerTransaction) {
	fromURI := req.From()
	if fromURI == nil {
		tx.Respond(sip.NewResponseFromRequest(req, 400, "Bad Request", nil))
		return
	}

	user := fromURI.Address.User
	domain := fromURI.Address.Host
	aor := user + "@" + domain

	if !strings.HasSuffix(domain, p.cfg.SIPUserRootDomain) {
		tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return
	}

	password, err := p.api.GetUserPassword(user, domain)
	if err != nil || password == "" {
		slog.Info("No password, sending challenge", "user", user, "error", err)
		sendAuthChallenge(tx, req, domain)
		return
	}

	if !validateDigestAuth(req, password) {
		authHeader := req.GetHeader("Authorization")
		if authHeader == nil {
			slog.Info("No auth header, sending challenge", "user", user)
		}
		sendAuthChallenge(tx, req, domain)
		return
	}

	expires := 300
	if expiresHeader := req.GetHeader("Expires"); expiresHeader != nil {
		if v, err := strconv.Atoi(expiresHeader.Value()); err == nil {
			expires = v
		}
	}

	contactHeader := req.GetHeader("Contact")

	// RFC 3261: an `expires` parameter on the Contact header takes precedence
	// over the Expires header. SIP.js (and most WS clients) only set the param.
	if contactHeader != nil {
		if v, ok := contactExpiresParam(contactHeader.Value()); ok {
			expires = v
		}
	}

	// Contact: * with Expires: 0 → unregister all contacts for this AOR
	if contactHeader != nil && contactHeader.Value() == "*" && expires == 0 {
		p.reg.Unregister(aor)
		subdomain := strings.Split(domain, ".")[0]
		go p.api.UpdateUserPresence(subdomain, "unregistered", user)
		tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
		return
	}

	// Expires: 0 with a specific contact → unregister just that contact
	if expires == 0 {
		sourceAddr := req.Source()
		p.reg.UnregisterContact(aor, sourceAddr)
		if !p.reg.IsRegistered(aor) {
			subdomain := strings.Split(domain, ".")[0]
			go p.api.UpdateUserPresence(subdomain, "unregistered", user)
		}
		tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
		return
	}

	sourceAddr := req.Source()
	transport := req.Transport()
	isWebRTC := transport == "ws" || transport == "wss" || transport == "WS" || transport == "WSS"

	contactURI := "sip:" + aor
	if contactHeader != nil {
		contactURI = extractContactURI(contactHeader.Value(), contactURI)
	}

	p.reg.Register(aor, &Contact{
		URI:       contactURI,
		Address:   sourceAddr,
		Transport: transport,
		IsWebRTC:  isWebRTC,
		ExpiresAt: time.Now().Add(time.Duration(expires) * time.Second),
	})

	subdomain := strings.Split(domain, ".")[0]
	go p.api.UpdateUserPresence(subdomain, "registered", user)

	resp := sip.NewResponseFromRequest(req, 200, "OK", nil)
	if contactHeader != nil {
		resp.AppendHeader(sip.NewHeader("Contact", contactHeader.Value()))
	} else {
		resp.AppendHeader(sip.NewHeader("Contact", "<"+contactURI+">"))
	}
	resp.AppendHeader(sip.NewHeader("Expires", strconv.Itoa(expires)))
	tx.Respond(resp)
}

// ---------------------------------------------------------------------------
// INVITE routing
// ---------------------------------------------------------------------------

func (p *Proxy) handleInvite(req *sip.Request, tx sip.ServerTransaction) {
	if tooManyHops(req) {
		tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
		return
	}

	// In-dialog re-INVITE (has To tag) → relay to other side
	if toTag, _ := req.To().Params.Get("tag"); toTag != "" {
		p.relayInDialog(req, tx)
		return
	}

	sourceIP := sourceIPFromRequest(req)
	isFS := p.dispatcher.IsFromFS(sourceIP)
	slog.Debug("INVITE routing", "sourceIP", sourceIP, "isFS", isFS,
		"from", req.From().Address.User, "to", req.To().Address.User)

	if isFS {
		p.handleInviteFromFS(req, tx)
	} else {
		p.handleInviteToFS(req, tx, sourceIP)
	}
}

// ---------------------------------------------------------------------------
// External caller/trunk → FS
// ---------------------------------------------------------------------------

func (p *Proxy) handleInviteToFS(req *sip.Request, tx sip.ServerTransaction, sourceIP string) {
	if !p.authenticateExternalRequest(req, tx, sourceIP) {
		return
	}

	callID := req.CallID().Value()
	userAORs := comcentUsersForRequest(req, p.cfg.SIPUserRootDomain)

	target, ok := p.selectTargetForUsers(userAORs)
	if !ok {
		tx.Respond(sip.NewResponseFromRequest(req, 503, "Service Unavailable", nil))
		return
	}
	fsAddr := stripSIPPrefix(target)
	slog.Info("Proxy: caller→FS", "from", req.From().Address.User, "to", req.To().Address.User, "fs", fsAddr)

	p.saveAffinity(callID, fsAddr, userAORs)
	established := false
	defer func() {
		if !established {
			p.deleteAffinity(callID, userAORs)
		}
	}()

	// 100 Trying (locally generated, not forwarded)
	tx.Respond(sip.NewResponseFromRequest(req, 100, "Trying", nil))

	// Build forwarded INVITE
	fwdReq, ok := p.buildForwardRequest(req)
	if !ok {
		tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
		return
	}
	fwdReq.SetDestination(fsAddr)
	fwdReq.SetTransport("udp")

	// Double Record-Route: outgoing interface first (private), then incoming (public)
	p.addRecordRoute(fwdReq, "to_fs")

	// Forward via private client (SBC→FS link)
	clientTx, err := p.privateClient.TransactionRequest(context.Background(), fwdReq, sipgo.ClientRequestAddVia)
	if err != nil {
		slog.Error("Failed to forward INVITE to FS", "error", err)
		tx.Respond(sip.NewResponseFromRequest(req, 502, "Bad Gateway", nil))
		return
	}
	defer clientTx.Terminate()

	// Store for CANCEL propagation
	p.activeTx.Store(callID, &activeTxEntry{tx: clientTx, req: fwdReq, client: p.privateClient})
	defer p.activeTx.Delete(callID)

	tx.OnCancel(func(cancelReq *sip.Request) {
		p.cancelOutgoing(callID)
	})

	// Relay responses
	for {
		select {
		case resp, ok := <-clientTx.Responses():
			if !ok {
				return
			}
			if resp.StatusCode == 100 {
				continue // already sent our own 100
			}

			relay := sip.NewResponseFromRequest(req, resp.StatusCode, resp.Reason, resp.Body())
			copyResponseHeaders(resp, relay)
			replaceContactHeader(relay, normalizedContactHeaderValue(resp.GetHeader("Contact"), fsAddr))
			tx.Respond(relay)

			if resp.StatusCode >= 200 {
				if resp.StatusCode < 300 {
					userURI := requestContactURI(req, req.From().Address)
					fsURI := responseContactURI(resp, sip.Uri{Host: strings.Split(fsAddr, ":")[0], Port: parsePort(fsAddr)})
					p.callsMu.Lock()
					p.calls[callID] = &callState{
						fsAddr:   fsAddr,
						fsURI:    fsURI,
						userAddr: req.Source(),
						userURI:  userURI,
						userAORs: append([]string(nil), userAORs...),
						isWebRTC: isWebRTCTransport(req.Transport()),
					}
					p.callsMu.Unlock()
					established = true
					slog.Info("Proxy: caller→FS established", "callID", callID)
				}
				return
			}

		case <-clientTx.Done():
			if err := clientTx.Err(); err != nil {
				slog.Error("INVITE to FS transaction failed", "error", err)
				tx.Respond(sip.NewResponseFromRequest(req, 408, "Request Timeout", nil))
			}
			return
		}
	}
}

// ---------------------------------------------------------------------------
// FS → registered user or FS → trunk
// ---------------------------------------------------------------------------

func (p *Proxy) handleInviteFromFS(req *sip.Request, tx sip.ServerTransaction) {
	toUser := req.To().Address.User
	toDomain := req.To().Address.Host

	if strings.HasSuffix(toDomain, p.cfg.SIPUserRootDomain) {
		p.handleInviteFromFSToUser(req, tx, toUser, toDomain)
	} else {
		p.handleInviteFromFSToTrunk(req, tx, toUser)
	}
}

func (p *Proxy) handleInviteFromFSToUser(req *sip.Request, tx sip.ServerTransaction, toUser, toDomain string) {
	aor := toUser + "@" + toDomain
	isWebRTC := isWebRTCSDP(req.Body())
	callID := req.CallID().Value()

	contacts := p.reg.LookupByType(aor, isWebRTC)
	if len(contacts) == 0 {
		typeName := "SIP"
		if isWebRTC {
			typeName = "WebRTC"
		}
		slog.Info("Proxy: FS→user no matching contacts", "aor", aor, "type", typeName)
		tx.Respond(sip.NewResponseFromRequest(req, 480, "Temporarily Unavailable", nil))
		return
	}

	slog.Info("Proxy: FS→user fork", "aor", aor, "contacts", len(contacts), "webrtc", isWebRTC)

	fsAddr := sourceAddrFromRequest(req)
	fsURI := requestContactURI(req, sip.Uri{Host: strings.Split(fsAddr, ":")[0], Port: parsePort(fsAddr)})
	p.saveAffinity(callID, fsAddr, []string{aor})
	established := false
	defer func() {
		if !established {
			p.deleteAffinity(callID, []string{aor})
		}
	}()

	// 100 Trying — locally generated, suppress upstream 100s.
	tx.Respond(sip.NewResponseFromRequest(req, 100, "Trying", nil))

	type branch struct {
		contact  *Contact
		fwdReq   *sip.Request
		clientTx sip.ClientTransaction
		// Set once a final response has been observed for this branch so we
		// don't re-cancel it (CANCEL on a terminated tx is harmless but noisy).
		final atomic.Bool
	}
	type branchResult struct {
		idx  int
		resp *sip.Response
		err  error
	}

	results := make(chan branchResult, len(contacts)*8)
	branchCtx, cancelAll := context.WithCancel(context.Background())
	defer cancelAll()

	type prep struct {
		c      *Contact
		fwdReq *sip.Request
	}
	preps := make([]*prep, 0, len(contacts))
	for _, c := range contacts {
		c := c
		userURI := contactDestinationURI(c, toUser, toDomain)
		fwdReq, ok := p.buildForwardRequestWithURI(req, userURI)
		if !ok {
			slog.Warn("Fork branch buildForwardRequest failed", "aor", aor, "address", c.Address)
			continue
		}
		fwdReq.SetDestination(c.Address)
		if c.IsWebRTC {
			fwdReq.SetTransport("ws")
		}
		p.addRecordRoute(fwdReq, "from_fs")
		preps = append(preps, &prep{c: c, fwdReq: fwdReq})
	}

	branches := make([]*branch, len(preps))

	for i, p2 := range preps {
		i, p2 := i, p2
		go func() {
			slog.Info("Fork branch sending",
				"aor", aor, "branch", i, "address", p2.c.Address, "webrtc", p2.c.IsWebRTC,
				"transport", p2.fwdReq.Transport(), "destination", p2.fwdReq.Destination(),
				"r-uri", p2.fwdReq.Recipient.String())
			clientTx, err := p.publicClient.TransactionRequest(branchCtx, p2.fwdReq, sipgo.ClientRequestAddVia)
			if err != nil {
				slog.Error("Fork branch send failed", "aor", aor, "branch", i, "address", p2.c.Address, "error", err)
				results <- branchResult{idx: i, err: err}
				return
			}
			b := &branch{contact: p2.c, fwdReq: p2.fwdReq, clientTx: clientTx}
			branches[i] = b
			slog.Info("Fork branch sent", "aor", aor, "branch", i, "address", p2.c.Address)
			defer clientTx.Terminate()
			for {
				select {
				case resp, ok := <-clientTx.Responses():
					if !ok {
						return
					}
					results <- branchResult{idx: i, resp: resp}
					if resp.StatusCode >= 200 {
						b.final.Store(true)
						return
					}
				case <-clientTx.Done():
					if cerr := clientTx.Err(); cerr != nil {
						results <- branchResult{idx: i, err: cerr}
					}
					b.final.Store(true)
					return
				case <-branchCtx.Done():
					return
				}
			}
		}()
	}

	if len(preps) == 0 {
		tx.Respond(sip.NewResponseFromRequest(req, 480, "Temporarily Unavailable", nil))
		return
	}

	cancelBranch := func(b *branch) {
		if b == nil || b.final.Load() {
			return
		}
		cancelReq := sip.NewRequest(sip.CANCEL, b.fwdReq.Recipient)
		cancelReq.AppendHeader(sip.HeaderClone(b.fwdReq.Via()))
		cancelReq.AppendHeader(sip.HeaderClone(b.fwdReq.From()))
		cancelReq.AppendHeader(sip.HeaderClone(b.fwdReq.To()))
		cancelReq.AppendHeader(sip.HeaderClone(b.fwdReq.CallID()))
		sip.CopyHeaders("Route", b.fwdReq, cancelReq)
		cancelReq.SetSource(b.fwdReq.Source())
		cancelReq.SetDestination(b.fwdReq.Destination())
		cancelReq.SetTransport(b.fwdReq.Transport())
		if err := p.publicClient.WriteRequest(cancelReq); err != nil {
			slog.Debug("CANCEL on fork sibling failed", "address", b.contact.Address, "error", err)
		}
	}

	// Upstream CANCEL → cancel every branch.
	tx.OnCancel(func(cancelReq *sip.Request) {
		for _, b := range branches {
			cancelBranch(b)
		}
	})

	p.activeTx.Store(callID, &activeTxEntry{tx: nil, req: req, client: p.publicClient})
	defer p.activeTx.Delete(callID)

	pending := len(preps)
	relayedProvisional := false
	var bestFinal *sip.Response

	for pending > 0 {
		select {
		case r := <-results:
			if r.err != nil {
				pending--
				continue
			}
			resp := r.resp
			if resp == nil {
				pending--
				continue
			}
			if resp.StatusCode == 100 {
				continue
			}
			if resp.StatusCode < 200 {
				if !relayedProvisional {
					relayedProvisional = true
					relay := sip.NewResponseFromRequest(req, resp.StatusCode, resp.Reason, resp.Body())
					copyResponseHeaders(resp, relay)
					tx.Respond(relay)
				}
				continue
			}
			pending--
			if resp.StatusCode < 300 {
				winner := branches[r.idx]
				relay := sip.NewResponseFromRequest(req, resp.StatusCode, resp.Reason, resp.Body())
				copyResponseHeaders(resp, relay)
				tx.Respond(relay)
				p.callsMu.Lock()
				p.calls[callID] = &callState{
					fsAddr:   fsAddr,
					fsURI:    fsURI,
					userAddr: winner.contact.Address,
					userURI:  winner.contact.URI,
					userAORs: []string{aor},
					isWebRTC: winner.contact.IsWebRTC,
				}
				p.callsMu.Unlock()
				established = true
				slog.Info("Proxy: FS→user established", "aor", aor, "callID", callID,
					"winner", winner.contact.Address, "webrtc", winner.contact.IsWebRTC,
					"branches", len(branches))
				for i, sib := range branches {
					if i != r.idx {
						cancelBranch(sib)
					}
				}
				cancelAll()
				return
			}
			if bestFinal == nil || resp.StatusCode < bestFinal.StatusCode {
				bestFinal = resp
			}
		case <-branchCtx.Done():
			return
		}
	}

	if bestFinal != nil {
		relay := sip.NewResponseFromRequest(req, bestFinal.StatusCode, bestFinal.Reason, bestFinal.Body())
		copyResponseHeaders(bestFinal, relay)
		tx.Respond(relay)
	} else {
		tx.Respond(sip.NewResponseFromRequest(req, 480, "Temporarily Unavailable", nil))
	}
}

func (p *Proxy) handleInviteFromFSToTrunk(req *sip.Request, tx sip.ServerTransaction, toUser string) {
	trunkHeader := req.GetHeader("X-Trunk-Number")
	if trunkHeader == nil {
		tx.Respond(sip.NewResponseFromRequest(req, 400, "Missing X-Trunk-Number", nil))
		return
	}

	trunk, err := p.api.GetSIPTrunk(trunkHeader.Value())
	if err != nil || trunk == nil {
		tx.Respond(sip.NewResponseFromRequest(req, 500, "Server Error", nil))
		return
	}

	dest := resolveHost(trunk.OutboundContact)
	callID := req.CallID().Value()
	slog.Info("Proxy: FS→trunk", "number", trunkHeader.Value(), "dest", dest)

	// 100 Trying
	tx.Respond(sip.NewResponseFromRequest(req, 100, "Trying", nil))

	// Build forwarded INVITE
	parts := strings.SplitN(dest, ":", 2)
	port := 5060
	if len(parts) == 2 {
		port, _ = strconv.Atoi(parts[1])
	}
	trunkURI := sip.Uri{User: toUser, Host: parts[0], Port: port}

	fwdReq, ok := p.buildForwardRequestWithURI(req, trunkURI)
	if !ok {
		tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
		return
	}
	fwdReq.SetDestination(dest)
	spoofedUser := ""
	if req.From() != nil && req.From().Address.User != "" && req.From().Address.User != trunkHeader.Value() {
		spoofedUser = req.From().Address.User
		p.spoofCache.Store(spoofCacheKey(callID, spoofedUser), trunkHeader.Value())
	}
	established := false
	defer func() {
		if !established && spoofedUser != "" {
			p.spoofCache.Delete(spoofCacheKey(callID, spoofedUser))
		}
	}()

	// Record-Route (outgoing = public, incoming = private)
	p.addRecordRoute(fwdReq, "from_fs")

	// Forward via public client
	clientTx, err := p.publicClient.TransactionRequest(context.Background(), fwdReq, sipgo.ClientRequestAddVia)
	if err != nil {
		slog.Error("Failed to forward INVITE to trunk", "error", err)
		tx.Respond(sip.NewResponseFromRequest(req, 502, "Bad Gateway", nil))
		return
	}
	defer clientTx.Terminate()

	p.activeTx.Store(callID, &activeTxEntry{tx: clientTx, req: fwdReq, client: p.publicClient})
	defer p.activeTx.Delete(callID)

	tx.OnCancel(func(cancelReq *sip.Request) {
		p.cancelOutgoing(callID)
	})

	fsAddr := sourceAddrFromRequest(req)

	for {
		select {
		case resp, ok := <-clientTx.Responses():
			if !ok {
				return
			}
			if resp.StatusCode == 100 {
				continue
			}

			// Handle trunk digest auth challenge (absorb 407, retry with creds)
			if resp.StatusCode == 401 || resp.StatusCode == 407 {
				slog.Info("Trunk auth challenge", "status", resp.StatusCode, "trunk", trunkHeader.Value())
				clientTx.Terminate()
				p.activeTx.Delete(callID)

				authResp, err := p.publicClient.DoDigestAuth(context.Background(), fwdReq, resp, sipgo.DigestAuth{
					Username: trunk.OutboundUser,
					Password: trunk.OutboundPass,
				})
				if err != nil {
					slog.Error("Trunk digest auth failed", "error", err)
					tx.Respond(sip.NewResponseFromRequest(req, 502, "Bad Gateway", nil))
					return
				}

				relay := sip.NewResponseFromRequest(req, authResp.StatusCode, authResp.Reason, authResp.Body())
				copyResponseHeaders(authResp, relay)
				tx.Respond(relay)

				if authResp.StatusCode >= 200 && authResp.StatusCode < 300 {
					userURI := responseContactURI(authResp, trunkURI)
					p.callsMu.Lock()
					p.calls[callID] = &callState{
						fsAddr:      fsAddr,
						fsURI:       requestContactURI(req, sip.Uri{Host: strings.Split(fsAddr, ":")[0], Port: parsePort(fsAddr)}),
						userAddr:    dest,
						userURI:     userURI,
						spoofedUser: spoofedUser,
					}
					p.callsMu.Unlock()
					established = true
					slog.Info("Proxy: FS→trunk established", "callID", callID)
				}
				return
			}

			relay := sip.NewResponseFromRequest(req, resp.StatusCode, resp.Reason, resp.Body())
			copyResponseHeaders(resp, relay)
			tx.Respond(relay)

			if resp.StatusCode >= 200 {
				if resp.StatusCode < 300 {
					userURI := responseContactURI(resp, trunkURI)
					p.callsMu.Lock()
					p.calls[callID] = &callState{
						fsAddr:      fsAddr,
						fsURI:       requestContactURI(req, sip.Uri{Host: strings.Split(fsAddr, ":")[0], Port: parsePort(fsAddr)}),
						userAddr:    dest,
						userURI:     userURI,
						spoofedUser: spoofedUser,
					}
					p.callsMu.Unlock()
					established = true
					slog.Info("Proxy: FS→trunk established", "callID", callID)
				}
				return
			}

		case <-clientTx.Done():
			if err := clientTx.Err(); err != nil {
				slog.Error("INVITE to trunk transaction failed", "error", err)
				tx.Respond(sip.NewResponseFromRequest(req, 408, "Request Timeout", nil))
			}
			return
		}
	}
}

// ---------------------------------------------------------------------------
// In-dialog relay (BYE, re-INVITE, REFER, INFO, UPDATE, NOTIFY)
// ---------------------------------------------------------------------------

func (p *Proxy) relayInDialog(req *sip.Request, tx sip.ServerTransaction) {
	callID := req.CallID().Value()

	p.callsMu.RLock()
	state, found := p.calls[callID]
	p.callsMu.RUnlock()
	if !found {
		if req.Method == sip.BYE {
			tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
			return
		}
		slog.Warn("In-dialog request for unknown call", "method", req.Method, "callid", callID)
		tx.Respond(sip.NewResponseFromRequest(req, 481, "Call Does Not Exist", nil))
		return
	}

	sourceIP := sourceIPFromRequest(req)
	isFS := p.dispatcher.IsFromFS(sourceIP)

	slog.Info("Relay in-dialog", "method", req.Method, "callid", callID, "fromFS", isFS)
	if req.Method == sip.REFER || req.Method == sip.NOTIFY {
		slog.Info("In-dialog details",
			"method", req.Method,
			"callid", callID,
			"refer_to", headerValue(req, "Refer-To"),
			"referred_by", headerValue(req, "Referred-By"),
			"event", headerValue(req, "Event"),
			"subscription_state", headerValue(req, "Subscription-State"),
		)
	}

	if !isFS && !p.authorizeExternalInDialog(req, tx, state, sourceIP) {
		return
	}

	// Build forwarded request (all headers pass through, Via/Route/Max-Forwards managed)
	var client *sipgo.Client
	var fwdReq *sip.Request
	var ok bool
	if isFS {
		// FS → user: forward via public client
		// Strip all our Route headers (both consumed by routing to SBC)
		client = p.publicClient
		fwdReq, ok = p.buildInDialogForwardRequestForHop(req, state.userURI, "")
		if !ok {
			tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
			return
		}
		if state.userAddr != "" {
			fwdReq.SetDestination(state.userAddr)
			if state.isWebRTC {
				fwdReq.SetTransport("ws")
			}
		}
	} else {
		// User → FS: forward via private client
		// Strip all our Route headers (both consumed by routing to SBC)
		client = p.privateClient
		fwdReq, ok = p.buildInDialogForwardRequestForHop(req, "", "")
		if !ok {
			tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
			return
		}
		fwdReq.SetDestination(state.fsAddr)
		fwdReq.SetTransport("udp")
		if req.Method == sip.REFER || req.Method == sip.ACK {
			fromTag := ""
			toTag := ""
			if f := fwdReq.From(); f != nil {
				fromTag, _ = f.Params.Get("tag")
			}
			if t := fwdReq.To(); t != nil {
				toTag, _ = t.Params.Get("tag")
			}
			slog.Info("User→FS forward",
				"method", req.Method,
				"callid", callID,
				"recipient", fwdReq.Recipient.String(),
				"destination", fwdReq.Destination(),
				"route", headerValue(fwdReq, "Route"),
				"from_tag", fromTag,
				"to_tag", toTag,
				"from", fwdReq.From().Address.String(),
				"to", fwdReq.To().Address.String(),
			)
		}
	}

	if req.Method == sip.BYE {
		slog.Info("BYE relay → start",
			"callid", callID,
			"isFS", isFS,
			"isWebRTC", state.isWebRTC,
			"destination", fwdReq.Destination(),
			"transport", fwdReq.Transport(),
			"recipient", fwdReq.Recipient.String(),
			"userAddr", state.userAddr,
			"userURI", state.userURI,
			"fsAddr", state.fsAddr,
		)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	startedAt := time.Now()
	resp, err := client.Do(ctx, fwdReq, sipgo.ClientRequestAddVia)
	elapsed := time.Since(startedAt)
	if err != nil {
		slog.Error("In-dialog relay failed",
			"method", req.Method,
			"callid", callID,
			"isFS", isFS,
			"destination", fwdReq.Destination(),
			"transport", fwdReq.Transport(),
			"elapsed_ms", elapsed.Milliseconds(),
			"error", err,
		)
		if req.Method == sip.BYE {
			tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
			p.cleanupCall(callID, state)
			return
		}
		tx.Respond(sip.NewResponseFromRequest(req, 408, "Request Timeout", nil))
		return
	}

	if req.Method == sip.BYE {
		slog.Info("BYE relay ← response",
			"callid", callID,
			"isFS", isFS,
			"status", resp.StatusCode,
			"reason", resp.Reason,
			"elapsed_ms", elapsed.Milliseconds(),
			"resp_source", resp.Source(),
			"resp_transport", resp.Transport(),
		)
	}

	if req.Method == sip.BYE && resp.StatusCode == 481 {
		tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
		p.cleanupCall(callID, state)
		slog.Info("Call terminated after remote BYE race", "callID", callID)
		return
	}

	relay := sip.NewResponseFromRequest(req, resp.StatusCode, resp.Reason, resp.Body())
	copyResponseHeaders(resp, relay)
	tx.Respond(relay)
	if req.Method == sip.REFER || req.Method == sip.NOTIFY {
		slog.Info("In-dialog response",
			"method", req.Method,
			"callid", callID,
			"status", resp.StatusCode,
			"reason", resp.Reason,
		)
	}

	// Clean up call state on successful BYE
	if req.Method == sip.BYE && resp.StatusCode == 200 {
		p.cleanupCall(callID, state)
		slog.Info("Call terminated", "callID", callID)
	}
}

// ---------------------------------------------------------------------------
// ACK (end-to-end for 2xx, forwarded to other side)
// ---------------------------------------------------------------------------

func (p *Proxy) handleAck(req *sip.Request, tx sip.ServerTransaction) {
	callID := req.CallID().Value()
	sourceIP := sourceIPFromRequest(req)
	isFS := p.dispatcher.IsFromFS(sourceIP)

	slog.Info("Handle ACK",
		"callid", callID,
		"fromFS", isFS,
		"recipient", req.Recipient.String(),
		"route", headerValue(req, "Route"),
	)

	p.callsMu.RLock()
	state, found := p.calls[callID]
	p.callsMu.RUnlock()
	if !found {
		slog.Debug("ACK for unknown call", "callid", callID)
		return
	}

	var client *sipgo.Client
	var fwdReq *sip.Request
	var ok bool
	if isFS {
		client = p.publicClient
		fwdReq, ok = p.buildInDialogForwardRequestForHop(req, state.userURI, "")
		if !ok {
			return
		}
		if state.userAddr != "" {
			fwdReq.SetDestination(state.userAddr)
			if state.isWebRTC {
				fwdReq.SetTransport("ws")
			}
		}
	} else {
		client = p.privateClient
		fwdReq, ok = p.buildInDialogForwardRequestForHop(req, "", "")
		if !ok {
			return
		}
		fwdReq.SetDestination(state.fsAddr)
		fwdReq.SetTransport("udp")
	}

	// ACK is non-transactional — send directly
	if err := client.WriteRequest(fwdReq, sipgo.ClientRequestAddVia); err != nil {
		slog.Error("Failed to forward ACK", "error", err)
	}
}

// ---------------------------------------------------------------------------
// CANCEL propagation
// ---------------------------------------------------------------------------

func (p *Proxy) handleCancel(req *sip.Request, tx sip.ServerTransaction) {
	if tooManyHops(req) {
		tx.Respond(sip.NewResponseFromRequest(req, 483, "Too Many Hops", nil))
		return
	}

	if sourceIP := sourceIPFromRequest(req); !p.dispatcher.IsFromFS(sourceIP) {
		if !p.authenticateExternalRequest(req, tx, sourceIP) {
			return
		}
	}

	tx.Respond(sip.NewResponseFromRequest(req, 200, "OK", nil))
	p.cancelOutgoing(req.CallID().Value())
}

// cancelOutgoing sends a CANCEL for the active outgoing INVITE matching the Call-ID.
func (p *Proxy) cancelOutgoing(callID string) {
	v, ok := p.activeTx.Load(callID)
	if !ok {
		return
	}
	entry := v.(*activeTxEntry)
	cancelReq := sip.NewRequest(sip.CANCEL, entry.req.Recipient)
	cancelReq.AppendHeader(sip.HeaderClone(entry.req.Via()))
	cancelReq.AppendHeader(sip.HeaderClone(entry.req.From()))
	cancelReq.AppendHeader(sip.HeaderClone(entry.req.To()))
	cancelReq.AppendHeader(sip.HeaderClone(entry.req.CallID()))
	sip.CopyHeaders("Route", entry.req, cancelReq)
	cancelReq.SetSource(entry.req.Source())
	cancelReq.SetDestination(entry.req.Destination())

	if err := entry.client.WriteRequest(cancelReq); err != nil {
		slog.Error("Failed to send CANCEL", "callid", callID, "error", err)
	}
}

// ---------------------------------------------------------------------------
// OPTIONS (respond locally)
// ---------------------------------------------------------------------------

func (p *Proxy) handleOptions(req *sip.Request, tx sip.ServerTransaction) {
	resp := sip.NewResponseFromRequest(req, 200, "OK", nil)
	resp.AppendHeader(sip.NewHeader("Allow", "INVITE, ACK, CANCEL, BYE, OPTIONS, REGISTER, REFER, INFO, UPDATE, NOTIFY"))
	tx.Respond(resp)
}

// ---------------------------------------------------------------------------
// In-dialog passthrough (REFER, INFO, UPDATE, NOTIFY)
// ---------------------------------------------------------------------------

func (p *Proxy) handlePassthrough(req *sip.Request, tx sip.ServerTransaction) {
	p.relayInDialog(req, tx)
}

// ---------------------------------------------------------------------------
// Request building helpers
// ---------------------------------------------------------------------------

// buildForwardRequest creates a proxy-forwarded copy of a SIP request.
// Copies all headers except Via (sipgo adds), Route (processed by proxy),
// and Max-Forwards (decremented).
func (p *Proxy) buildForwardRequest(req *sip.Request) (*sip.Request, bool) {
	return p.buildForwardRequestWithURI(req, req.Recipient)
}

func (p *Proxy) buildInDialogForwardRequest(req *sip.Request, rawTarget string) (*sip.Request, bool) {
	if uri, ok := parseContactURI(rawTarget); ok {
		return p.buildForwardRequestWithURI(req, uri)
	}
	return p.buildForwardRequest(req)
}

func (p *Proxy) buildInDialogForwardRequestForHop(req *sip.Request, rawTarget string, keepHop string) (*sip.Request, bool) {
	var (
		target sip.Uri
		ok     bool
	)
	if rawTarget != "" {
		target, ok = parseContactURI(rawTarget)
	}
	if !ok {
		target = req.Recipient
	}
	return p.buildForwardRequestWithURIAndRoute(req, target, keepHop)
}

func (p *Proxy) buildForwardRequestWithURI(req *sip.Request, uri sip.Uri) (*sip.Request, bool) {
	return p.buildForwardRequestWithURIAndRoute(req, uri, "")
}

func (p *Proxy) buildForwardRequestWithURIAndRoute(req *sip.Request, uri sip.Uri, keepHop string) (*sip.Request, bool) {
	fwd := sip.NewRequest(req.Method, uri)

	// Skip headers managed by proxy/sipgo:
	// - max-forwards: decremented below
	// - content-length: auto-computed by sipgo from body
	// Via is preserved: proxy prepends its own Via (ClientRequestAddVia)
	// while keeping the original Via stack for response routing.
	skip := map[string]bool{"max-forwards": true, "content-length": true}
	for _, hdr := range req.Headers() {
		name := strings.ToLower(hdr.Name())
		if skip[name] {
			continue
		}
		if name == "route" {
			if value := p.filterRouteValueForHop(hdr.Value(), keepHop); value != "" {
				fwd.AppendHeader(sip.NewHeader("Route", value))
			}
			continue
		}
		// Clone headers to prevent ClientRequestAddVia from mutating
		// the original request's Via rport/received params (shared pointers).
		fwd.AppendHeader(sip.HeaderClone(hdr))
	}

	// Decrement Max-Forwards
	mf := 70
	if h := req.MaxForwards(); h != nil {
		mf = int(h.Val()) - 1
	}
	if mf < 0 {
		return nil, false
	}
	maxfwd := sip.MaxForwardsHeader(mf)
	fwd.AppendHeader(&maxfwd)

	fwd.SetBody(req.Body())
	return fwd, true
}

// addRecordRoute adds double Record-Route for the SBC's two interfaces.
// Order depends on direction so each side's route set resolves correctly.
// Ports come from cfg (PublicSIPPort/PrivateSIPPort) so dev with Docker
// port-mapping (host:6060 → container:5060) advertises the host-side port
// that external peers can actually reach.
func (p *Proxy) addRecordRoute(req *sip.Request, direction string) {
	publicRR := fmt.Sprintf("<sip:%s:%d;lr>", p.cfg.PublicIP, p.cfg.PublicSIPPort)
	privateRR := fmt.Sprintf("<sip:%s:%d;lr>", p.cfg.PrivateIP, p.cfg.PrivateSIPPort)

	if direction == "to_fs" {
		// Caller→FS: packet enters public, exits private
		// Top = outgoing (private, closest to FS), bottom = incoming (public)
		req.PrependHeader(sip.NewHeader("Record-Route", publicRR))
		req.PrependHeader(sip.NewHeader("Record-Route", privateRR))
	} else {
		// FS→user/trunk: packet enters private, exits public
		// Top = outgoing (public, closest to user), bottom = incoming (private)
		req.PrependHeader(sip.NewHeader("Record-Route", privateRR))
		req.PrependHeader(sip.NewHeader("Record-Route", publicRR))
	}
}

// ---------------------------------------------------------------------------
// Response header forwarding
// ---------------------------------------------------------------------------

// copyResponseHeaders forwards application-level headers from a received
// response into the relay response. Dialog/transport headers are skipped.
func copyResponseHeaders(src *sip.Response, dst *sip.Response) {
	skip := map[string]bool{
		"via": true, "from": true, "to": true, "call-id": true,
		"cseq": true, "content-type": true, "content-length": true,
	}
	for _, hdr := range src.Headers() {
		name := strings.ToLower(hdr.Name())
		if !skip[name] {
			dst.AppendHeader(hdr)
		}
	}
	// Content-Type must be forwarded if body is present
	if src.ContentType() != nil {
		dst.AppendHeader(sip.NewHeader("Content-Type", src.ContentType().Value()))
	}
	// To header must be copied from the received response because it carries
	// the remote party's tag. NewResponseFromRequest uses the original request's
	// To (which has no tag on initial INVITEs), so the tag would be lost.
	if srcTo := src.To(); srcTo != nil {
		dst.RemoveHeader("To")
		dst.AppendHeader(srcTo)
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func sourceIPFromRequest(req *sip.Request) string {
	src := req.Source()
	if src == "" {
		return ""
	}
	host, _, err := net.SplitHostPort(src)
	if err != nil {
		return src
	}
	return host
}

func sourceAddrFromRequest(req *sip.Request) string {
	return req.Source()
}

func tooManyHops(req *sip.Request) bool {
	if h := req.MaxForwards(); h != nil {
		return h.Val() <= 0
	}
	return false
}

func (p *Proxy) authenticateExternalRequest(req *sip.Request, tx sip.ServerTransaction, sourceIP string) bool {
	fromDomain := req.From().Address.Host

	if strings.HasSuffix(fromDomain, p.cfg.SIPUserRootDomain) {
		user := req.From().Address.User
		password, err := p.api.GetUserPassword(user, fromDomain)
		if err != nil || password == "" {
			sendAuthChallenge(tx, req, fromDomain)
			return false
		}
		if !validateDigestAuth(req, password) {
			sendAuthChallenge(tx, req, fromDomain)
			return false
		}
		return true
	}

	trunkNumber := req.To().Address.User
	if cached, ok := p.spoofCache.Load(spoofCacheKey(req.CallID().Value(), trunkNumber)); ok {
		trunkNumber = cached.(string)
	}
	trunk, err := p.api.GetSIPTrunk(trunkNumber)
	if err != nil || trunk == nil {
		tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return false
	}
	if !isIPAllowed(sourceIP, trunk.InboundIPs) {
		tx.Respond(sip.NewResponseFromRequest(req, 403, "Forbidden", nil))
		return false
	}
	return true
}

func (p *Proxy) authorizeExternalInDialog(req *sip.Request, tx sip.ServerTransaction, state *callState, sourceIP string) bool {
	if strings.HasSuffix(req.From().Address.Host, p.cfg.SIPUserRootDomain) {
		if state.userAddr != "" && req.Source() == state.userAddr {
			return true
		}
	}
	return p.authenticateExternalRequest(req, tx, sourceIP)
}

func comcentUsersForRequest(req *sip.Request, sipUserRootDomain string) []string {
	users := make([]string, 0, 2)
	for _, uri := range []sip.Uri{req.From().Address, req.To().Address} {
		if uri.User == "" || !strings.HasSuffix(uri.Host, sipUserRootDomain) {
			continue
		}
		aor := uri.User + "@" + uri.Host
		if !containsString(users, aor) {
			users = append(users, aor)
		}
	}
	return users
}

func (p *Proxy) selectTargetForUsers(users []string) (string, bool) {
	p.affinityMu.RLock()
	for _, user := range users {
		for _, target := range p.affinity[user] {
			p.affinityMu.RUnlock()
			return "sip:" + target, true
		}
	}
	p.affinityMu.RUnlock()
	return p.dispatcher.SelectTarget()
}

func (p *Proxy) saveAffinity(callID, fsAddr string, users []string) {
	if len(users) == 0 || fsAddr == "" {
		return
	}
	p.affinityMu.Lock()
	defer p.affinityMu.Unlock()
	for _, user := range users {
		if _, ok := p.affinity[user]; !ok {
			p.affinity[user] = make(map[string]string)
		}
		p.affinity[user][callID] = fsAddr
	}
}

func (p *Proxy) deleteAffinity(callID string, users []string) {
	if len(users) == 0 {
		return
	}
	p.affinityMu.Lock()
	defer p.affinityMu.Unlock()
	for _, user := range users {
		callMap, ok := p.affinity[user]
		if !ok {
			continue
		}
		delete(callMap, callID)
		if len(callMap) == 0 {
			delete(p.affinity, user)
		}
	}
}

func (p *Proxy) cleanupCall(callID string, state *callState) {
	p.callsMu.Lock()
	delete(p.calls, callID)
	p.callsMu.Unlock()
	p.deleteAffinity(callID, state.userAORs)
	if state.spoofedUser != "" {
		p.spoofCache.Delete(spoofCacheKey(callID, state.spoofedUser))
	}
}

func (p *Proxy) filterRouteValue(value string) string {
	return p.filterRouteValueForHop(value, "")
}

func (p *Proxy) filterRouteValueForHop(value, keepHop string) string {
	if value == "" {
		return ""
	}
	publicMarker := fmt.Sprintf("%s:5060", p.cfg.PublicIP)
	privateMarker := fmt.Sprintf("%s:5065", p.cfg.PrivateIP)
	parts := strings.Split(value, ",")
	kept := make([]string, 0, len(parts))
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed == "" {
			continue
		}

		isPublic := strings.Contains(trimmed, publicMarker)
		isPrivate := strings.Contains(trimmed, privateMarker)
		if isPublic || isPrivate {
			switch keepHop {
			case "public":
				if isPublic {
					kept = append(kept, trimmed)
				}
			case "private":
				if isPrivate {
					kept = append(kept, trimmed)
				}
			}
			continue
		}
		kept = append(kept, trimmed)
	}
	return strings.Join(kept, ", ")
}

// contactExpiresParam parses an `expires=N` parameter from a Contact header
// value. RFC 3261 §10.2.1 says this param overrides the Expires header.
func contactExpiresParam(value string) (int, bool) {
	rest := value
	if idx := strings.IndexByte(rest, '>'); idx >= 0 {
		rest = rest[idx+1:]
	}
	for _, raw := range strings.Split(rest, ";") {
		p := strings.TrimSpace(raw)
		if !strings.HasPrefix(strings.ToLower(p), "expires=") {
			continue
		}
		v := strings.TrimSpace(p[len("expires="):])
		if n, err := strconv.Atoi(v); err == nil {
			return n, true
		}
	}
	return 0, false
}

func extractContactURI(value, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	start := strings.IndexByte(value, '<')
	end := strings.IndexByte(value, '>')
	if start >= 0 && end > start {
		return value[start+1 : end]
	}
	if idx := strings.IndexByte(value, ';'); idx >= 0 {
		return strings.TrimSpace(value[:idx])
	}
	return value
}

func headerValue(req *sip.Request, name string) string {
	if hdr := req.GetHeader(name); hdr != nil {
		return hdr.Value()
	}
	return ""
}

func normalizedContactHeaderValue(hdr sip.Header, destAddr string) string {
	if hdr == nil || destAddr == "" {
		return ""
	}
	raw := extractContactURI(hdr.Value(), "")
	if raw == "" {
		return ""
	}

	uri, ok := parseContactURI(raw)
	if !ok {
		return ""
	}
	if !shouldRewriteContactHost(uri.Host) {
		return ""
	}

	host, port := hostPortFromAddr(destAddr)
	if host == "" {
		return ""
	}
	uri.Host = host
	if port > 0 {
		uri.Port = port
	}
	return "<" + uri.String() + ">"
}

func replaceContactHeader(msg interface {
	RemoveHeader(string) bool
	AppendHeader(sip.Header)
}, value string) {
	if value == "" {
		return
	}
	msg.RemoveHeader("Contact")
	msg.AppendHeader(sip.NewHeader("Contact", value))
}

func shouldRewriteContactHost(host string) bool {
	switch strings.ToLower(host) {
	case "", "localhost", "127.0.0.1", "0.0.0.0":
		return true
	default:
		return false
	}
}

func hostPortFromAddr(addr string) (string, int) {
	parts := strings.Split(addr, ":")
	if len(parts) == 0 {
		return "", 0
	}
	host := parts[0]
	if len(parts) == 1 {
		return host, 0
	}
	port, _ := strconv.Atoi(parts[len(parts)-1])
	return host, port
}

func requestContactURI(req *sip.Request, fallback sip.Uri) string {
	if hdr := req.GetHeader("Contact"); hdr != nil {
		return extractContactURI(hdr.Value(), fallback.String())
	}
	return fallback.String()
}

func responseContactURI(resp *sip.Response, fallback sip.Uri) string {
	if hdr := resp.GetHeader("Contact"); hdr != nil {
		return extractContactURI(hdr.Value(), fallback.String())
	}
	return fallback.String()
}

func contactDestinationURI(contact *Contact, user, domain string) sip.Uri {
	if uri, ok := parseContactURI(contact.URI); ok {
		return uri
	}
	host := strings.Split(contact.Address, ":")[0]
	port := parsePort(contact.Address)
	return sip.Uri{User: user, Host: host, Port: port}
}

func parseContactURI(raw string) (sip.Uri, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return sip.Uri{}, false
	}
	trimmed = strings.Trim(trimmed, "<>")
	trimmed = strings.TrimPrefix(trimmed, "sip:")
	trimmed = strings.TrimPrefix(trimmed, "sips:")
	if idx := strings.Index(trimmed, ";"); idx >= 0 {
		trimmed = trimmed[:idx]
	}
	if trimmed == "" {
		return sip.Uri{}, false
	}

	user := ""
	hostPort := trimmed
	if at := strings.LastIndex(trimmed, "@"); at >= 0 {
		user = trimmed[:at]
		hostPort = trimmed[at+1:]
	}
	host := hostPort
	port := 0
	if idx := strings.LastIndex(hostPort, ":"); idx >= 0 && !strings.Contains(hostPort[idx+1:], "]") {
		if parsed, err := strconv.Atoi(hostPort[idx+1:]); err == nil {
			host = hostPort[:idx]
			port = parsed
		}
	}
	return sip.Uri{User: user, Host: host, Port: port}, true
}

func spoofCacheKey(callID, user string) string {
	return callID + "::" + user
}

func containsString(values []string, candidate string) bool {
	for _, value := range values {
		if value == candidate {
			return true
		}
	}
	return false
}

func isWebRTCTransport(transport string) bool {
	switch strings.ToLower(transport) {
	case "ws", "wss":
		return true
	default:
		return false
	}
}

func isIPAllowed(sourceIP string, allowedCIDRs []string) bool {
	if len(allowedCIDRs) == 0 {
		return false
	}
	ip := net.ParseIP(sourceIP)
	if ip == nil {
		return false
	}
	for _, cidr := range allowedCIDRs {
		_, network, err := net.ParseCIDR(cidr)
		if err != nil {
			continue
		}
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func stripSIPPrefix(uri string) string {
	dest := uri
	dest = strings.TrimPrefix(dest, "sip:")
	dest = strings.TrimPrefix(dest, "sips:")
	if !strings.Contains(dest, ":") {
		dest = dest + ":5060"
	}
	return dest
}

func resolveHost(hostPort string) string {
	parts := strings.SplitN(hostPort, ":", 2)
	host := parts[0]
	port := "5060"
	if len(parts) == 2 {
		port = parts[1]
	}
	addrs, err := net.LookupHost(host)
	if err != nil || len(addrs) == 0 {
		return hostPort
	}
	return addrs[0] + ":" + port
}

func parsePort(addr string) int {
	_, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return 5060
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return 5060
	}
	return port
}

// isWebRTCSDP checks if an SDP body uses WebRTC transport (SAVP/SAVPF)
// Duplicated from registrar.go for convenience in this file.
func isWebRTCSDPBody(body []byte) bool {
	s := string(body)
	return strings.Contains(s, "RTP/SAVPF") ||
		strings.Contains(s, "RTP/SAVP") ||
		strings.Contains(s, "UDP/TLS/RTP/SAVPF")
}
