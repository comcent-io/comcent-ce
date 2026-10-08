#!/bin/sh
# Behaves like a consumer router between LAN_IP's network and WAN_IP's:
#
#   * LAN hosts reach the WAN through one masqueraded address, on a random
#     source port per mapping (--random-fully), so an expired mapping does not
#     come back on the same port.
#   * Only replies to a live mapping get in: a packet from the WAN is let
#     through only when conntrack matches it to traffic the LAN host sent to
#     that same address and port. Anything else is dropped without an answer.
#   * A UDP mapping that sees no traffic for NAT_UDP_TIMEOUT seconds is
#     forgotten. Real routers use 30 s to a few minutes; tests use a few
#     seconds so they don't have to wait.
#
# The conntrack timeouts are per network namespace, so they are set with the
# service's `sysctls` in compose and only checked here.
set -eu

: "${LAN_IP:?LAN_IP is required}"
: "${WAN_IP:?WAN_IP is required}"
timeout="${NAT_UDP_TIMEOUT:-10}"

iface_with() {
  ip -o -4 addr show | awk -v ip="$1" 'index($4, ip "/") == 1 { print $2 }'
}

lan_if="$(iface_with "$LAN_IP")"
wan_if="$(iface_with "$WAN_IP")"
if [ -z "$lan_if" ] || [ -z "$wan_if" ]; then
  echo "nat-router: no interface for LAN $LAN_IP ($lan_if) or WAN $WAN_IP ($wan_if)" >&2
  ip -o -4 addr show >&2
  exit 1
fi

iptables -t nat -A POSTROUTING -o "$wan_if" -j MASQUERADE --random-fully

iptables -P FORWARD DROP
iptables -A FORWARD -i "$lan_if" -o "$wan_if" -j ACCEPT
iptables -A FORWARD -i "$wan_if" -o "$lan_if" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# A packet for an expired mapping is addressed to the router itself. Drop it
# rather than answer with ICMP port unreachable, as a home router does.
iptables -A INPUT -i "$wan_if" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$wan_if" -j DROP

for name in nf_conntrack_udp_timeout nf_conntrack_udp_timeout_stream; do
  value="$(cat "/proc/sys/net/netfilter/$name")"
  if [ "$value" != "$timeout" ]; then
    echo "nat-router: $name is $value, want $timeout (set it in the service's sysctls)" >&2
    exit 1
  fi
done

echo "nat-router: LAN $LAN_IP ($lan_if) -> WAN $WAN_IP ($wan_if), UDP mappings expire after ${timeout}s idle"

# Log mappings as they are made and forgotten, for debugging a failed run.
exec conntrack -E -p udp -o timestamp
