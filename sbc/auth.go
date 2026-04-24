package main

import (
	"crypto/md5"
	"crypto/rand"
	"fmt"
	"log/slog"
	"strings"

	"github.com/emiago/sipgo/sip"
)

func generateNonce() string {
	b := make([]byte, 16)
	rand.Read(b)
	return fmt.Sprintf("%x", b)
}

func sendAuthChallenge(tx sip.ServerTransaction, req *sip.Request, realm string) {
	nonce := generateNonce()
	resp := sip.NewResponseFromRequest(req, 401, "Unauthorized", nil)
	resp.AppendHeader(sip.NewHeader(
		"WWW-Authenticate",
		fmt.Sprintf(`Digest realm="%s", nonce="%s", algorithm=MD5, qop="auth"`, realm, nonce),
	))
	if err := tx.Respond(resp); err != nil {
		slog.Error("Failed to send 401", "error", err)
	}
}

func validateDigestAuth(req *sip.Request, password string) bool {
	authHeader := req.GetHeader("Authorization")
	if authHeader == nil {
		return false
	}

	authStr := authHeader.Value()
	if !strings.HasPrefix(authStr, "Digest ") {
		return false
	}

	params := parseDigestParams(authStr[7:])
	username := params["username"]
	realm := params["realm"]
	nonce := params["nonce"]
	uri := params["uri"]
	nc := params["nc"]
	cnonce := params["cnonce"]
	qop := params["qop"]
	clientResponse := params["response"]

	ha1 := md5Hex(username + ":" + realm + ":" + password)

	var ha2 string
	ha2 = md5Hex(req.Method.String() + ":" + uri)

	var expected string
	if qop == "auth" {
		expected = md5Hex(ha1 + ":" + nonce + ":" + nc + ":" + cnonce + ":" + qop + ":" + ha2)
	} else {
		expected = md5Hex(ha1 + ":" + nonce + ":" + ha2)
	}

	return expected == clientResponse
}

func parseDigestParams(s string) map[string]string {
	params := make(map[string]string)
	parts := strings.Split(s, ",")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		idx := strings.IndexByte(part, '=')
		if idx < 0 {
			continue
		}
		key := strings.TrimSpace(part[:idx])
		val := strings.TrimSpace(part[idx+1:])
		val = strings.Trim(val, `"`)
		params[key] = val
	}
	return params
}

func md5Hex(s string) string {
	h := md5.Sum([]byte(s))
	return fmt.Sprintf("%x", h)
}
