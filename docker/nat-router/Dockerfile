# A home router for the e2e stack: the kernel's own NAT (iptables masquerade
# and conntrack), with the idle timeout of a UDP mapping set low enough to
# test against. See entrypoint.sh.
FROM alpine:3.20

RUN apk add --no-cache iptables iproute2 conntrack-tools

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
