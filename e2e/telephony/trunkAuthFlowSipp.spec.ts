import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  waitForCallStory,
} from '../utils/telephonyDb';
import { allocations } from './testAllocations';
import { readLatestSippMessagesLog, runSipp } from '../utils/sipp';
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

const A = allocations.trunkAuth;

test(
  'Outbound trunk call retries with digest auth after a proxy challenge',
  { tag: ['@sipp', '@kamailio', '@trunk-auth', '@recording'] },
  async ({ browser, page }) => {
    test.setTimeout(180_000);

    const caller = {
      name: 'WebRTC Trunk Auth Agent',
      email: 'test.user+webrtctrunkauth@example.com',
      password: 'WebRtcTrunkAuth@1902',
      username: 'webrtctrunkauth',
      sipPassword: 'WebRtcTrunkAuthSip@1902',
    };
    const fromNumber = A.did;
    const customerNumber = '+14155556783';

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
      sipTrunkName: 'Telephony Trunk Auth',
      outboundContact: 'sipp-uas:' + A.uasPort,
      outboundUsername: 'trunkauthuser',
      outboundPassword: 'trunkauthpassword',
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
      scenario: 'uas-proxy-auth-answer.xml',
      service: 'sipp-uas',
      extraArgs: ['-p', String(A.uasPort), '-t', 'u1'],
      timeoutMs: 120_000,
      allowNonZeroExit: true,
    });

    await callerPage.waitForTimeout(1_500);
    await dialFromWidget(callerPage, {
      fromNumber,
      to: customerNumber,
    });
    await waitForDialerConnected(callerPage, 60_000);
    await callerPage.waitForTimeout(2_000);
    await hangupCurrentCall(callerPage);
    await waitForDialerHungUp(callerPage, 45_000);

    const uasResult = await uas;
    expect(uasResult.stderr).not.toContain('Address already in use');

    const authTrace = await readLatestSippMessagesLog(
      'sipp-uas',
      'uas-proxy-auth-answer',
    );
    expect(authTrace).toContain('Proxy-Authorization: Digest');
    expect(authTrace).toContain('username="trunkauthuser"');

    const callStory = await waitForCallStory({
      caller: `${caller.username}@acme.comcent.io`,
      direction: 'outbound',
      timeoutMs: 90_000,
    });
    expect(callStory.spans).toBeGreaterThan(0);

    await context.close();
  },
);
