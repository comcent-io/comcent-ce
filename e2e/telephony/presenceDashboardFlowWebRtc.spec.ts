import { expect, test, type Page } from '@playwright/test';
import { ensureMemberInOrg, ensureUserAcceptedTerms, ensureUserEmailVerified } from '../utils/telephonyDb';
import { ensureRegisteredUser, loginAsMember, setDialerPresenceStatus } from '../utils/webDialer';

test.describe.configure({ mode: 'serial' });

function memberPresenceCard(page: Page, username: string) {
  return page.locator('div').filter({ hasText: `${username}@acme.comcent.io` }).first();
}

test('Presence dashboard updates in realtime when another web dialer user changes status', async ({
  browser,
  page,
}) => {
  test.setTimeout(180_000);

  const agent = {
    name: 'Presence Dashboard Agent',
    email: 'test.user+presenceagent@example.com',
    password: 'PresenceAgent@1902',
    username: 'presenceagent',
    sipPassword: 'PresenceAgentSip@1902',
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
    presence: 'Logged Out',
  });
  await ensureUserAcceptedTerms(agent.email);
  await ensureUserEmailVerified(agent.email);

  await page.goto('/app/acme/presence');

  const presenceCard = memberPresenceCard(page, agent.username);
  await expect(presenceCard).toBeVisible();
  await expect(presenceCard).toContainText('Logged Out');

  const { context, page: agentPage } = await loginAsMember({
    browser,
    request: page.request,
    email: agent.email,
    password: agent.password,
    subdomain: 'acme',
  });

  try {
    await setDialerPresenceStatus(agentPage, 'On Break');
    await expect(presenceCard).toContainText('On Break', { timeout: 10_000 });

    await setDialerPresenceStatus(agentPage, 'Available');
    await expect(presenceCard).toContainText('Available', { timeout: 10_000 });

    await setDialerPresenceStatus(agentPage, 'Logged Out');
    await expect(presenceCard).toContainText('Logged Out', { timeout: 10_000 });
  } finally {
    await context.close();
  }
});
