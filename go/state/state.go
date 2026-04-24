package state

import "github.com/comcent-io/sip-test-tools/phone"

type ServerState struct {
	Status           string          `json:"status"`
	IPAddress        string          `json:"ipAddress"`
	PublicIPAddress  string          `json:"publicIPAddress"`
	TrunkStatus      string          `json:"trunkStatus"`
	SipTrunk         *phone.SipTrunk `json:"-"`
	Calls            []*phone.Call   `json:"calls"`
	CallIdToStream   string          `json:"callIdToStream"`
	RegisteredAgents any             `json:"registeredAgents,omitempty"`
}
