import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  setNumberInboundFlowToDial,
  waitForCallSpans,
  waitForInboundCallStory,
} from '../utils/telephonyDb';
import { runInboundDidToExternalFlow } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.inboundDial;

test.describe.configure({ mode: 'serial' });

test(
  'Inbound DID routes through number flow Dial node to an external SIP endpoint via SIPp',
  { tag: ['@sipp', '@routing', '@recording'] },
  async () => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155551234';
    const dialTarget = '+14155550123';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Inbound Dial',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToDial(publicNumber, dialTarget);

    const { uacResult, uasResult } = await runInboundDidToExternalFlow({
      customerNumber,
      didNumber: publicNumber,
      externalTarget: dialTarget,
      withAudio: true,
      callerPort: A.callerPort,
      externalPort: A.uasPort,
    });

    expect(uacResult.stderr).not.toContain('Failed');
    expect(uasResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStory({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 60_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.caller).toBe(customerNumber);
    expect(callStory.callee).toBe(publicNumber);
    expect(callStory.spans).toBeGreaterThan(0);

    // Verify that a recording was produced for the completed call.
    const spans = await waitForCallSpans(
      callStory.id,
      (rows) =>
        rows.some(
          (row) => row.type === 'RECORDING' && row.metadata?.file_name != null,
        ),
      60_000,
    );
    const recordingSpan = spans.find((r) => r.type === 'RECORDING');
    expect(recordingSpan?.metadata?.file_name).toBeTruthy();
  },
);
