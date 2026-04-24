#!/usr/bin/perl
# play_pcap.pl — replay a libpcap file as RTP UDP datagrams to a specified host:port.
#
# Usage: perl play_pcap.pl <file.pcap> <dst_ip> <dst_port>
#
# Sends each UDP payload (Ethernet+IP+UDP headers stripped) at the timing
# recorded in the PCAP timestamps.  Used in place of SIPp play_pcap_audio
# when the SDP c= line contains an IP unreachable from inside the Docker
# network (e.g. 127.0.0.1 on Mac Docker Desktop where ext-rtp-ip=127.0.0.1
# but FreeSwitch actually binds on the container IP 172.29.17.8).
use strict;
use warnings;
use IO::Socket::INET;
use Socket qw(sockaddr_in inet_aton);
use Time::HiRes qw(time sleep);

my ($file, $dst_ip, $dst_port) = @ARGV;
die "Usage: $0 <file.pcap> <dst_ip> <dst_port>\n" unless @ARGV == 3;

open my $fh, '<:raw', $file or die "Cannot open '$file': $!\n";

# ── PCAP global header (24 bytes) ────────────────────────────────────────────
read($fh, my $gh, 24) == 24 or die "Truncated PCAP global header\n";
my ($magic) = unpack 'V', $gh;
die "Not a PCAP file (magic=0x" . sprintf('%08x', $magic) . ")\n"
    unless $magic == 0xa1b2c3d4;

# ── UDP socket (unconnected) ──────────────────────────────────────────────────
# Use an unconnected socket so that ICMP port-unreachable responses from the
# remote end are NOT delivered as ECONNREFUSED on subsequent send() calls.
# Connected sockets surface ICMP errors which causes every other send to fail.
my $sock = IO::Socket::INET->new(Proto => 'udp')
    or die "Cannot create UDP socket: $!\n";

my $dst_addr = sockaddr_in(int($dst_port), inet_aton($dst_ip))
    or die "Cannot resolve $dst_ip:$dst_port\n";

# ── Replay loop ───────────────────────────────────────────────────────────────
# ETH (14) + IP (20) + UDP (8) = 42 bytes to strip before the RTP payload.
my $ETH_IP_UDP = 42;
my ($t0_pcap, $t0_real);

while (read($fh, my $rh, 16) == 16) {
    my ($ts_sec, $ts_usec, $caplen, $origlen) = unpack 'VVVV', $rh;

    my $pkt = '';
    read($fh, $pkt, $caplen);

    next if $caplen <= $ETH_IP_UDP;   # skip malformed/non-RTP records

    my $pts = $ts_sec + $ts_usec / 1_000_000;
    $t0_pcap //= $pts;
    $t0_real //= time();

    my $send_at = $t0_real + ($pts - $t0_pcap);
    my $delay   = $send_at - time();
    sleep($delay) if $delay > 0.000_1;

    $sock->send(substr($pkt, $ETH_IP_UDP), 0, $dst_addr)
        or warn "UDP send to $dst_ip:$dst_port failed: $!\n";
}

close $fh;
