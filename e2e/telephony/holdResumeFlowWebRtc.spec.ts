import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  waitForCallSpans,
  waitForCallStory,
} from '../utils/telephonyDb';
import {
  copyFileToContainer,
  CUSTOMER_PCAP_HOST_PATH,
  runSipp,
} from '../utils/sipp';
import { allocations } from './testAllocations';
import {
  dialFromWidget,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  toggleHold,
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

const A = allocations.holdResume;

test('Browser WebRTC agent can hold and resume an outbound call', async ({
  page,
}) => {
  test.setTimeout(240_000);

  const caller = {
    name: 'WebRTC Hold Resume Agent',
    email: 'test.user+webrtcholdresume@example.com',
    password: 'WebRtcHoldResume@1902',
    username: 'webrtcholdresume',
    sipPassword: 'WebRtcHoldResumeSip@1902',
  };
  const fromNumber = A.did;
  const customerNumber = '+14155556781';

  // ── Seed fixtures ─────────────────────────────────────────────────────────

  await ensureRegisteredUser(page.request, {
    name: caller.name,
    email: caller.email,
    password: caller.password,
  });

  await ensureMemberInOrg({
    subdomain: 'acme',
    email: caller.email,
    name: caller.name,
    username: caller.username,
    sipPassword: caller.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(caller.email);
  await ensureUserEmailVerified(caller.email);

  await ensureDefaultOutboundRoute({
    subdomain: 'acme',
    number: fromNumber,
    sipTrunkName: 'Telephony WebRTC Hold Resume',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });

  // ── Stage customer audio inside sipp-uas container ────────────────────────

  await copyFileToContainer(
    CUSTOMER_PCAP_HOST_PATH,
    'sipp-uas',
    '/tmp/customer-audio.pcap',
  );

  // ── Launch Chrome with agent speech as fake microphone ────────────────────

  const browser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT_WAV}`,
    ],
  });

  try {
    const { context, page: callerPage } = await loginAsMember({
      browser,
      request: page.request,
      email: caller.email,
      password: caller.password,
      subdomain: 'acme',
    });

    await installDialerObservers(callerPage);

    // ── Start SIPp UAS with customer PCAP audio ───────────────────────────

    const uas = runSipp({
      scenario: 'uas-answer-pcap.xml',
      service: 'sipp-uas',
      extraArgs: ['-p', String(A.uasPort), '-t', 'u1'],
      timeoutMs: 120_000,
    });

    // ── Make the call ─────────────────────────────────────────────────────

    await callerPage.waitForTimeout(1_500);
    await dialFromWidget(callerPage, { fromNumber, to: customerNumber });
    await waitForDialerConnected(callerPage, 45_000);

    // Pre-hold: let the agent speak for a few seconds
    await callerPage.waitForTimeout(4_000);

    // Put the customer on hold — they should hear music-on-hold from
    // FreeSwitch, which will show up in the recording.
    await toggleHold(callerPage);
    await callerPage.waitForTimeout(8_000);

    // Resume the call
    await toggleHold(callerPage);
    await callerPage.waitForTimeout(5_000);

    await hangupCurrentCall(callerPage);
    await waitForDialerHungUp(callerPage, 45_000);

    const uasResult = await uas;
    expect(uasResult.stderr).not.toContain('Failed');

    // ── Assert call story and hold span ──────────────────────────────────

    const callStory = await waitForCallStory({
      caller: `${caller.username}@acme.comcent.io`,
      direction: 'outbound',
      timeoutMs: 90_000,
    });

    const spans = await waitForCallSpans(
      callStory.id,
      (rows) => rows.some((row) => row.type === 'HOLD' && row.end_at),
      30_000,
    );

    expect(spans.filter((row) => row.type === 'HOLD')).toHaveLength(1);

    const recording = await assertRecordingProduced(callStory.id, 90_000);
    expect(recording.fileName).toBeTruthy();
    expect(recording.fileSize ?? 0).toBeGreaterThan(0);

    await context.close();
  } finally {
    await browser.close();
  }
});
