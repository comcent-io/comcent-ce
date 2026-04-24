package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"sync/atomic"
)

type Dispatcher struct {
	mu      sync.RWMutex
	targets []string // list of "ip:port" FS addresses
	counter atomic.Uint64
	cfg     Config
}

func newDispatcher(cfg Config) *Dispatcher {
	return &Dispatcher{cfg: cfg}
}

func (d *Dispatcher) AddTarget(uri string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, t := range d.targets {
		if t == uri {
			return
		}
	}
	d.targets = append(d.targets, uri)
	slog.Info("Dispatcher added FS target", "uri", uri, "total", len(d.targets))
}

func (d *Dispatcher) RemoveTarget(uri string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	for i, t := range d.targets {
		if t == uri {
			d.targets = append(d.targets[:i], d.targets[i+1:]...)
			slog.Info("Dispatcher removed FS target", "uri", uri, "total", len(d.targets))
			return
		}
	}
}

func (d *Dispatcher) SelectTarget() (string, bool) {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if len(d.targets) == 0 {
		return "", false
	}
	idx := d.counter.Add(1) % uint64(len(d.targets))
	return d.targets[idx], true
}

func (d *Dispatcher) IsFromFS(sourceIP string) bool {
	d.mu.RLock()
	defer d.mu.RUnlock()
	for _, t := range d.targets {
		if t == "sip:"+sourceIP+":5070" {
			return true
		}
	}
	return false
}

func (d *Dispatcher) ListTargets() []string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	out := make([]string, len(d.targets))
	copy(out, d.targets)
	return out
}

type rpcRequest struct {
	JSONRPC string        `json:"jsonrpc"`
	Method  string        `json:"method"`
	Params  []interface{} `json:"params"`
	ID      interface{}   `json:"id"`
}

func (d *Dispatcher) handleRPC(expectedToken string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-Api-Token")
		if token == "" || token != expectedToken {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		var req rpcRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Bad Request", http.StatusBadRequest)
			return
		}

		switch req.Method {
		case "dispatcher.add":
			if len(req.Params) >= 2 {
				uri := fmt.Sprintf("%v", req.Params[1])
				d.AddTarget(uri)
			}
			json.NewEncoder(w).Encode(map[string]interface{}{"jsonrpc": "2.0", "result": "OK", "id": req.ID})

		case "dispatcher.remove":
			if len(req.Params) >= 2 {
				uri := fmt.Sprintf("%v", req.Params[1])
				d.RemoveTarget(uri)
			}
			json.NewEncoder(w).Encode(map[string]interface{}{"jsonrpc": "2.0", "result": "OK", "id": req.ID})

		case "dispatcher.list":
			targets := d.ListTargets()
			records := make([]interface{}, 0)
			if len(targets) > 0 {
				targetList := make([]map[string]interface{}, len(targets))
				for i, t := range targets {
					targetList[i] = map[string]interface{}{"DEST": map[string]string{"URI": t}}
				}
				records = append(records, map[string]interface{}{
					"SET": map[string]interface{}{"TARGETS": targetList},
				})
			}
			json.NewEncoder(w).Encode(map[string]interface{}{
				"jsonrpc": "2.0",
				"result":  map[string]interface{}{"RECORDS": records},
				"id":      req.ID,
			})

		default:
			http.Error(w, "Method not found", http.StatusNotFound)
		}
	}
}
