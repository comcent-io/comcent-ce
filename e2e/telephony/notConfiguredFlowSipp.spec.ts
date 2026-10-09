import { randomUUID } from 'node:crypto';
import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  setNumberInboundFlowToEmpty,
} from '../utils/telephonyDb';
import { readLatestSippMessagesLog, runInboundDidCall } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.notConfigured;

// The prompt is 2 s of silence, so the first word isn't lost while the
// caller's audio path opens, then "This number is not configured. Please
// configure it." (about 2.4 s).
const PROMPT_MS = 4_000;

// When the trace logged the first message that starts with `firstLine`.
function messageTime(trace: string, firstLine: string): number {
  const block = trace
    .split(/^-{10,} /m)
    .find((entry) => entry.includes(`\n\n${firstLine}`));
  if (!block) {
    throw new Error(`No "${firstLine}" in the SIPp trace:\n${trace}`);
  }
  return Date.parse(block.slice(0, block.indexOf('\n')).trim());
}

test(
  'A number with an empty call flow plays the not-configured prompt, then hangs up',
  { tag: ['@sipp', '@flow'] },
  async () => {
    test.setTimeout(120_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557670';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Not Configured',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    // What an imported number starts with.
    await setNumberInboundFlowToEmpty(publicNumber);

    // A trace file of its own: the sipp container is shared by every worker.
    const traceName = `not-configured-${randomUUID()}`;

    // uac-remote-bye.xml fails unless the call is answered and FreeSWITCH
    // then sends the BYE, so a rejected or busy call fails here.
    const result = await runInboundDidCall({
      customerNumber,
      didNumber: publicNumber,
      scenario: 'uac-remote-bye.xml',
      localPort: A.callerPort,
      callerExtraArgs: ['-message_file', `/tmp/${traceName}_messages.log`],
    });
    expect(result.stderr).not.toContain('Failed');

    // The BYE only comes once the prompt has played. The old busy hang-up
    // sent it straight after answering.
    const trace = await readLatestSippMessagesLog('sipp', traceName);
    const answeredAt = messageTime(trace, 'SIP/2.0 200 OK');
    const byeAt = messageTime(trace, 'BYE sip:');
    expect(byeAt - answeredAt).toBeGreaterThanOrEqual(PROMPT_MS);
  },
);
