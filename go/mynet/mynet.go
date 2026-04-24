package mynet

import (
	"fmt"
	"io"
	"net"
	"net/http"
)

func getPublicIp() (*string, error) {
	resp, err := http.Get("https://api.ipify.org?format=text")
	if err != nil {
		fmt.Println("Error:", err)
		return nil, err
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {
			fmt.Println("Error:", err)
		}
	}(resp.Body)

	ip, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("Error:", err)
		return nil, err
	}
	ipStr := string(ip)
	return &ipStr, nil
}

func GetContainerIP() (string, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", fmt.Errorf("error getting network interfaces: %w", err)
	}

	var ipv4Candidates []string
	var ipv6Candidates []string

	for _, iface := range interfaces {
		// Ignore interfaces that are down or not connected.
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			return "", fmt.Errorf("error getting addresses for interface %s: %w", iface.Name, err)
		}

		for _, addr := range addrs {
			// Extract IP address.
			switch v := addr.(type) {
			case *net.IPNet:
				ip := v.IP
				if ip.IsGlobalUnicast() && !ip.IsLoopback() && !ip.IsMulticast() {
					if ip.To4() != nil {
						// IPv4 address
						ipv4Candidates = append(ipv4Candidates, ip.String())
					} else {
						// IPv6 address
						ipv6Candidates = append(ipv6Candidates, ip.String())
					}
				}
			case *net.IPAddr:
				ip := v.IP
				if ip.IsGlobalUnicast() && !ip.IsLoopback() && !ip.IsMulticast() {
					if ip.To4() != nil {
						// IPv4 address
						ipv4Candidates = append(ipv4Candidates, ip.String())
					} else {
						// IPv6 address
						ipv6Candidates = append(ipv6Candidates, ip.String())
					}
				}
			}
		}
	}

	// Prefer IPv4 addresses over IPv6
	if len(ipv4Candidates) > 0 {
		return ipv4Candidates[0], nil
	}

	// Fall back to IPv6 if no IPv4 is available
	if len(ipv6Candidates) > 0 {
		return ipv6Candidates[0], nil
	}

	return "", fmt.Errorf("no valid IP address found")
}
