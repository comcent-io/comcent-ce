import { test } from '@playwright/test';
import {
  assertNoCallStory,
  ensureDefaultOutboundRoute,
} from '../utils/telephonyDb';
import { runInboundDidCall } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.inboundIpWhitelist;

test.describe.configure({ mode: 'serial' });

test(
  'Inbound call from a non-whitelisted IP is rejected before entering the app flow',
  { tag: ['@sipp', '@kamailio', '@security'] },
  async () => {
    test.setTimeout(120_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557663';

    try {
      await ensureDefaultOutboundRoute({
        subdomain: 'acme',
        number: publicNumber,
        sipTrunkName: 'Telephony IP Whitelist Reject',
        outboundContact: 'sipp-uas:5060',
        inboundIps: ['10.10.10.0/24'],
      });

      const result = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        scenario: 'uac-expect-403.xml',
        localPort: A.callerPort,
      });

      if (result.stderr.includes('Failed')) {
        throw new Error(result.stderr);
      }

      await assertNoCallStory({
        caller: customerNumber,
        callee: publicNumber,
        direction: 'inbound',
        waitMs: 3_000,
      });
    } finally {
      await ensureDefaultOutboundRoute({
        subdomain: 'acme',
        number: publicNumber,
        sipTrunkName: 'Telephony IP Whitelist Reset',
        outboundContact: 'sipp-uas:5060',
        inboundIps: ['172.29.0.0/16'],
      });
    }
  },
);
