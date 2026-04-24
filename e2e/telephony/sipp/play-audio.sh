#!/bin/sh
# Plays /tmp/customer-audio.pcap toward FreeSwitch using the far-side RTP port
# from the SIPp messages log.
#
# Usage:
#   sh /scenarios/play-audio.sh        # UAS — port comes from the first
#                                      # m=audio line (received INVITE)
#   sh /scenarios/play-audio.sh 2      # UAC — port comes from the second
#                                      # m=audio line (our sent INVITE is
#                                      # first, received 200 OK is second)
#
# Called from uas-answer-pcap*.xml / uac-remote-bye-pcap.xml via <exec> after
# the ACK exchange so FreeSwitch has already advertised its RTP port.

index=${1:-1}

log=$(ls -t /tmp/*_messages.log 2>/dev/null | head -1)
port=$(awk -v n="$index" '/m=audio/{ c++; if (c == n) { print $2; exit } }' "$log")

echo "$(date -u +%H:%M:%S) play-audio: log=$log index=$index port=$port" \
  >> /tmp/play-audio.log 2>&1

perl /scenarios/play_pcap.pl /tmp/customer-audio.pcap 172.29.17.8 "$port" \
  >> /tmp/play-audio.log 2>&1 &
