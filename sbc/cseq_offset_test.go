package main

import (
	"testing"

	"github.com/emiago/sipgo/sip"
)

// After the SBC answers a trunk's digest challenge, the trunk saw the INVITE
// with CSeq n+1 while FS still counts from n. FS's ACK (and later BYE) must
// reach the trunk shifted by that offset, while the response relayed back to
// FS keeps FS's own number.
func TestShiftCSeqOnTheForwardedCopyOnly(t *testing.T) {
	ack := sip.NewRequest(sip.ACK, sip.Uri{User: "+14155550123", Host: "acme.pstn.twilio.com"})
	ack.AppendHeader(&sip.CSeqHeader{SeqNo: 301, MethodName: sip.ACK})

	p := &Proxy{}
	fwd, ok := p.buildForwardRequestWithURI(ack, sip.Uri{User: "+14155550123", Host: "acme.pstn.twilio.com"})
	if !ok {
		t.Fatal("could not build the forwarded request")
	}
	shiftCSeq(fwd, 1)

	if got := fwd.CSeq().SeqNo; got != 302 {
		t.Errorf("forwarded ACK CSeq = %d, want 302 (the authenticated INVITE's)", got)
	}
	if got := ack.CSeq().SeqNo; got != 301 {
		t.Errorf("FS's own request CSeq = %d, want 301 unchanged", got)
	}
}

// sipgo's DoDigestAuth increments the CSeq of the forwarded request in place,
// so the offset has to come from FS's original INVITE. Production calls
// dropped at 32 seconds while it was read from the forwarded copy.
func TestDigestCSeqOffsetComparesAgainstFSRequest(t *testing.T) {
	invite := sip.NewRequest(sip.INVITE, sip.Uri{User: "+14155550123", Host: "acme.pstn.twilio.com"})
	invite.AppendHeader(&sip.CSeqHeader{SeqNo: 301, MethodName: sip.INVITE})

	p := &Proxy{}
	fwd, ok := p.buildForwardRequestWithURI(invite, invite.Recipient)
	if !ok {
		t.Fatal("could not build the forwarded request")
	}
	fwd.CSeq().SeqNo++ // what DoDigestAuth does before resending

	ok200 := sip.NewResponseFromRequest(fwd, 200, "OK", nil)
	if got := digestCSeqOffset(invite, ok200); got != 1 {
		t.Errorf("offset = %d, want 1", got)
	}
}

func TestShiftCSeqWithoutOffsetLeavesItAlone(t *testing.T) {
	bye := sip.NewRequest(sip.BYE, sip.Uri{Host: "example.com"})
	bye.AppendHeader(&sip.CSeqHeader{SeqNo: 7, MethodName: sip.BYE})
	shiftCSeq(bye, 0)
	if got := bye.CSeq().SeqNo; got != 7 {
		t.Errorf("CSeq = %d, want 7", got)
	}
}
