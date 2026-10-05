import { randomUUID } from 'node:crypto';
import { expect, test, type Page } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  waitForCallStory,
} from '../utils/telephonyDb';
import { readLatestSippMessagesLog, runSipp } from '../utils/sipp';
import { allocations, type TestAllocation } from './testAllocations';
import {
  dialFromWidget,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
  waitForDialerHungUp,
} from '../utils/webDialer';

// Quality gate for a SIP trunk's outbound contact, the address outbound calls
// are sent to. The address is typed into the real SIP trunk form, in the
// forms customers use, and must come out as the bare host:port the dialplan
// and the SBC read. The UAS listens only on its own port, never 5060, so the
// call connects only if that port was honoured all the way to the SBC.

test.describe.configure({ mode: 'serial' });

type Case = {
  title: string;
  allocation: TestAllocation;
  sipTrunkName: string;
  // What the admin types into the form; the UAS port is appended.
  typed: (port: number) => string;
  callerKey: string;
  customerNumber: string;
};

const cases: Case[] = [
  {
    title: 'sip:host:port',
    allocation: allocations.outboundContactSipUri,
    sipTrunkName: 'Outbound Sip Uri Gate',
    typed: (port) => ` sip:sipp-uas:${port} `,
    callerKey: 'outboundsipuri',
    customerNumber: '+14155556791',
  },
  {
    title: 'host:port',
    allocation: allocations.outboundContactHostPort,
    sipTrunkName: 'Outbound HostPort Gate',
    typed: (port) => `sipp-uas:${port}`,
    callerKey: 'outboundhostport',
    customerNumber: '+14155556792',
  },
];

function proxyAddressInput(page: Page) {
  return page.getByPlaceholder('provider.example.com');
}

async function openSipTrunkForEdit(page: Page, name: string) {
  await page.goto('/app/acme/sip-trunks');
  await page
    .locator(`tr:has(td:has-text("${name}"))`)
    .getByRole('link', { name: 'Edit' })
    .click();
  await expect(proxyAddressInput(page)).toBeVisible();
}

// Saves the outbound contact through the SIP trunk form as an admin would,
// so the call below uses whatever the form and the server stored.
async function setOutboundContactThroughForm(
  page: Page,
  sipTrunkName: string,
  typed: string,
) {
  await openSipTrunkForEdit(page, sipTrunkName);
  await proxyAddressInput(page).fill(typed);
  await page.getByRole('button', { name: 'Update' }).click();
  await expect(page).toHaveURL('/app/acme/sip-trunks');
}

for (const c of cases) {
  test(
    `Outbound call reaches a trunk whose address was entered as ${c.title}`,
    { tag: ['@sipp', '@sbc', '@outbound-contact'] },
    async ({ browser, page }) => {
      test.setTimeout(180_000);

      const A = c.allocation;
      const port = A.uasPort;
      const caller = {
        name: `Outbound Contact ${c.title}`,
        email: `test.user+${c.callerKey}@example.com`,
        password: 'OutboundContact@1902',
        username: c.callerKey,
        sipPassword: 'OutboundContactSip@1902',
      };

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

      // Creates the trunk and routes the DID through it. The address it
      // starts with cannot be dialled; the form below replaces it.
      await ensureDefaultOutboundRoute({
        subdomain: 'acme',
        number: A.did,
        sipTrunkName: c.sipTrunkName,
        outboundContact: 'unset.invalid',
        inboundIps: ['172.29.0.0/16'],
      });

      await setOutboundContactThroughForm(page, c.sipTrunkName, c.typed(port));

      // Stored in the one canonical form, without the sip: prefix.
      await openSipTrunkForEdit(page, c.sipTrunkName);
      await expect(proxyAddressInput(page)).toHaveValue(`sipp-uas:${port}`);

      const { context, page: callerPage } = await loginAsMember({
        browser,
        request: page.request,
        email: caller.email,
        password: caller.password,
        subdomain: 'acme',
      });

      try {
        await installDialerObservers(callerPage);

        // A trace file of its own: the sipp-uas container is shared by every
        // worker, so "the latest uas-answer log" could be another spec's.
        const traceName = `outbound-contact-${port}-${randomUUID()}`;
        const uas = runSipp({
          scenario: 'uas-answer.xml',
          service: 'sipp-uas',
          extraArgs: [
            '-p',
            String(port),
            '-t',
            'u1',
            '-message_file',
            `/tmp/${traceName}_messages.log`,
          ],
          timeoutMs: 120_000,
        });

        await callerPage.waitForTimeout(1_500);
        await dialFromWidget(callerPage, {
          fromNumber: A.did,
          to: c.customerNumber,
        });
        await waitForDialerConnected(callerPage, 60_000);
        await callerPage.waitForTimeout(2_000);
        await hangupCurrentCall(callerPage);
        await waitForDialerHungUp(callerPage, 45_000);

        // runSipp rejects unless the UAS got the INVITE, answered, and saw
        // the BYE: the call really went to this port.
        const uasResult = await uas;
        expect(uasResult.stderr).not.toContain('Address already in use');

        // The SBC sent the INVITE to the trunk's port, not the default 5060.
        const trace = await readLatestSippMessagesLog('sipp-uas', traceName);
        const digits = c.customerNumber.replace(/^\+/, '');
        expect(trace).toMatch(
          new RegExp(`INVITE sip:\\+?${digits}@[^\\s;>]+:${port}[\\s;>]`),
        );

        // Matched on the dialled number too, so a call story left by an
        // earlier run of this test can't satisfy it.
        const callStory = await waitForCallStory({
          caller: `${caller.username}@acme.comcent.io`,
          callee: c.customerNumber,
          direction: 'outbound',
          timeoutMs: 90_000,
        });
        expect(callStory.spans).toBeGreaterThan(0);
      } finally {
        await context.close();
      }
    },
  );
}
