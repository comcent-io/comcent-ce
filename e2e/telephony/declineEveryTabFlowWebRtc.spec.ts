import { chromium, expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  setNumberInboundFlowToDial,
} from '../utils/telephonyDb';
import { runInboundDidCall } from '../utils/sipp';
import { allocations } from './testAllocations';
import {
  ensureRegisteredUser,
  loginAsMember,
  waitForDialerReady,
} from '../utils/webDialer';

const CHROME_MEDIA_ARGS = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

test.describe.configure({ mode: 'serial' });

const A = allocations.declineEveryTab;

// Each tab registers its own phone, so a call rings on both. Decline on one
// used to send 480, which only ended that tab's ring; the other kept ringing
// until the Dial step timed out. Decline now sends 603, and the SBC cancels
// every other tab and device.
test('Declining on one tab stops the call ringing on the agent’s other tab', async ({
  page,
}) => {
  test.setTimeout(120_000);

  const publicNumber = A.did;
  const customerNumber = '+14155553740';
  const agent = {
    name: 'Two Tab Agent',
    email: 'test.user+twotabagent@example.com',
    password: 'TwoTabAgent@1902',
    username: 'twotabagent',
    sipPassword: 'TwoTabAgentSip@1902',
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
    sipTrunkName: 'Telephony Decline Every Tab',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });
  // The Dial step rings for 20 s; the call must end well before that.
  await setNumberInboundFlowToDial(publicNumber, agent.username);

  const browser = await chromium.launch({ args: CHROME_MEDIA_ARGS });
  try {
    const { context, page: tabA } = await loginAsMember({
      browser,
      request: page.request,
      email: agent.email,
      password: agent.password,
      subdomain: 'acme',
    });
    const tabB = await context.newPage();
    await tabB.goto(tabA.url());
    await waitForDialerReady(tabB);

    // The customer waits for Comcent to hang up on them.
    const callPromise = runInboundDidCall({
      customerNumber,
      didNumber: publicNumber,
      scenario: 'uac-remote-bye.xml',
      localPort: A.callerPort,
    });

    const declineA = tabA.getByRole('button', { name: 'Decline' }).first();
    const declineB = tabB.getByRole('button', { name: 'Decline' }).first();
    await expect(declineA).toBeVisible({ timeout: 30_000 });
    await expect(declineB).toBeVisible({ timeout: 30_000 });

    const declinedAt = Date.now();
    await declineA.click();

    await expect(declineA).toBeHidden({ timeout: 5_000 });
    await expect(declineB).toBeHidden({ timeout: 5_000 });

    // The caller isn't left ringing out the Dial step's 20 s either.
    const uacResult = await callPromise;
    expect(uacResult.stderr).not.toContain('Failed');
    expect(Date.now() - declinedAt).toBeLessThan(12_000);

    await context.close();
  } finally {
    await browser.close();
  }
});
