import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  setNumberInboundFlowToMenuDial,
  waitForInboundCallStory,
} from '../utils/telephonyDb';
import { runInboundDidToExternalFlow } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.menuBranch;

test.describe.configure({ mode: 'serial' });

test(
  'Menu node routes the inbound caller to the selected DTMF branch',
  { tag: ['@sipp', '@flow', '@dtmf'] },
  async () => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557657';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Menu',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToMenuDial({
      number: publicNumber,
      selectedDigit: '1',
      target: '+14155550123',
      fallbackTarget: 'menu-fallback-should-not-run',
    });

    const { uacResult, uasResult } = await runInboundDidToExternalFlow({
      customerNumber,
      didNumber: publicNumber,
      externalTarget: '+14155550123',
      withDtmf: true,
      withAudio: true,
      callerPort: A.callerPort,
      externalPort: A.uasPort,
    });

    expect(uacResult.stderr).not.toContain('Failed');
    expect(uasResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStory({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 90_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.spans).toBeGreaterThan(0);
  },
);
