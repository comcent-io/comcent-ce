package main

import "os"

type Config struct {
	PublicIP           string
	PrivateIP          string
	InternalAPIBaseURL string
	InternalAPIUser    string
	InternalAPIPass    string
	RPCAPIToken        string
}

func loadConfig() Config {
	return Config{
		PublicIP:           envOrDefault("PUBLIC_IP", "127.0.0.1"),
		PrivateIP:          envOrDefault("PRIVATE_IP", "127.0.0.1"),
		InternalAPIBaseURL: envOrDefault("INTERNAL_API_BASE_URL", "http://server:4000/internal-api"),
		InternalAPIUser:    envOrDefault("INTERNAL_API_USERNAME", ""),
		InternalAPIPass:    envOrDefault("INTERNAL_API_PASSWORD", ""),
		RPCAPIToken:        envOrDefault("RPC_API_TOKEN", ""),
	}
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
