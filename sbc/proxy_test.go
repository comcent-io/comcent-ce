package main

import "testing"

// What SIP.js sends: the lifetime only as a Contact parameter, no Expires header.
const sipJSContact = `<sip:ste83mpb@uk3dbr4gss78.invalid;transport=ws>;+sip.ice;reg-id=1;+sip.instance="<urn:uuid:8f2c1c0e-5d1a-4b7e-9d8a-2f3b4c5d6e7f>";expires=600`

func TestRegisterExpires(t *testing.T) {
	cases := []struct {
		name          string
		contact       string
		expiresHeader string
		want          int
	}{
		{"Contact parameter only (SIP.js)", sipJSContact, "", 600},
		{"Expires header only", "<sip:alice@10.0.0.2:5060>", "120", 120},
		{"Contact parameter wins over the header", "<sip:alice@10.0.0.2:5060>;expires=60", "3600", 60},
		{"neither: default", "<sip:alice@10.0.0.2:5060>", "", defaultRegisterExpires},
		{"unregister via the Contact parameter (SIP.js)", `<sip:ste83mpb@uk3dbr4gss78.invalid;transport=ws>;+sip.ice;expires=0`, "", 0},
		{"unregister via the header", "<sip:alice@10.0.0.2:5060>", "0", 0},
		{"URI parameter named expires is not the lifetime", "<sip:alice@10.0.0.2:5060;expires=5>", "90", 90},
		{"no angle brackets: parameters belong to the header", "sip:alice@10.0.0.2:5060;expires=45", "", 45},
		{"garbage parameter falls back to the header", "<sip:alice@10.0.0.2:5060>;expires=soon", "30", 30},
		{"Contact: * with Expires: 0", "*", "0", 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := registerExpires(tc.contact, tc.expiresHeader); got != tc.want {
				t.Fatalf("registerExpires(%q, %q) = %d, want %d", tc.contact, tc.expiresHeader, got, tc.want)
			}
		})
	}
}

func TestContactWithExpires(t *testing.T) {
	cases := []struct {
		name    string
		contact string
		expires int
		want    string
	}{
		{
			"replaces the client's value and keeps the other parameters",
			sipJSContact,
			300,
			`<sip:ste83mpb@uk3dbr4gss78.invalid;transport=ws>;+sip.ice;reg-id=1;+sip.instance="<urn:uuid:8f2c1c0e-5d1a-4b7e-9d8a-2f3b4c5d6e7f>";expires=300`,
		},
		{"adds it when absent", "<sip:alice@10.0.0.2:5060>", 300, "<sip:alice@10.0.0.2:5060>;expires=300"},
		{"leaves URI parameters alone", "<sip:alice@10.0.0.2:5060;transport=tcp>", 120, "<sip:alice@10.0.0.2:5060;transport=tcp>;expires=120"},
		{"no angle brackets", "sip:alice@10.0.0.2:5060;expires=600", 300, "sip:alice@10.0.0.2:5060;expires=300"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := contactWithExpires(tc.contact, tc.expires)
			if got != tc.want {
				t.Fatalf("contactWithExpires(%q, %d) =\n  %s\nwant\n  %s", tc.contact, tc.expires, got, tc.want)
			}
			// What the client reads back is what we stored.
			if back := registerExpires(got, ""); back != tc.expires {
				t.Fatalf("registerExpires of the response Contact = %d, want %d", back, tc.expires)
			}
		})
	}
}
