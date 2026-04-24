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
  waitForCallSpans,
  waitForCallStory,
} from '../utils/telephonyDb';
import { runInboundDidCall } from '../utils/sipp';
import { allocations } from './testAllocations';
import {
  answerIncomingCall,
  blindTransferCurrentCall,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
} from '../utils/webDialer';

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

// Each agent has a dedicated short speech file that starts talking immediately
// (no leading silence) because blind-transfer call segments are short and
// Chrome restarts --use-file-for-fake-audio-capture from position 0 every
// time a new RTCPeerConnection mic stream opens.
const AGENT1_WAV = path.join(
  repoRoot,
  'e2e/telephony/audio/blindTransferAgent1.wav',
);
const AGENT2_WAV = path.join(
  repoRoot,
  'e2e/telephony/audio/blindTransferAgent2.wav',
);

const CHROME_MEDIA_ARGS = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

test.describe.configure({ mode: 'serial' });

const A = allocations.blindTransfer;

test('Inbound customer call can be blind transferred from one browser WebRTC agent to another', async ({
  page,
}) => {
  test.setTimeout(240_000);

  const firstAgent = {
    name: 'WebRTC Transfer Agent One',
    email: 'test.user+webrtctransferone@example.com',
    password: 'WebRtcTransferOne@1902',
    username: 'webrtctransferone',
    sipPassword: 'WebRtcTransferOneSip@1902',
  };
  const secondAgent = {
    name: 'WebRTC Transfer Agent Two',
    email: 'test.user+webrtctransfertwo@example.com',
    password: 'WebRtcTransferTwo@1902',
    username: 'webrtctransfertwo',
    sipPassword: 'WebRtcTransferTwoSip@1902',
  };
  const publicNumber = A.did;
  const customerNumber = '+14155557661';

  // ── Seed users ────────────────────────────────────────────────────────────

  await ensureRegisteredUser(page.request, {
    name: firstAgent.name,
    email: firstAgent.email,
    password: firstAgent.password,
  });
  await ensureRegisteredUser(page.request, {
    name: secondAgent.name,
    email: secondAgent.email,
    password: secondAgent.password,
  });

  await ensureMemberInOrg({
    subdomain: 'acme',
    email: firstAgent.email,
    name: firstAgent.name,
    username: firstAgent.username,
    sipPassword: firstAgent.sipPassword,
    presence: 'Available',
  });
  await ensureMemberInOrg({
    subdomain: 'acme',
    email: secondAgent.email,
    name: secondAgent.name,
    username: secondAgent.username,
    sipPassword: secondAgent.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(firstAgent.email);
  await ensureUserAcceptedTerms(secondAgent.email);
  await ensureUserEmailVerified(firstAgent.email);
  await ensureUserEmailVerified(secondAgent.email);

  await ensureDefaultOutboundRoute({
    subdomain: 'acme',
    number: publicNumber,
    sipTrunkName: 'Telephony WebRTC Blind Transfer',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });
  await setNumberInboundFlowToDial(publicNumber, firstAgent.username);

  // ── Launch each browser with its own fake microphone WAV ─────────────────

  const firstBrowser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT1_WAV}`,
    ],
  });
  const secondBrowser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT2_WAV}`,
    ],
  });

  try {
    const firstSession = await loginAsMember({
      browser: firstBrowser,
      request: page.request,
      email: firstAgent.email,
      password: firstAgent.password,
      subdomain: 'acme',
    });
    const secondSession = await loginAsMember({
      browser: secondBrowser,
      request: page.request,
      email: secondAgent.email,
      password: secondAgent.password,
      subdomain: 'acme',
    });

    await installDialerObservers(firstSession.page);
    await installDialerObservers(secondSession.page);

    // ── Customer calls in; agent 1 answers and speaks ────────────────────

    const customerCall = runInboundDidCall({
      customerNumber,
      didNumber: publicNumber,
      // PCAP variant of uac-remote-bye so the customer leg plays real speech
      // toward FreeSwitch via play-audio.sh instead of sending silence.
      scenario: 'uac-remote-bye-pcap.xml',
      withAudio: true,
      localPort: A.callerPort,
    });

    await expect(
      firstSession.page.getByRole('button', { name: 'Answer' }).first(),
    ).toBeVisible({ timeout: 45_000 });
    await answerIncomingCall(firstSession.page);
    await waitForDialerConnected(firstSession.page, 45_000);

    // Let agent 1's ~7 s phrase play fully before initiating the transfer so
    // the recording captures agent 1's voice on the pre-transfer leg.
    await firstSession.page.waitForTimeout(8_000);
    await blindTransferCurrentCall(firstSession.page, secondAgent.username);

    // ── Agent 2 answers the transferred call and speaks ──────────────────

    await expect(
      secondSession.page.getByRole('button', { name: 'Answer' }).first(),
    ).toBeVisible({ timeout: 45_000 });
    await answerIncomingCall(secondSession.page);
    await waitForDialerConnected(secondSession.page, 45_000);

    // Let agent 2's ~4.5 s phrase play fully before hanging up.
    await secondSession.page.waitForTimeout(6_000);
    await hangupCurrentCall(secondSession.page);

    const customerResult = await customerCall;
    expect(customerResult.stderr).not.toContain('Failed');

    // ── Assert both agents appear on the call and a recording was made ──

    const callStory = await waitForCallStory({
      caller: customerNumber,
      callee: publicNumber,
      direction: 'inbound',
      timeoutMs: 90_000,
    });

    const spans = await waitForCallSpans(
      callStory.id,
      (rows) => {
        const parties = new Set(rows.map((row) => row.current_party));
        return (
          parties.has(`${firstAgent.username}@acme.comcent.io`) &&
          parties.has(`${secondAgent.username}@acme.comcent.io`)
        );
      },
      30_000,
    );

    expect(
      spans.some(
        (row) => row.current_party === `${firstAgent.username}@acme.comcent.io`,
      ),
    ).toBe(true);
    expect(
      spans.some(
        (row) =>
          row.current_party === `${secondAgent.username}@acme.comcent.io`,
      ),
    ).toBe(true);

    const recording = await assertRecordingProduced(callStory.id, 90_000);
    expect(recording.fileName).toBeTruthy();
    expect(recording.fileSize ?? 0).toBeGreaterThan(0);

    await firstSession.context.close();
    await secondSession.context.close();
  } finally {
    await firstBrowser.close();
    await secondBrowser.close();
  }
});
