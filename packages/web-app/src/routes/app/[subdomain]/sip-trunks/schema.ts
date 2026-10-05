import * as z from 'zod';

export const OUTBOUND_CONTACT_HINT =
  'Use host, host:port, sip:host or sip:host:port, e.g. sip:sip.example.com:5060';

type OutboundContactResult = { ok: true; value: string } | { ok: false; message: string };

// Mirrors Comcent.OutboundContact.normalize/1 on the server, which has the
// final say. The value is stored as the bare host or host:port: FreeSWITCH
// dials it after an "@" and the SBC splits it on ":" into host and port, so
// a "sip:" prefix is dropped, and what neither can honour is refused: sips:
// (no TLS leg to carriers), URI parameters such as ;transport=tcp, a user@
// part, and IPv6 (its colons can't be told from the port separator).
export function normalizeOutboundContact(input: string): OutboundContactResult {
  const fail = (message: string): OutboundContactResult => ({
    ok: false,
    message: `${message}. ${OUTBOUND_CONTACT_HINT}`,
  });
  const value = input.trim();

  if (value === '') return fail('Enter the SIP proxy address');
  if (/\s/.test(value)) return fail('The SIP proxy address must not contain spaces');
  if (/^sips:/i.test(value)) {
    return { ok: false, message: 'sips: (TLS) is not supported. Use sip:host or sip:host:port' };
  }

  const address = value.replace(/^sip:/i, '');
  if (address.includes(';')) {
    return fail('URI parameters such as ;transport=tcp are not supported (calls go out over UDP)');
  }
  if (address.includes('@')) return fail('Enter the address only, without a user@ part');
  if (address.includes('[') || address.split(':').length > 2) {
    return fail('Not a valid SIP address. IPv6 addresses are not supported');
  }
  if (/^[a-z][a-z0-9+-]*:(?!\d+$)/i.test(address)) {
    return fail('Only the sip: scheme is supported');
  }

  const [host, port] = address.split(':');
  if (!isValidHost(host)) return fail('Invalid host name or IP address');
  if (port === undefined) return { ok: true, value: host };

  const portNumber = Number(port);
  if (!/^\d{1,5}$/.test(port) || portNumber < 1 || portNumber > 65535) {
    return fail('Invalid port, it must be 1-65535');
  }
  return { ok: true, value: `${host}:${portNumber}` };
}

// Digits and dots only must be a real IPv4 address, so "1.0.5" is not taken
// for a host name. Host names are RFC 1123 labels; a single label (an
// internal host) is allowed, but the last label must not be all digits.
function isValidHost(host: string): boolean {
  if (/^[\d.]+$/.test(host)) {
    const octets = host.split('.');
    return octets.length === 4 && octets.every((o) => /^\d{1,3}$/.test(o) && Number(o) <= 255);
  }
  const labels = host.split('.');
  return (
    host.length <= 253 &&
    labels.every((label) => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i.test(label)) &&
    !/^\d+$/.test(labels[labels.length - 1])
  );
}

export const sipTrunkCreateSchema = z.object({
  name: z.string().min(3).max(25),
  // remove the regex testing on below line and min also
  outboundUsername: z.string().optional(),
  outboundPassword: z.string().optional(),
  // Accepts host, host:port, sip:host and sip:host:port, and parses to the
  // stored form (see normalizeOutboundContact).
  outboundContact: z.string().transform((value, ctx) => {
    const result = normalizeOutboundContact(value);
    if (!result.ok) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: result.message });
      return z.NEVER;
    }
    return result.value;
  }),
  inboundIps: z.array(
    z.string().refine(
      (value) => {
        // Regular expression for IPv4 CIDR
        const ipv4CidrPattern =
          /^((25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?)\/(3[0-2]|[12]?[0-9])$/;
        return ipv4CidrPattern.test(value);
      },
      { message: 'Inbound IPs should be comma separated CIDR values. e.g. 1.2.3.4/16' },
    ),
  ),
});
