package main

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"sync"
	"testing"
	"time"
)

func TestReapReportsOnlyAORsLeftWithoutContacts(t *testing.T) {
	now := time.Now()
	r := newRegistrar()
	r.Register("lapsed@acme.example.com", &Contact{Address: "10.0.0.1:5060", ExpiresAt: now.Add(-time.Second)})
	r.Register("live@acme.example.com", &Contact{Address: "10.0.0.2:5060", ExpiresAt: now.Add(time.Minute)})
	r.Register("mixed@acme.example.com", &Contact{Address: "10.0.0.3:5060", ExpiresAt: now.Add(-time.Second)})
	r.Register("mixed@acme.example.com", &Contact{Address: "10.0.0.4:5060", ExpiresAt: now.Add(time.Minute)})

	emptied := r.reap(now)

	if want := []string{"lapsed@acme.example.com"}; !reflect.DeepEqual(emptied, want) {
		t.Fatalf("reap emptied %v, want %v", emptied, want)
	}
	if r.IsRegistered("lapsed@acme.example.com") {
		t.Fatal("lapsed AOR is still registered")
	}
	if got := r.LookupAll("mixed@acme.example.com"); len(got) != 1 || got[0].Address != "10.0.0.4:5060" {
		t.Fatalf("mixed AOR kept %v, want only the live contact", got)
	}
	if !r.IsRegistered("live@acme.example.com") {
		t.Fatal("live AOR was reaped")
	}
	if emptied := r.reap(now); len(emptied) != 0 {
		t.Fatalf("second reap emptied %v, want nothing", emptied)
	}
}

func TestRegistrationLapsedTellsTheServerUnlessRegisteredAgain(t *testing.T) {
	var mu sync.Mutex
	var posts []url.Values
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path != "/user/presence" {
			t.Errorf("unexpected path %s", req.URL.Path)
		}
		if err := req.ParseForm(); err != nil {
			t.Error(err)
		}
		mu.Lock()
		posts = append(posts, req.PostForm)
		mu.Unlock()
	}))
	defer srv.Close()

	reg := newRegistrar()
	p := &Proxy{reg: reg, api: &InternalAPI{baseURL: srv.URL, client: srv.Client()}}

	reg.Register("back@acme.sip.example.com", &Contact{Address: "10.0.0.5:5060", ExpiresAt: time.Now().Add(time.Minute)})
	p.registrationLapsed("back@acme.sip.example.com")
	p.registrationLapsed("gone@acme.sip.example.com")

	want := []url.Values{{
		"subdomain": {"acme"},
		"action":    {"expired"},
		"username":  {"gone"},
	}}
	mu.Lock()
	defer mu.Unlock()
	if !reflect.DeepEqual(posts, want) {
		t.Fatalf("server was told %v, want %v", posts, want)
	}
}
