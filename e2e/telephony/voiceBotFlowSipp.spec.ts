import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureVoiceBot,
  ensureVoiceBotEndpoint,
  setNumberInboundFlowToVoiceBot,
  waitForInboundCallStoryObserved,
} from '../utils/telephonyDb';
import { runInboundDidToExternalFlow } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.voiceBot;

test.describe.configure({ mode: 'serial' });

test(
  'VoiceBot node routes the inbound call to the configured voice bot endpoint',
  { tag: ['@sipp', '@flow', '@voicebot'] },
  async () => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557658';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Voice Bot',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    const { voiceBotId } = await ensureVoiceBot({
      subdomain: 'acme',
      name: 'telephony voice bot',
      pipeline: 'test',
    });
    await ensureVoiceBotEndpoint('sipp-uas');
    await setNumberInboundFlowToVoiceBot(publicNumber, voiceBotId);

    const { uacResult, uasResult } = await runInboundDidToExternalFlow({
      customerNumber,
      didNumber: publicNumber,
      externalTarget: voiceBotId,
      externalPort: 5080,
      withAudio: true,
      callerPort: A.callerPort,
    });

    expect(uacResult.stderr).not.toContain('Failed');
    expect(uasResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStoryObserved({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 90_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.spans).toBeGreaterThan(0);
  },
);
