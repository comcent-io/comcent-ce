import * as z from 'zod';

export const sipTrunkCreateSchema = z.object({
  name: z.string().min(3).max(25),
  // remove the regex testing on below line and min also
  outboundUsername: z.string().optional(),
  outboundPassword: z.string().optional(),
  outboundContact: z
    .string()
    .min(1)
    .refine(
      (value) => {
        // the below regex accepts all types of ipv4 addresses
        const ipv4Pattern =
          /^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:(6553[0-5]|655[0-2][0-9]|65[0-4][0-9]{2}|6[0-4][0-9]{3}|[1-5][0-9]{4}|[0-9]{1,4}))?$/;
        // the below regex accepts all formats of ipv6 addresses and also embedded ipv4 addresses.
        const ipv6Pattern =
          /^((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}))|(([0-9A-Fa-f]{1,4}:){1,6}:([0-9A-Fa-f]{1,4}))|(([0-9A-Fa-f]{1,4}:){1,5}(:[0-9A-Fa-f]{1,4}){1,2})|(([0-9A-Fa-f]{1,4}:){1,4}(:[0-9A-Fa-f]{1,4}){1,3})|(([0-9A-Fa-f]{1,4}:){1,3}(:[0-9A-Fa-f]{1,4}){1,4})|(([0-9A-Fa-f]{1,4}:){1,2}(:[0-9A-Fa-f]{1,4}){1,5})|([0-9A-Fa-f]{1,4}:((:[0-9A-Fa-f]{1,4}){1,6}))|(:((:[0-9A-Fa-f]{1,4}){1,7}|:))|(::([0-9A-Fa-f]{1,4}:){0,5}([0-9A-Fa-f]{1,4}))|((([0-9A-Fa-f]{1,4}:){6})?((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)))$/;
        // the below regex accepts all types of valid domain names except the domain which starts from sip:
        const domainPattern = /^(?!sip:)(?!-)([a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,}$/;
        return ipv4Pattern.test(value) || ipv6Pattern.test(value) || domainPattern.test(value);
      },
      { message: 'Sip Proxy Address should be a valid IP address or a valid domain name' },
    ), // Adjust the min length as needed
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
