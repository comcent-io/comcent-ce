import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  getCallSpans,
  waitForCallStory,
} from '../utils/telephonyDb';
import { copyFileToContainer, runSipp } from '../utils/sipp';
import { allocations } from './testAllocations';
import {
  dialFromWidget,
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

// Pre-recorded speech fixtures committed to the repo.
// agent.wav   — Samantha voice, 48 kHz mono 16-bit PCM, for Chrome fake mic.
// customer.pcap — Alex voice, G.711 μ-law RTP PCAP, for SIPp play_pcap_audio.
// To regenerate: see e2e/telephony/audio/README.md
const AGENT_WAV = path.join(repoRoot, 'e2e/telephony/audio/agent.wav');
const CUSTOMER_PCAP = path.join(repoRoot, 'e2e/telephony/audio/customer.pcap');

test.describe.configure({ mode: 'serial' });

const A = allocations.agentOutbound;

test('Browser WebRTC agent can originate an outbound call to an external SIP endpoint', async ({
  page,
}) => {
  test.setTimeout(180_000);

  const caller = {
    name: 'WebRTC Outbound Agent',
    email: 'test.user+webrtcoutboundagent@example.com',
    password: 'WebRtcOutboundAgent@1902',
    username: 'webrtcoutboundagent',
    sipPassword: 'WebRtcOutboundSip@1902',
  };
  const fromNumber = A.did;
  const customerNumber = '+14155556789';

  // ── Seed test fixtures ────────────────────────────────────────────────────

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
    sipTrunkName: 'Telephony WebRTC Outbound',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });

  // ── Stage customer audio inside sipp-uas container ───────────────────────

  await copyFileToContainer(
    CUSTOMER_PCAP,
    'sipp-uas',
    '/tmp/customer-audio.pcap',
  );

  // ── Launch Chrome with agent speech as fake microphone ───────────────────

  const browser = await chromium.launch({
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
      `--use-file-for-fake-audio-capture=${AGENT_WAV}`,
      '--autoplay-policy=no-user-gesture-required',
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

    // ── Start sipp-uas — answers and plays customer speech via PCAP ──────────

    const uas = runSipp({
      scenario: 'uas-answer-pcap.xml',
      service: 'sipp-uas',
      extraArgs: ['-p', String(A.uasPort), '-t', 'u1'],
      timeoutMs: 120_000,
    });

    // ── Make the call ─────────────────────────────────────────────────────────

    await callerPage.waitForTimeout(1_500);
    await dialFromWidget(callerPage, { fromNumber, to: customerNumber });
    await waitForDialerConnected(callerPage, 45_000);

    // Let both sides speak for 15 s so FreeSwitch records meaningful audio
    await callerPage.waitForTimeout(15_000);

    await hangupCurrentCall(callerPage);
    await waitForDialerHungUp(callerPage, 45_000);

    const uasResult = await uas;
    expect(uasResult.stderr).not.toContain('Failed');

    // ── Assert call story and spans ───────────────────────────────────────────

    const outboundStory = await waitForCallStory({
      caller: `${caller.username}@acme.comcent.io`,
      direction: 'outbound',
      timeoutMs: 90_000,
    });

    expect(outboundStory.direction).toBe('outbound');
    expect(outboundStory.spans).toBeGreaterThan(0);

    const spans = await getCallSpans(outboundStory.id);
    const agentOnCall = spans.find(
      (span) =>
        span.type === 'ON_CALL' &&
        span.current_party === `${caller.username}@acme.comcent.io`,
    );
    const calleeOnCall = spans.find(
      (span) =>
        span.type === 'ON_CALL' && span.current_party === customerNumber,
    );

    expect(agentOnCall?.end_at).not.toBeNull();
    expect(calleeOnCall?.end_at).not.toBeNull();

    // ── Assert recording captured real audio ──────────────────────────────────

    const recording = await assertRecordingProduced(outboundStory.id, 90_000);
    expect(recording.fileName).toBeTruthy();
    expect(recording.fileSize).toBeGreaterThan(0);

    await context.close();
  } finally {
    await browser.close();
  }
});
