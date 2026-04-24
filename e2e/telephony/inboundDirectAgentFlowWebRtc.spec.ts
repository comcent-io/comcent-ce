import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  setNumberInboundFlowToDial,
  waitForInboundCallStoryObserved,
} from '../utils/telephonyDb';
import {
  copyFileToContainer,
  CUSTOMER_PCAP_HOST_PATH,
  runInboundDidCall,
} from '../utils/sipp';
import { allocations } from './testAllocations';
import {
  answerIncomingCall,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
  waitForDialerHungUp,
} from '../utils/webDialer';

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

const AGENT_WAV = path.join(repoRoot, 'e2e/telephony/audio/agent.wav');

const CHROME_MEDIA_ARGS = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

test.describe.configure({ mode: 'serial' });

const A = allocations.inboundDirectAgentWebRtc;

test('Inbound DID routes through Dial node to a browser WebRTC agent with real audio', async ({
  page,
}) => {
  test.setTimeout(180_000);

  const publicNumber = A.did;
  const customerNumber = '+14155553457';
  const agent = {
    name: 'WebRTC Direct Agent',
    email: 'test.user+webrtcdirectagent@example.com',
    password: 'WebRtcDirectAgent@1902',
    username: 'webrtcdirectagent',
    sipPassword: 'WebRtcDirectSip@1902',
  };

  await ensureRegisteredUser(page.request, {
    name: agent.name,
    email: agent.email,
    password: agent.password,
  });

  await ensureMemberInOrg({
    subdomain: 'acme',
    email: agent.email,
    name: agent.name,
    username: agent.username,
    sipPassword: agent.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(agent.email);
  await ensureUserEmailVerified(agent.email);

  await ensureDefaultOutboundRoute({
    subdomain: 'acme',
    number: publicNumber,
    sipTrunkName: 'Telephony WebRTC Direct Agent',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });

  await setNumberInboundFlowToDial(publicNumber, agent.username);

  // Stage customer speech PCAP on the SIPp caller so FreeSwitch receives
  // real audio from the customer leg.
  await copyFileToContainer(
    CUSTOMER_PCAP_HOST_PATH,
    'sipp',
    '/tmp/customer-audio.pcap',
  );

  // Launch the agent's browser with agent.wav as the fake microphone so
  // the WebRTC leg streams real speech instead of Chrome's default beep.
  const agentBrowser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT_WAV}`,
    ],
  });

  try {
    const { context, page: agentPage } = await loginAsMember({
      browser: agentBrowser,
      request: page.request,
      email: agent.email,
      password: agent.password,
      subdomain: 'acme',
    });

    await installDialerObservers(agentPage);

    // Caller plays customer PCAP while waiting for the remote BYE from
    // the browser agent.
    const callPromise = runInboundDidCall({
      customerNumber,
      didNumber: publicNumber,
      scenario: 'uac-remote-bye-pcap.xml',
      withAudio: true,
      localPort: A.callerPort,
    });

    await expect(agentPage.getByRole('button', { name: 'Answer' })).toBeVisible(
      { timeout: 45_000 },
    );
    // Let the call ring for a couple of seconds before answering so the
    // RINGING span has a non-zero duration in the call story UI.
    await agentPage.waitForTimeout(2_000);
    await answerIncomingCall(agentPage);
    await waitForDialerConnected(agentPage, 45_000);

    // Keep the call up long enough for the full conversation to play
    // (customer PCAP speech sits between 6 s and 14 s of the clip).
    await agentPage.waitForTimeout(15_000);
    await hangupCurrentCall(agentPage);
    await waitForDialerHungUp(agentPage, 45_000);

    const uacResult = await callPromise;
    expect(uacResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStoryObserved({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 90_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.spans).toBeGreaterThan(0);

    const recording = await assertRecordingProduced(callStory.id, 90_000);
    expect(recording.fileName).toBeTruthy();
    expect(recording.fileSize ?? 0).toBeGreaterThan(0);

    await context.close();
  } finally {
    await agentBrowser.close();
  }
});
