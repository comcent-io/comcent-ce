package config

import (
	"fmt"
	"net"
	"os"
	"path/filepath"

	"github.com/comcent-io/sip-test-tools/mynet"
	"gopkg.in/yaml.v3"
)

// Config represents the application configuration structure
type Config struct {
	SIP struct {
		Domain string `yaml:"domain"`
		Port int `yaml:"port"`
	} `yaml:"sip"`

	WebRTC struct {
		PortStart int `yaml:"portStart"`
		PortEnd   int `yaml:"portEnd"`
	} `yaml:"webrtc"`

	Network struct {
		PublicIP string `yaml:"publicIP"`
	} `yaml:"network"`

	Kamailio struct {
		StaticIP    string `yaml:"staticIP"`
		LocalhostIP string `yaml:"localhostIP"`
		Port        int    `yaml:"port"`
	} `yaml:"kamailio"`

	LogLevel string `yaml:"logLevel"`
	Env      string `yaml:"env"`

	Calls struct {
		PhoneNumbers struct {
			CountryCode      string   `yaml:"countryCode"`
			ValidFirstDigits []string `yaml:"validFirstDigits"`
			RemainingDigits  int      `yaml:"remainingDigits"`
		} `yaml:"phoneNumbers"`
		QueueNumber   string `yaml:"queueNumber"`
		NumberOfCalls int    `yaml:"numberOfCalls"`
	} `yaml:"calls"`

	Agents []struct {
		Username string `yaml:"username"`
		Password string `yaml:"password"`
	} `yaml:"agents"`
}

var AppConfig *Config

// LoadConfig loads the configuration from config.yml file
func LoadConfig() error {
	// Get the directory where the executable is located
	execPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get executable path: %v", err)
	}
	execDir := filepath.Dir(execPath)

	// Look for config.yml in the same directory as the executable
	configPath := filepath.Join(execDir, "config.yml")

	// If config.yml is not found in the executable directory, try the current working directory
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		configPath = "config.yml"
	}

	// Read the config file
	data, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("failed to read config file: %v", err)
	}

	// Parse the YAML
	AppConfig = &Config{}
	if err := yaml.Unmarshal(data, AppConfig); err != nil {
		return fmt.Errorf("failed to parse config file: %v", err)
	}

	return nil
}

// GetConfig returns the loaded configuration
func GetConfig() *Config {
	if AppConfig == nil {
		// Load config if not already loaded
		if err := LoadConfig(); err != nil {
			// If loading fails, return a default config
			AppConfig = &Config{
				SIP: struct {
					Domain string `yaml:"domain"`
					Port int `yaml:"port"`
				}{Port: 5061},
				WebRTC: struct {
					PortStart int `yaml:"portStart"`
					PortEnd   int `yaml:"portEnd"`
				}{PortStart: 10000, PortEnd: 10010},
				Network: struct {
					PublicIP string `yaml:"publicIP"`
				}{PublicIP: "192.168.31.23"},
				Kamailio: struct {
					StaticIP    string `yaml:"staticIP"`
					LocalhostIP string `yaml:"localhostIP"`
					Port        int    `yaml:"port"`
				}{StaticIP: "172.31.17.9", LocalhostIP: "127.0.0.1", Port: 5060},
				LogLevel: "info",
				Env:      "dev",
				Calls: struct {
					PhoneNumbers struct {
						CountryCode      string   `yaml:"countryCode"`
						ValidFirstDigits []string `yaml:"validFirstDigits"`
						RemainingDigits  int      `yaml:"remainingDigits"`
					} `yaml:"phoneNumbers"`
					QueueNumber   string `yaml:"queueNumber"`
					NumberOfCalls int    `yaml:"numberOfCalls"`
				}{
					PhoneNumbers: struct {
						CountryCode      string   `yaml:"countryCode"`
						ValidFirstDigits []string `yaml:"validFirstDigits"`
						RemainingDigits  int      `yaml:"remainingDigits"`
					}{
						CountryCode:      "+91",
						ValidFirstDigits: []string{"6", "7", "8", "9"},
						RemainingDigits:  9,
					},
					QueueNumber:   "+919611828661",
					NumberOfCalls: 1,
				},
			}
		}
	}
	return AppConfig
}

// GetKamailioIP returns the appropriate Kamailio IP based on the environment
// If running in Docker (detected by container IP), returns StaticIP
// If running locally, returns LocalhostIP
func GetKamailioIP() string {
	config := GetConfig()

	// Check if we're running in Docker by looking for Docker-specific indicators
	// First, check if we're in a Docker container by looking for /.dockerenv file
	if _, err := os.Stat("/.dockerenv"); err == nil {
		// We're definitely in a Docker container
		if config.Kamailio.StaticIP != "" {
			return config.Kamailio.StaticIP
		}
	}

	// Try to get container IP to detect if we're in Docker
	containerIP, err := mynet.GetContainerIP()
	if err != nil {
		// If we can't get container IP, we're likely running locally
		if config.Kamailio.LocalhostIP != "" {
			return config.Kamailio.LocalhostIP
		}
		return config.Kamailio.StaticIP
	}

	// Check if the container IP is in a Docker network range
	// Docker typically uses 172.17.x.x to 172.31.x.x (Docker default networks)
	if isDockerNetworkIP(containerIP) {
		// We're likely in Docker environment
		if config.Kamailio.StaticIP != "" {
			return config.Kamailio.StaticIP
		}
	}

	// Default to localhost for local development
	if config.Kamailio.LocalhostIP != "" {
		return config.Kamailio.LocalhostIP
	}

	// Fallback to static IP if nothing else is configured
	return config.Kamailio.StaticIP
}

// isDockerNetworkIP checks if the given IP is in a Docker network range
// Docker typically uses 172.17.x.x to 172.31.x.x for default networks
func isDockerNetworkIP(ip string) bool {
	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		return false
	}

	// Check if it's in the 172.17.0.0/12 range (172.17.0.0 to 172.31.255.255)
	// This covers Docker's default network range
	if parsedIP.To4() != nil {
		ipv4 := parsedIP.To4()
		// Check if it's 172.x.x.x and x is between 17-31
		if ipv4[0] == 172 && ipv4[1] >= 17 && ipv4[1] <= 31 {
			return true
		}
	}

	return false
}
