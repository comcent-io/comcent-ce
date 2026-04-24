import jsonwebtoken from 'jsonwebtoken';
import { Client } from 'pg';
import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  waitForCallSpans,
  waitForCallStory,
} from '../utils/telephonyDb';
import { fetchRecordingBytes } from '../utils/telephonyApi';

// The seeded admin has no password — auth is JWT-based.  Mint a session
// token with the same SIGNING_KEY the server uses, identical to what
// e2e/utils/bootstrap.ts does for the default storage state.
async function signAdminJwt() {
  const signingKey = process.env.SIGNING_KEY;
  if (!signingKey) {
    throw new Error('SIGNING_KEY is required to mint an admin session token');
  }

  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const result = await client.query<{ id: string }>(
      "SELECT id FROM users WHERE email = 'test.admin@example.com'",
    );
    const userId = result.rows[0]?.id;
    if (!userId) throw new Error('Seeded admin user not found');

    return jsonwebtoken.sign(
      {
        sub: userId,
        email: 'test.admin@example.com',
        name: 'Test Admin',
        picture: null,
        email_verified: true,
        auth_provider: 'password',
        token_type: 'session',
      },
      signingKey,
      { algorithm: 'HS256', expiresIn: '1h' },
    );
  } finally {
    await client.end();
  }
}
import { allocations } from './testAllocations';
import { runSipp } from '../utils/sipp';
import {
  dialFromWidget,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
  waitForDialerHungUp,
} from '../utils/webDialer';

test.describe.configure({ mode: 'serial' });

const A = allocations.recordingContent;

test('Completed call recording metadata and WAV content are available', async ({
  browser,
  page,
}) => {
  test.setTimeout(180_000);

  const caller = {
    name: 'WebRTC Recording Agent',
    email: 'test.user+webrtcrecordingagent@example.com',
    password: 'WebRtcRecordingAgent@1902',
    username: 'webrtcrecordingagent',
    sipPassword: 'WebRtcRecordingSip@1902',
  };
  const fromNumber = A.did;
  const customerNumber = '+14155556782';

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
    sipTrunkName: 'Telephony WebRTC Recording',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });

  const { context, page: callerPage } = await loginAsMember({
    browser,
    request: page.request,
    email: caller.email,
    password: caller.password,
    subdomain: 'acme',
  });

  await installDialerObservers(callerPage);

  const uas = runSipp({
    scenario: 'uas-answer.xml',
    service: 'sipp-uas',
    extraArgs: ['-p', String(A.uasPort), '-t', 'u1'],
    timeoutMs: 120_000,
  });

  await callerPage.waitForTimeout(1_500);
  await dialFromWidget(callerPage, {
    fromNumber,
    to: customerNumber,
  });
  await waitForDialerConnected(callerPage, 45_000);
  await callerPage.waitForTimeout(3_000);
  await hangupCurrentCall(callerPage);
  await waitForDialerHungUp(callerPage, 45_000);

  const uasResult = await uas;
  expect(uasResult.stderr).not.toContain('Failed');

  const callStory = await waitForCallStory({
    caller: `${caller.username}@acme.comcent.io`,
    direction: 'outbound',
    timeoutMs: 90_000,
  });

  const spans = await waitForCallSpans(
    callStory.id,
    (rows) =>
      rows.some(
        (row) =>
          row.type === 'RECORDING' &&
          row.metadata?.file_name &&
          row.metadata?.sha512 &&
          row.metadata?.fileSize,
      ),
    90_000,
  );

  const recordingSpan = spans.find(
    (row) =>
      row.type === 'RECORDING' &&
      row.metadata?.file_name &&
      row.metadata?.sha512,
  );
  expect(recordingSpan).toBeTruthy();
  expect(Number(recordingSpan?.metadata?.fileSize ?? '0')).toBeGreaterThan(0);

  const adminToken = await signAdminJwt();

  const recordingBytes = await fetchRecordingBytes({
    request: page.request,
    token: adminToken,
    subdomain: 'acme',
    callStoryId: callStory.id,
    fileName: recordingSpan!.metadata!.file_name!,
    timeoutMs: 90_000,
  });

  expect(recordingBytes.subarray(0, 4).toString()).toBe('RIFF');
  expect(recordingBytes.subarray(8, 12).toString()).toBe('WAVE');

  await context.close();
});
