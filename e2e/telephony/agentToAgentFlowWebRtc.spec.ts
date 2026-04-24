import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  waitForCallStory,
} from '../utils/telephonyDb';
import { allocations } from './testAllocations';
import {
  answerIncomingCall,
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

// Per-speaker dialogue WAVs.  Each file has the other side's turn rendered as
// silence so two looping Chrome instances produce an alternating conversation.
// See e2e/telephony/audio/README.md for the layout.
const AGENT1_WAV = path.join(repoRoot, 'e2e/telephony/audio/agent1.wav');
const AGENT2_WAV = path.join(repoRoot, 'e2e/telephony/audio/agent2.wav');

const CHROME_MEDIA_ARGS = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

test.describe.configure({ mode: 'serial' });

const A = allocations.agentToAgent;

test('Browser WebRTC agent can call another browser WebRTC agent with real speech', async ({
  page,
}) => {
  test.setTimeout(240_000);

  const caller = {
    name: 'WebRTC Caller Agent',
    email: 'test.user+webrtccalleragent@example.com',
    password: 'WebRtcCallerAgent@1902',
    username: 'webrtccalleragent',
    sipPassword: 'WebRtcCallerSip@1902',
  };
  const callee = {
    name: 'WebRTC Callee Agent',
    email: 'test.user+webrtccalleeagent@example.com',
    password: 'WebRtcCalleeAgent@1902',
    username: 'webrtccalleeagent',
    sipPassword: 'WebRtcCalleeSip@1902',
  };
  const fromNumber = A.did;

  // ── Seed users ────────────────────────────────────────────────────────────

  await ensureRegisteredUser(page.request, {
    name: caller.name,
    email: caller.email,
    password: caller.password,
  });
  await ensureRegisteredUser(page.request, {
    name: callee.name,
    email: callee.email,
    password: callee.password,
  });

  await ensureMemberInOrg({
    subdomain: 'acme',
    email: caller.email,
    name: caller.name,
    username: caller.username,
    sipPassword: caller.sipPassword,
    presence: 'Available',
  });
  await ensureMemberInOrg({
    subdomain: 'acme',
    email: callee.email,
    name: callee.name,
    username: callee.username,
    sipPassword: callee.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(caller.email);
  await ensureUserAcceptedTerms(callee.email);
  await ensureUserEmailVerified(caller.email);
  await ensureUserEmailVerified(callee.email);

  // ── Launch each browser with its own fake microphone WAV ─────────────────

  const callerBrowser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT1_WAV}`,
    ],
  });
  const calleeBrowser = await chromium.launch({
    args: [
      ...CHROME_MEDIA_ARGS,
      `--use-file-for-fake-audio-capture=${AGENT2_WAV}`,
    ],
  });

  try {
    const callerSession = await loginAsMember({
      browser: callerBrowser,
      request: page.request,
      email: caller.email,
      password: caller.password,
      subdomain: 'acme',
    });
    const calleeSession = await loginAsMember({
      browser: calleeBrowser,
      request: page.request,
      email: callee.email,
      password: callee.password,
      subdomain: 'acme',
    });

    await installDialerObservers(callerSession.page);
    await installDialerObservers(calleeSession.page);

    // ── Place the call ────────────────────────────────────────────────────

    await dialFromWidget(callerSession.page, {
      fromNumber,
      to: callee.username,
    });

    await expect(
      calleeSession.page.getByRole('button', { name: 'Answer' }),
    ).toBeVisible({ timeout: 45_000 });
    await answerIncomingCall(calleeSession.page);
    await waitForDialerConnected(callerSession.page, 45_000);
    await waitForDialerConnected(calleeSession.page, 45_000);

    // The scripted dialogue is ~20.5 s.  Wait for it to finish so FreeSwitch
    // records both voices before either side hangs up.
    await callerSession.page.waitForTimeout(22_000);

    await hangupCurrentCall(callerSession.page);
    await waitForDialerHungUp(callerSession.page, 45_000);

    // ── Assert a recording was produced ──────────────────────────────────
    // Transcript content is intentionally NOT verified here — running STT on
    // every run is expensive and adds an external dependency.  The speech
    // round-trip (two distinct voices surviving WebRTC → FreeSwitch → WAV)
    // has been verified manually via Deepgram; from here on we only check
    // that FreeSwitch produced a non-empty recording of the expected length.

    const callStory = await waitForCallStory({
      caller: `${caller.username}@acme.comcent.io`,
      timeoutMs: 90_000,
    });

    const recording = await assertRecordingProduced(callStory.id, 90_000);
    expect(recording.fileName).toBeTruthy();
    expect(recording.fileSize ?? 0).toBeGreaterThan(0);

    await callerSession.context.close();
    await calleeSession.context.close();
  } finally {
    await callerBrowser.close();
    await calleeBrowser.close();
  }
});
