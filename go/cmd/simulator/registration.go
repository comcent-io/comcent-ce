package main

import (
	"context"
	"fmt"
	"strconv"

	"github.com/comcent-io/sip-test-tools/config"
	"github.com/emiago/diago"
	"github.com/emiago/sipgo"
	"github.com/emiago/sipgo/sip"
	"github.com/rs/zerolog/log"
)

type AgentRegistration struct {
	Username   string
	Password   string
	Diago      *diago.Diago
	UA         *sipgo.UserAgent
	Registered bool
	Context    context.Context
	Cancel     context.CancelFunc
}

// NewAgentRegistration creates a new agent registration instance
func NewAgentRegistration(username, password string) (*AgentRegistration, error) {
	cfg := config.GetConfig()
	sipDomain := cfg.SIP.Domain
	publicIP := cfg.Network.PublicIP

	ua, err := sipgo.NewUA(
		sipgo.WithUserAgent(username),
		sipgo.WithUserAgentHostname(sipDomain),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create user agent: %v", err)
	}

	// Configure diago with UDP transport
	dg := diago.NewDiago(ua, diago.WithTransport(diago.Transport{
		Transport:    "udp",
		BindHost:     "0.0.0.0",
		BindPort:     0,
		ExternalHost: publicIP,
		ExternalPort: 0,
	}), diago.WithAuth(sipgo.DigestAuth{
		Username: username,
		Password: password,
	}))

	ctx, cancel := context.WithCancel(context.Background())

	return &AgentRegistration{
		Username:   username,
		Password:   password,
		Diago:      dg,
		UA:         ua,
		Registered: false,
		Context:    ctx,
		Cancel:     cancel,
	}, nil
}

// Register registers the agent with the SIP server using diago.Register
func (ar *AgentRegistration) Register() error {
	log.Info().Msgf("Registering agent: %s", ar.Username)

	cfg := config.GetConfig()
	kamailioIP := config.GetKamailioIP()
	kamailioPort := cfg.Kamailio.Port
	sipDomain := cfg.SIP.Domain

	// Create the registration URI - this is where we want to register
	regURI := sip.Uri{
		User: ar.Username,
		Host: sipDomain,
	}

	// Configure registration options
	registerOptions := diago.RegisterOptions{
		Username:  ar.Username,
		Password:  ar.Password,
		ProxyHost: kamailioIP + ":" + strconv.Itoa(kamailioPort),
	}

	// Use diago's RegisterTransaction for more control
	regTx, err := ar.Diago.RegisterTransaction(ar.Context, regURI, registerOptions)
	if err != nil {
		return fmt.Errorf("failed to create register transaction for agent %s: %v", ar.Username, err)
	}

	// Perform a single registration (not continuous)
	err = regTx.Register(ar.Context)
	if err != nil {
		return fmt.Errorf("failed to register agent %s: %v", ar.Username, err)
	}

	ar.Registered = true
	log.Info().Msgf("Agent %s registered successfully", ar.Username)
	return nil
}

// Unregister unregisters the agent from the SIP server
func (ar *AgentRegistration) Unregister() error {
	if !ar.Registered {
		return nil
	}

	log.Info().Msgf("Unregistering agent: %s", ar.Username)

	cfg := config.GetConfig()
	kamailioIP := config.GetKamailioIP()
	kamailioPort := cfg.Kamailio.Port
	sipDomain := cfg.SIP.Domain

	// Create the registration URI
	regURI := sip.Uri{
		User: ar.Username,
		Host: sipDomain,
	}

	// Configure unregistration options (same as registration but diago handles expiry)
	registerOptions := diago.RegisterOptions{
		Username:  ar.Username,
		Password:  ar.Password,
		ProxyHost: kamailioIP + ":" + strconv.Itoa(kamailioPort),
		Expiry:    0,
	}

	// Use diago's Register method with 0 expiry to unregister
	regTx, err := ar.Diago.RegisterTransaction(ar.Context, regURI, registerOptions)
	if err != nil {
		log.Warn().Err(err).Msgf("Failed to unregister agent %s, but continuing", ar.Username)
	} else {
		err = regTx.Unregister(ar.Context)
		if err != nil {
			log.Warn().Err(err).Msgf("Failed to unregister agent %s, but continuing", ar.Username)
		} else {
			log.Info().Msgf("Agent %s unregistered successfully", ar.Username)
		}
	}

	ar.Registered = false
	return nil
}

// Close closes the registration and cleans up resources
func (ar *AgentRegistration) Close() {
	if ar.Registered {
		ar.Unregister()
	}
	if ar.UA != nil {
		ar.UA.Close()
	}
	ar.Cancel()
}
