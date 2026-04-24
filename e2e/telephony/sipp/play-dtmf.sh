#!/bin/sh
# Plays /tmp/dtmf.pcap toward FreeSwitch's RTP port.
#
# Usage:
#   sh /scenarios/play-dtmf.sh        # UAS — port from first m=audio
#   sh /scenarios/play-dtmf.sh 2      # UAC — port from second m=audio
#
# Called from UAC scenarios after ACK to inject RFC 2833 DTMF events into the
# RTP stream.  The PCAP contains fake Ethernet+IP+UDP headers that play_pcap.pl
# strips before sending the RTP payload as a UDP datagram.

index=${1:-2}

log=$(ls -t /tmp/*_messages.log 2>/dev/null | head -1)
port=$(awk -v n="$index" '/m=audio/{ c++; if (c == n) { print $2; exit } }' "$log")

echo "$(date -u +%H:%M:%S) play-dtmf: log=$log index=$index port=$port" \
  >> /tmp/play-dtmf.log 2>&1

perl /scenarios/play_pcap.pl /tmp/dtmf.pcap 172.29.17.8 "$port" \
  >> /tmp/play-dtmf.log 2>&1
