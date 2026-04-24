package phone

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"net"
	"time"

	"github.com/comcent-io/sip-test-tools/config"
	"github.com/emiago/diago"
	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	"github.com/rs/zerolog/log"
)

type SipTrunk struct {
	ua                    *sipgo.UserAgent
	diago                 *diago.Diago
	privateIp             net.IP
	publicIp              net.IP
	port                  int
	proxy                 string
	Calls                 []*Call
	InviteAcceptedChannel chan InvitationResponseType `json:"-"`
	context               context.Context
}

func NewSipTrunk(privateIp string, port int, proxy string, inviteAcceptedChannel chan InvitationResponseType) (*SipTrunk, error) {
	ua, err := sipgo.NewUA()
	if err != nil {
		log.Fatal().Err(err).Msg("Fail to setup user agent")
	}

	// Configure diago with UDP transport
	dg := diago.NewDiago(ua, diago.WithTransport(diago.Transport{
		Transport:    "udp",
		BindHost:     "0.0.0.0",
		BindPort:     port,
		ExternalHost: privateIp,
		ExternalPort: port,
	}))
	ctx, _ := context.WithCancel(context.Background())

	cfg := config.GetConfig()
	publicIp := cfg.Network.PublicIP

	sipTrunk := &SipTrunk{
		ua:                    ua,
		diago:                 dg,
		privateIp:             net.ParseIP(privateIp),
		publicIp:              net.ParseIP(publicIp),
		port:                  port,
		proxy:                 proxy,
		InviteAcceptedChannel: inviteAcceptedChannel,
		context:               ctx,
		Calls:                 []*Call{},
	}

	go sipTrunk.ListenToWebsocketMessage()

	// Start diago server in background so NewSipTrunk can return
	log.Info().Msgf("Starting diago server on %s:%d", "0.0.0.0", port)
	err = dg.ServeBackground(ctx, func(inDialog *diago.DialogServerSession) {
		log.Info().Msg("INVITE received")
		callId := inDialog.ID
		fmt.Println("call id from invite received: ", callId)
		inDialog.Trying()
		call := Call{
			CallId:              callId,
			FromNumber:          inDialog.FromUser(),
			ToNumber:            inDialog.ToUser(),
			StartedAt:           time.Now(),
			State:               "RINGING",
			DialogServerSession: inDialog,
			Direction:           "in",
			Instructions:        make(chan string),
			IsAudioConnected:    false,
		}

		// Set up automatic call cleanup when dialog closes (BYE received from either side)
		inDialog.OnClose(func() error {
			log.Info().Str("callId", call.CallId).Msg("Incoming dialog closed - removing call from active sessions")
			sipTrunk.RemoveCallById(call.CallId)
			return nil
		})

		sipTrunk.AddCall(&call)
		inDialog.Ringing()

		select {
		case instruction := <-call.Instructions:
			if instruction == "accept" {
				call.AcceptInvite(sipTrunk.publicIp, sipTrunk.privateIp)
			}
		case <-inDialog.Context().Done():
			log.Info().Msg("Dialog server session closed")
			break
		}
	})

	if err != nil {
		log.Error().Err(err).Msg("Failed to start diago server")
		return nil, err
	}

	log.Info().Msg("Diago server started successfully")
	return sipTrunk, nil
}

func (sipTrunk *SipTrunk) MakeCall(toUri sip.Uri, index int, fromUri sip.Uri) error {

	cfg := config.GetConfig()
	kamailioIp := config.GetKamailioIP()
	kamailioPort := cfg.Kamailio.Port

	fromHeader := sip.FromHeader{
		Address: fromUri,
		Params:  sip.NewParams().Add("tag", fmt.Sprintf("%d", rand.Intn(1000000))),
	}

	toHeader := sip.ToHeader{
		Address: toUri,
		Params:  sip.NewParams(),
	}

	headers := []sip.Header{&fromHeader, &toHeader}

	destinationUri := sip.Uri{
		Scheme: "sip",
		Host:   kamailioIp,
		Port:   kamailioPort,
	}

	opts := diago.InviteOptions{
		Transport: "udp",
		Headers:   headers,
		OnResponse: func(res *sip.Response) error {
			log.Info().
				Int("code", int(res.StatusCode)).
				Msg("Call answered")
			return nil
		},
	}

	dialogClientSession, err := sipTrunk.diago.Invite(sipTrunk.context, destinationUri, opts)
	if err != nil {
		log.Error().Err(err).Msg("Error while sending INVITE")
		return err
	}

	mediaSession := dialogClientSession.MediaSession()
	log.Info().
		Str("localAddr", mediaSession.Laddr.String()).
		Str("remoteAddr", mediaSession.Raddr.String()).
		Msg("Media/RTP session created by diago")

	call := &Call{
		CallId:              dialogClientSession.ID,
		FromNumber:          fromUri.User,
		ToNumber:            toUri.User,
		StartedAt:           time.Now(),
		DialogClientSession: dialogClientSession,
		State:               "CONNECTED",
		Direction:           "out",
		mediaSession:        mediaSession,
		IsAudioConnected:    false,
	}

	call.Init()

	dialogClientSession.OnClose(func() error {
		log.Info().Str("callId", call.CallId).Msg("Dialog closed - removing call from active sessions")
		sipTrunk.RemoveCallById(call.CallId)
		return nil
	})

	sipTrunk.AddCall(call)
	return nil
}

func (sipTrunk *SipTrunk) Hangup(callId string) error {
	call := sipTrunk.FindCallByID(callId)
	if call == nil {
		log.Warn().Msgf("Call with ID not found in active sessions")
		return errors.New("call not found")
	}

	var err error
	if call.Direction == "out" {
		err = call.DialogClientSession.Bye(sipTrunk.context)
		if err != nil {
			log.Error().Err(err).Msg("Failed to send BYE")
			return err
		}
	} else if call.Direction == "in" {
		if call.State == "CONNECTED" {
			call.Hangup()
		} else {
			call.RejectInvite()
		}

	}
	sipTrunk.RemoveCallById(callId)
	return nil
}

func (sipTrunk *SipTrunk) RemoveCallById(callId string) {
	for i, call := range sipTrunk.Calls {
		if call.CallId == callId {
			sipTrunk.Calls = append(sipTrunk.Calls[:i], sipTrunk.Calls[i+1:]...)
			return
		}
	}
	log.Warn().Msgf("Call with ID not found")
}

func (sipTrunk *SipTrunk) FindCallByID(callId string) *Call {
	for i := range sipTrunk.Calls {
		if sipTrunk.Calls[i].CallId == callId {
			return sipTrunk.Calls[i]
		}
	}
	return nil
}

func (sipTrunk *SipTrunk) AddCall(call *Call) {
	sipTrunk.Calls = append(sipTrunk.Calls, call)
}

func (sipTrunk *SipTrunk) AcceptInvite(callId string) error {
	call := sipTrunk.FindCallByID(callId)
	if call == nil {
		log.Error().Msgf("Call not found for ID: %s", callId)
		return errors.New("call not found")
	}

	select {
	case call.Instructions <- "accept":
		return nil
	default:
		return errors.New("failed to send accept instruction")
	}
}

func (sipTrunk *SipTrunk) ListenToWebsocketMessage() {
	for {
		inviteAcceptedData := <-sipTrunk.InviteAcceptedChannel
		if inviteAcceptedData.IsAccepted {
			currentCall := sipTrunk.FindCallByID(inviteAcceptedData.CallId)
			if currentCall == nil {
				log.Error().Msgf("Call not found for ID: %s", inviteAcceptedData.CallId)
				continue
			}
			select {
			case currentCall.Instructions <- "accept":
			default:
			}
		}
	}
}
