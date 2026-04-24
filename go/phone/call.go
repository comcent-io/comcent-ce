package phone

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"time"

	"github.com/emiago/diago"
	"github.com/emiago/diago/media"
	"github.com/emiago/sipgo/sip"
	"github.com/pion/rtp"
	"github.com/rs/zerolog/log"
)

type Call struct {
	CallId              string                     `json:"callId"`
	FromNumber          string                     `json:"fromNumber"`
	ToNumber            string                     `json:"toNumber"`
	StartedAt           time.Time                  `json:"startedAt"`
	State               string                     `json:"state"`
	Direction           string                     `json:"direction"`
	DialogServerSession *diago.DialogServerSession `json:"-"`
	DialogClientSession *diago.DialogClientSession `json:"-"`
	mediaSession        *media.MediaSession        `json:"-"`
	outboundAudioPacket rtp.Packet                 `json:"-"`
	Instructions        chan string                `json:"-"`
	IsAudioConnected    bool                       `json:"isAudioConnected"`
}

func (call *Call) WriteRtpRaw(payload []byte) error {
	call.outboundAudioPacket.Payload = payload
	err := call.mediaSession.WriteRTP(&call.outboundAudioPacket)
	if err != nil {
		log.Error().Err(err).Msg("Fail to send RTP")
		return err
	}
	call.outboundAudioPacket.SequenceNumber++
	call.outboundAudioPacket.Timestamp += 160
	return nil
}

func (call *Call) ReadRtpRaw() ([]byte, error) {
	buf := make([]byte, media.RTPBufSize)
	n, err := call.mediaSession.ReadRTPRawDeadline(buf, time.Now().Add(50*time.Millisecond))
	if err != nil {
		log.Debug().Err(err).Msg("Failed to read RTP packet")
		return nil, err
	}
	if n > 0 {
		var rtpPacket rtp.Packet
		err := rtpPacket.Unmarshal(buf[:n])
		if err != nil {
			log.Error().Err(err).Msg("Failed to unmarshal RTP packet")
			return nil, err
		}
		return rtpPacket.Payload, nil
	}
	return nil, nil
}

func (call *Call) Init() {
	call.outboundAudioPacket = rtp.Packet{
		Header: rtp.Header{
			Version:        2,
			Padding:        false,
			Extension:      false,
			Marker:         false,
			PayloadType:    0,
			SequenceNumber: uint16(rand.Intn(65536)),           // Random 16-bit number
			Timestamp:      uint32(time.Now().UnixMilli() * 8), // Random 32-bit number
			SSRC:           uint32(rand.Intn(1 << 32)),         // Random 32-bit number
		},
	}
}

func (call *Call) AcceptInvite(publicIp net.IP, privateIp net.IP) error {
	call.State = "CONNECTED"

	err := call.DialogServerSession.Answer()
	if err != nil {
		log.Error().Err(err).Msg("Failed to answer invite")
		return err
	}

	call.mediaSession = call.DialogServerSession.MediaSession()

	log.Info().
		Str("localAddr", call.mediaSession.Laddr.String()).
		Str("remoteAddr", call.mediaSession.Raddr.String()).
		Msg("Media session created for incoming call by diago")

	call.Init()

	fmt.Println("call accepted")
	return nil
}

func (call *Call) RejectInvite() {
	call.State = "REJECTED"
	call.DialogServerSession.Respond(sip.StatusBusyHere, "Busy Here", nil)
}

func (call *Call) Hangup() {
	call.State = "HANGUP"
	call.DialogServerSession.Hangup(context.Background())
}

func (call *Call) ReadBye(req *sip.Request, tx sip.ServerTransaction) error {
	call.State = "HANGUP"
	log.Info().Msg("BYE received - call will be terminated by diago automatically")
	return nil
}
