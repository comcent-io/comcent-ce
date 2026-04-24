package main

import (
	"context"
	"fmt"
	"math/rand"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/comcent-io/sip-test-tools/config"
	"github.com/comcent-io/sip-test-tools/logger"
	"github.com/comcent-io/sip-test-tools/mynet"

	"github.com/comcent-io/sip-test-tools/phone"
	"github.com/comcent-io/sip-test-tools/state"

	"github.com/emiago/diago"
	"github.com/emiago/sipgo/sip"
	"github.com/rs/zerolog/log"
)

var serverState = state.ServerState{
	Status:          "Online",
	IPAddress:       "Unknown",
	PublicIPAddress: "Unknown",
	TrunkStatus:     "Offline",
	SipTrunk:        nil,
}

var inviteAcceptedChannel = make(chan phone.InvitationResponseType)

// generateRandomIndianNumber generates a random Indian phone number using config settings
func generateRandomIndianNumber(cfg *config.Config) string {
	// Use valid first digits from config
	firstDigit := cfg.Calls.PhoneNumbers.ValidFirstDigits

	// Generate the first digit
	number := firstDigit[rand.Intn(len(firstDigit))]

	// Generate remaining digits based on config
	for i := 0; i < cfg.Calls.PhoneNumbers.RemainingDigits; i++ {
		number += strconv.Itoa(rand.Intn(10))
	}

	return cfg.Calls.PhoneNumbers.CountryCode + number
}

// registerSingleAgent registers a single agent and returns the result
func registerSingleAgent(username, password string) (*AgentRegistration, error) {
	// Create agent registration
	agentReg, err := NewAgentRegistration(username, password)
	if err != nil {
		return nil, fmt.Errorf("failed to create registration for %s: %v", username, err)
	}

	// Register the agent
	err = agentReg.Register()
	if err != nil {
		agentReg.Close()
		return nil, fmt.Errorf("failed to register agent %s: %v", username, err)
	}

	return agentReg, nil
}

// registerAllAgents registers all agents from the configuration
func initAllAgents(cfg *config.Config) error {
	log.Info().Msgf("Starting registration for %d agents", len(cfg.Agents))

	var wg sync.WaitGroup
	successCount := int32(0)
	totalCount := len(cfg.Agents)

	for i, agent := range cfg.Agents {
		wg.Add(1)
		go func(username, password string, delay int) {
			defer wg.Done()

			// Add a small delay between registrations to avoid conflicts
			time.Sleep(time.Duration(delay) * 500 * time.Millisecond)

			agentReg, err := registerSingleAgent(username, password)
			if err != nil {
				log.Error().Err(err).Msg("Failed to register agent " + username)
				return
			}

			// Increment success counter atomically
			atomic.AddInt32(&successCount, 1)

			// Set up invite handler for this agent after successful registration
			setupAgentInviteHandler(username, agentReg)

		}(agent.Username, agent.Password, i)
	}

	// Wait for all registrations to complete
	wg.Wait()

	finalSuccessCount := atomic.LoadInt32(&successCount)
	if finalSuccessCount == int32(totalCount) {
		log.Info().Msgf("Successfully registered all %d agents", totalCount)
	} else {
		log.Warn().Msgf("Registered %d out of %d agents", finalSuccessCount, totalCount)
		if finalSuccessCount == 0 {
			return fmt.Errorf("failed to register any agents")
		}
	}
	return nil
}

// setupAgentInviteHandler sets up the invite handler for an agent using diago
func setupAgentInviteHandler(username string, agentReg *AgentRegistration) {
	log.Info().Msgf("Setting up diago invite handler for agent: %s", username)
	agentDiago := agentReg.Diago

	ctx := context.Background()

	// Start diago server for this agent in background
	err := agentDiago.ServeBackground(ctx, func(inDialog *diago.DialogServerSession) {
		log.Info().Msgf("INVITE received for agent: %s", username)

		// Generate random second between 1 to 20
		randomSecond := rand.Intn(20) + 1
		log.Info().Msgf("Random second generated: %d for agent: %s", randomSecond, username)

		if randomSecond > 10 {
			// Do nothing - ignore the invite
			log.Info().Msgf("Random second %d > 10, ignoring invite for agent: %s", randomSecond, username)
			return
		}

		// Random second <= 10, wait for the random seconds
		log.Info().Msgf("Random second %d <= 10, waiting %d seconds for agent: %s", randomSecond, randomSecond, username)
		time.Sleep(time.Duration(randomSecond) * time.Second)

		// Generate random action (0 or 1)
		action := rand.Intn(2)
		log.Info().Msgf("Random action generated: %d for agent: %s", action, username)

		callId := inDialog.ID
		log.Info().Msgf("Call ID from invite received: %s", callId)

		// Send trying response
		inDialog.Trying()

		if action == 1 {
			// Accept the call, wait 60 seconds, then hangup
			log.Info().Msgf("Action 1: Accepting call %s for agent: %s", callId, username)

			// Send ringing response
			inDialog.Ringing()

			// Accept the call
			err := inDialog.Answer()
			if err != nil {
				log.Error().Err(err).Msg("Failed to answer call")
				return
			}

			log.Info().Msgf("Call %s accepted, waiting 60 seconds before hangup for agent: %s", callId, username)

			// Wait for 60 seconds then hangup
			go func() {
				time.Sleep(60 * time.Second)
				log.Info().Msgf("60 seconds elapsed, hanging up call %s for agent: %s", callId, username)

				// Send BYE to hangup the call
				err := inDialog.Hangup(context.Background())
				if err != nil {
					log.Error().Err(err).Msgf("Failed to hangup call %s for agent: %s", callId, username)
				} else {
					log.Info().Msgf("Call %s hung up successfully for agent: %s", callId, username)
				}
			}()
		} else {
			// Reject the call
			log.Info().Msgf("Action 0: Rejecting call %s for agent: %s", callId, username)
			err := inDialog.Respond(sip.StatusBusyHere, "Busy Here", nil)
			if err != nil {
				log.Error().Err(err).Msg("Failed to reject call")
				return
			}
			log.Info().Msgf("Call %s rejected for agent: %s", callId, username)
		}
	})

	if err != nil {
		log.Error().Err(err).Msgf("Failed to start diago server for agent %s", username)
		return
	}

	log.Info().Msgf("Diago server started successfully for agent %s", username)
}

func main() {
	// Load configuration
	if err := config.LoadConfig(); err != nil {
		log.Error().Msgf("Failed to load config: %v", err)
		return
	}
	cfg := config.GetConfig()
	logger.SetUpLogger()

	// Initialize random seed
	rand.Seed(time.Now().UnixNano())

	// Get container IP for internal communication
	containerIP, _ := mynet.GetContainerIP()

	// Use public IP from config for external communication
	publicIP := cfg.Network.PublicIP

	// Set the server state IP address to the container IP for internal communication
	serverState.IPAddress = containerIP

	// Store the public IP for external communication
	serverState.PublicIPAddress = publicIP

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Configure SIP port from config
	sipPort := cfg.SIP.Port
	log.Info().Msgf("Using SIP port from config: %d", sipPort)

	log.Info().Msgf("Creating SIP trunk with diago on port %d", sipPort)
	sipTrunk, err := phone.NewSipTrunk(serverState.IPAddress, sipPort, serverState.IPAddress, inviteAcceptedChannel)
	if err != nil {
		serverState.TrunkStatus = "Failed"
		log.Error().Msgf("Failed to create SIP trunk: %v", err)
		return
	}
	serverState.TrunkStatus = "Online"
	serverState.SipTrunk = sipTrunk

	// Register all agents from configuration
	log.Info().Msg("=== Agent Registration ===")
	if err := initAllAgents(cfg); err != nil {
		log.Error().Err(err).Msg("Failed to register agents")
		// Continue with the simulator even if agent registration fails
	}

	// Get number of calls and queue number from config
	fmt.Println("\n=== SIP Call Simulator ===")

	numCalls := cfg.Calls.NumberOfCalls
	queueNumber := cfg.Calls.QueueNumber

	if numCalls <= 0 {
		log.Error().Msg("Number of calls must be a positive integer")
		return
	}

	if queueNumber == "" {
		log.Error().Msg("Queue number cannot be empty")
		return
	}

	log.Info().Msgf("Making %d calls to %s", numCalls, queueNumber)

	// Create the to URI once
	toUri := sip.Uri{User: queueNumber, Host: "acme.comcent.io"}

	// Make multiple calls with 5-second delay between each
	for i := 0; i < numCalls; i++ {
		// Generate random Indian phone number for this call using config
		fromNumber := generateRandomIndianNumber(cfg)

		log.Info().Msgf("Call %d/%d: Making call from %s to %s", i+1, numCalls, fromNumber, queueNumber)

		// Create SIP URI for the from number
		fromUri := sip.Uri{User: fromNumber, Host: "localhost"}

		// Make the call
		serverState.SipTrunk.MakeCall(toUri, 0, fromUri)

		// Wait 5 seconds before making the next call (except for the last call)
		if i < numCalls-1 {
			log.Info().Msg("Waiting 5 seconds before next call...")
			time.Sleep(10 * time.Second)
		}
	}

	log.Info().Msgf("All %d calls initiated. Press Ctrl+C to exit.", numCalls)

	<-ctx.Done()
	log.Info().Msg("Server is shutting down")
}
