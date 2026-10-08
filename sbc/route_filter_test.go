package main

import "testing"

// Twilio's Record-Route names our public address in its twnat parameter. Only
// our own hops may be stripped from the Route set of an ACK or BYE to the
// trunk; Twilio's must stay, or its edge answers the BYE 481 and the far end
// stays on the call.
func TestRouteFilterKeepsTwiliosHopThatMentionsOurAddress(t *testing.T) {
	p := &Proxy{cfg: Config{PublicIP: "203.0.113.10", PrivateIP: "172.31.17.9"}}
	twilio := "<sip:198.51.100.3;lr;twnat=sip:203.0.113.10:5060>"
	value := twilio + ",<sip:203.0.113.10:5060;lr>,<sip:172.31.17.9:5065;lr>"

	if got := p.filterRouteValueForHop(value, ""); got != twilio {
		t.Errorf("Route to the trunk = %q, want only Twilio's hop %q", got, twilio)
	}
	if got := p.filterRouteValueForHop(value, "private"); got != twilio+", <sip:172.31.17.9:5065;lr>" {
		t.Errorf("Route keeping the private hop = %q", got)
	}
}

func TestRouteHop(t *testing.T) {
	cases := map[string]string{
		"<sip:198.51.100.3;lr;twnat=sip:203.0.113.10:5060>": "198.51.100.3:5060",
		"<sip:203.0.113.10:5060;lr>":                        "203.0.113.10:5060",
		" <sip:172.31.17.9:5065;lr>":                        "172.31.17.9:5065",
		"sip:edge.example.com:5080;lr":                      "edge.example.com:5080",
		"<not a uri>":                                       "",
	}
	for entry, want := range cases {
		if got := routeHop(entry); got != want {
			t.Errorf("routeHop(%q) = %q, want %q", entry, got, want)
		}
	}
}
