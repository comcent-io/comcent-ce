package main

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	"golang.org/x/sync/errgroup"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg := loadConfig()

	// Allow large UDP packets for WebRTC SDPs (ICE candidates make them >1500 bytes)
	sip.UDPMTUSize = 9000

	// Public UA — for external SIP (trunks, SIP phones, WebRTC agents)
	// Via headers use publicIP:5060
	publicUA, err := sipgo.NewUA(
		sipgo.WithUserAgent("ComcentSBC/1.0"),
		sipgo.WithUserAgentHostname(cfg.PublicIP),
	)
	if err != nil {
		slog.Error("Failed to create public UA", "error", err)
		os.Exit(1)
	}

	// Private UA — for internal FS communication
	// Via headers use privateIP:5065
	privateUA, err := sipgo.NewUA(
		sipgo.WithUserAgent("ComcentSBC/1.0"),
		sipgo.WithUserAgentHostname(cfg.PrivateIP),
	)
	if err != nil {
		slog.Error("Failed to create private UA", "error", err)
		os.Exit(1)
	}

	publicSrv, err := sipgo.NewServer(publicUA)
	if err != nil {
		slog.Error("Failed to create public server", "error", err)
		os.Exit(1)
	}

	privateSrv, err := sipgo.NewServer(privateUA)
	if err != nil {
		slog.Error("Failed to create private server", "error", err)
		os.Exit(1)
	}

	publicClient, err := sipgo.NewClient(publicUA)
	if err != nil {
		slog.Error("Failed to create public client", "error", err)
		os.Exit(1)
	}

	privateClient, err := sipgo.NewClient(
		privateUA,
		sipgo.WithClientHostname(cfg.PrivateIP),
		sipgo.WithClientPort(5065),
		sipgo.WithClientConnectionAddr(cfg.PrivateIP+":5065"),
	)
	if err != nil {
		slog.Error("Failed to create private client", "error", err)
		os.Exit(1)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	api := newInternalAPI(cfg)
	reg := newRegistrar(ctx)
	dispatcher := newDispatcher(cfg)
	proxy := newProxy(publicClient, privateClient, reg, api, dispatcher, cfg)

	// Register handlers on both public and private servers
	for _, s := range []*sipgo.Server{publicSrv, privateSrv} {
		s.OnRequest(sip.REGISTER, proxy.handleRegister)
		s.OnRequest(sip.INVITE, proxy.handleInvite)
		s.OnRequest(sip.ACK, proxy.handleAck)
		s.OnRequest(sip.BYE, proxy.handlePassthrough)
		s.OnRequest(sip.CANCEL, proxy.handleCancel)
		s.OnRequest(sip.OPTIONS, proxy.handleOptions)
		s.OnRequest(sip.REFER, proxy.handlePassthrough)
		s.OnRequest(sip.INFO, proxy.handlePassthrough)
		s.OnRequest(sip.UPDATE, proxy.handlePassthrough)
		s.OnRequest(sip.NOTIFY, proxy.handlePassthrough)
	}

	g, ctx := errgroup.WithContext(ctx)

	// Public UDP listener — external SIP (trunks, SIP phones)
	// Via: publicIP:5060
	g.Go(func() error {
		slog.Info("SIP UDP public listener", "addr", "0.0.0.0:5060", "advertise", cfg.PublicIP+":5060")
		return publicSrv.ListenAndServe(ctx, "udp", "0.0.0.0:5060")
	})

	// Public TCP listener — external SIP over TCP
	g.Go(func() error {
		slog.Info("SIP TCP public listener", "addr", "0.0.0.0:5060", "advertise", cfg.PublicIP+":5060")
		return publicSrv.ListenAndServe(ctx, "tcp", "0.0.0.0:5060")
	})

	// Private UDP listener — internal FS communication
	// Via: privateIP:5065
	g.Go(func() error {
		slog.Info("SIP UDP private listener", "addr", "0.0.0.0:5065", "advertise", cfg.PrivateIP+":5065")
		return privateSrv.ListenAndServe(ctx, "udp", "0.0.0.0:5065")
	})

	// Private TCP listener — internal SIP over TCP
	g.Go(func() error {
		slog.Info("SIP TCP private listener", "addr", "0.0.0.0:5065", "advertise", cfg.PrivateIP+":5065")
		return privateSrv.ListenAndServe(ctx, "tcp", "0.0.0.0:5065")
	})

	// Port 80: mixed HTTP (health/rpc) + WebSocket (SIP over WS)
	// WebSocket uses public server (external WebRTC agents)
	g.Go(func() error {
		return startMuxListener(ctx, publicSrv, dispatcher, cfg, "0.0.0.0:80")
	})

	// Port 8080: health-only for Docker healthcheck
	g.Go(func() error {
		mux := http.NewServeMux()
		mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("OK"))
		})
		httpSrv := &http.Server{Addr: "0.0.0.0:8080", Handler: mux}
		go func() { <-ctx.Done(); httpSrv.Close() }()
		slog.Info("Health listener", "addr", "0.0.0.0:8080")
		return httpSrv.ListenAndServe()
	})

	// Auto-discover FS on startup
	go func() {
		time.Sleep(2 * time.Second)
		addrs, err := net.LookupHost("freeswitch")
		if err != nil {
			slog.Info("FS auto-discovery: freeswitch hostname not found", "error", err)
			return
		}
		for _, addr := range addrs {
			uri := "sip:" + addr + ":5070"
			dispatcher.AddTarget(uri)
			slog.Info("FS auto-discovered", "uri", uri)
		}
	}()

	if err := g.Wait(); err != nil && ctx.Err() == nil {
		slog.Error("Server error", "error", err)
		os.Exit(1)
	}

	slog.Info("SBC shutdown complete")
}

func startMuxListener(ctx context.Context, srv *sipgo.Server, dispatcher *Dispatcher, cfg Config, addr string) error {
	tcpLn, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	go func() { <-ctx.Done(); tcpLn.Close() }()

	// sipgo WS listener via pipe
	wsLn := newPipeListener()
	go func() {
		if err := srv.ServeWS(wsLn); err != nil && ctx.Err() == nil {
			slog.Error("WS serve error", "error", err)
		}
	}()

	httpMux := http.NewServeMux()
	httpMux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})
	httpMux.HandleFunc("/rpc", dispatcher.handleRPC(cfg.RPCAPIToken))

	slog.Info("Mixed HTTP+WS listener", "addr", addr)

	for {
		conn, err := tcpLn.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		go handleTCPConn(conn, wsLn, httpMux)
	}
}

func handleTCPConn(conn net.Conn, wsLn *pipeListener, httpMux *http.ServeMux) {
	br := bufio.NewReader(conn)

	peek, err := br.Peek(4)
	if err != nil {
		conn.Close()
		return
	}

	first := strings.ToUpper(string(peek))

	if strings.HasPrefix(first, "GET ") || strings.HasPrefix(first, "POST") {
		req, err := http.ReadRequest(br)
		if err != nil {
			conn.Close()
			return
		}

		if isWebSocketUpgrade(req) {
			// Reconstruct HTTP request for sipgo's WS handler
			var buf strings.Builder
			buf.WriteString(req.Method + " " + req.RequestURI + " " + req.Proto + "\r\n")
			if req.Host != "" {
				buf.WriteString("Host: " + req.Host + "\r\n")
			}
			for k, vals := range req.Header {
				if strings.EqualFold(k, "Host") {
					continue
				}
				for _, v := range vals {
					buf.WriteString(k + ": " + v + "\r\n")
				}
			}
			buf.WriteString("\r\n")
			raw := []byte(buf.String())

			// Extract real client IP from X-Forwarded-For (when behind Traefik)
			realIP := req.Header.Get("X-Forwarded-For")
			if realIP != "" {
				// Store real IP for rport handling
				parts := strings.Split(realIP, ",")
				slog.Debug("WS connection from proxy", "realIP", strings.TrimSpace(parts[0]), "proxyIP", conn.RemoteAddr().String())
			}

			wsConn := newPrefixConn(conn, raw)
			wsLn.Inject(wsConn)
			return
		}

		rw := newResponseWriter(conn)
		httpMux.ServeHTTP(rw, req)
		rw.finish()
		conn.Close()
		return
	}

	conn.Close()
}

func isWebSocketUpgrade(r *http.Request) bool {
	upgrade := r.Header.Get("Upgrade")
	connection := r.Header.Get("Connection")
	return strings.EqualFold(upgrade, "websocket") &&
		strings.Contains(strings.ToLower(connection), "upgrade")
}

type rawResponseWriter struct {
	conn       net.Conn
	headers    http.Header
	statusCode int
	written    bool
	body       strings.Builder
}

func newResponseWriter(conn net.Conn) *rawResponseWriter {
	return &rawResponseWriter{
		conn:       conn,
		headers:    make(http.Header),
		statusCode: 200,
	}
}

func (w *rawResponseWriter) Header() http.Header {
	return w.headers
}

func (w *rawResponseWriter) WriteHeader(code int) {
	w.statusCode = code
}

func (w *rawResponseWriter) Write(b []byte) (int, error) {
	w.written = true
	return w.body.Write(b)
}

func (w *rawResponseWriter) finish() {
	body := w.body.String()
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("HTTP/1.1 %d %s\r\n", w.statusCode, http.StatusText(w.statusCode)))
	sb.WriteString(fmt.Sprintf("Content-Length: %d\r\n", len(body)))
	sb.WriteString("Connection: close\r\n")
	for k, vals := range w.headers {
		for _, v := range vals {
			sb.WriteString(k + ": " + v + "\r\n")
		}
	}
	sb.WriteString("\r\n")
	sb.WriteString(body)
	w.conn.Write([]byte(sb.String()))
}
