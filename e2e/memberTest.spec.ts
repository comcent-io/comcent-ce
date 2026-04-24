import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { Client } from 'pg';
import { v4 as uuid } from 'uuid';
import { ageInviteEmailCooldown } from './utils/db';
import { waitForInvitationLink, waitForMessageCount } from './utils/mailhog';

type MemberRole = 'ADMIN' | 'MEMBER';

type TestOrg = {
  id: string;
  name: string;
  subdomain: string;
};

test.describe.configure({ mode: 'parallel' });

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

function uniqueSlug(testInfo: TestInfo) {
  return [
    Date.now().toString(36),
    testInfo.parallelIndex.toString(36),
    Math.random().toString(36).slice(2, 10),
  ].join('');
}

function memberEmail(slug: string, label: string) {
  return `${label}+${slug}@example.com`;
}

function memberUsername(slug: string, label: string) {
  return `${label}_${slug}`.replace(/[^a-z0-9_]/g, '').slice(0, 20);
}

async function createOrgForTest(testInfo: TestInfo): Promise<TestOrg> {
  const client = createClient();
  await client.connect();

  const slug = uniqueSlug(testInfo);
  const subdomain = `m-${slug}`.slice(0, 40);
  const org: TestOrg = {
    id: uuid(),
    name: `Members ${slug}`,
    subdomain,
  };

  try {
    await client.query('BEGIN');
    const adminResult = await client.query<{ id: string }>(
      `SELECT id FROM users WHERE email = 'test.admin@example.com'`,
    );

    const adminId = adminResult.rows[0]?.id;
    if (!adminId) {
      throw new Error('Baseline admin user not found');
    }

    await client.query(
      `
        INSERT INTO orgs (
          id,
          name,
          subdomain,
          use_custom_domain,
          assign_ext_automatically,
          is_active,
          enable_sentiment_analysis,
          enable_summary,
          enable_transcription,
          alert_threshold_balance,
          max_members,
          enable_call_recording,
          wallet_balance,
          max_monthly_storage_used,
          storage_used,
          low_balance_alert_count,
          enable_labels,
          enable_daily_summary,
          daily_summary_time_zone,
          created_at,
          updated_at
        )
        VALUES (
          $1, $2, $3, false, false, true, true, true, true, 5, 100, true, 30000000, 0, 0, 0, true, true, 'America/New_York', NOW(), NOW()
        )
      `,
      [org.id, org.name, org.subdomain],
    );

    await client.query(
      `
        INSERT INTO org_members (
          user_id,
          org_id,
          role,
          username,
          sip_password,
          extension_number,
          presence
        )
        VALUES ($1, $2, 'ADMIN', $3, $4, NULL, 'Logged Out')
      `,
      [adminId, org.id, memberUsername(slug, 'owner'), 'ytgJ6sp9xcvofYT8UlKlr'],
    );

    await client.query('COMMIT');
    return org;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function seedMember(org: TestOrg, email: string, role: MemberRole = 'MEMBER') {
  const client = createClient();
  await client.connect();

  try {
    await client.query('BEGIN');

    const userResult = await client.query<{ id: string }>(
      `SELECT id FROM users WHERE email = $1`,
      [email],
    );

    const userId = userResult.rows[0]?.id ?? uuid();

    if (!userResult.rows[0]) {
      await client.query(
        `
          INSERT INTO users (
            id,
            name,
            email,
            is_email_verified,
            has_agreed_to_tos,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, true, true, NOW(), NOW())
        `,
        [userId, email, email],
      );
    }

    await client.query(
      `
        INSERT INTO org_members (
          user_id,
          org_id,
          role,
          username,
          sip_password,
          extension_number,
          presence
        )
        VALUES ($1, $2, $3, $4, $5, NULL, 'Logged Out')
        ON CONFLICT DO NOTHING
      `,
      [userId, org.id, role, memberUsername(org.subdomain, email.split('@')[0]), 'ytgJ6sp9xcvofYT8UlKlr'],
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function seedMembers(org: TestOrg, emails: string[]) {
  for (const email of emails) {
    await seedMember(org, email);
  }
}

async function gotoMembersPage(page: Page, subdomain: string) {
  await page.goto(`/app/${subdomain}/members`);
  await expect(page.getByRole('heading', { name: 'Members' })).toBeVisible();
}

async function openInviteForm(page: Page) {
  await page.getByRole('button', { name: 'Invite', exact: true }).click();
  await expect(page.locator('#email')).toBeVisible();
}

async function sendInvite(page: Page, subdomain: string, email: string, role: MemberRole) {
  await gotoMembersPage(page, subdomain);
  await openInviteForm(page);
  await page.locator('#email').fill(email);
  await page.locator('#role').selectOption(role);
  await page.getByRole('button', { name: 'Send Invite' }).click();
}

async function openPendingInvitesTab(page: Page) {
  await page.getByRole('button', { name: /Pending Invites \(/ }).click();
}

async function expectInviteRow(page: Page, email: string) {
  await expect(page.getByRole('cell', { name: email })).toBeVisible();
}

async function openMemberEditPage(page: Page, subdomain: string, email: string) {
  await gotoMembersPage(page, subdomain);
  const row = page.locator('tbody tr').filter({ hasText: email }).first();
  await expect(row).toBeVisible();
  await row.getByRole('link', { name: 'Edit' }).click();
  await expect(page.getByRole('heading', { name: 'Edit Member' })).toBeVisible();
}

test('Member list page, send invitation successfully and show it in pending invites', async ({
  page,
}, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const inviteEmail = memberEmail(org.subdomain, 'invite-success');

  await sendInvite(page, org.subdomain, inviteEmail, 'MEMBER');
  await expect(page.getByText('Invite Sent Successfully')).toBeVisible();

  const invitationLink = await waitForInvitationLink(page.request, inviteEmail);
  expect(invitationLink).toContain(`/invitation/`);
  expect(invitationLink).toContain('http://localhost:4173');

  await openPendingInvitesTab(page);
  await expectInviteRow(page, inviteEmail);
  await expect(page.getByRole('cell', { name: 'MEMBER' })).toBeVisible();
  await expect(page.getByRole('cell', { name: 'PENDING' })).toBeVisible();
  const row = page.locator('tbody tr').filter({ hasText: inviteEmail }).first();
  await expect(row.getByRole('cell', { name: '0', exact: true })).toBeVisible();
});

test('Member list page, send invitation to already invited user', async ({ page }, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const inviteEmail = memberEmail(org.subdomain, 'already-invited');

  await sendInvite(page, org.subdomain, inviteEmail, 'MEMBER');
  await expect(page.getByText('Invite Sent Successfully')).toBeVisible();

  await sendInvite(page, org.subdomain, inviteEmail, 'ADMIN');
  await expect(page.getByText('User is already invited to this organization')).toBeVisible();
});

test('Member list page, send invitation to existing member', async ({ page }, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const email = memberEmail(org.subdomain, 'existing-member');
  await seedMember(org, email);

  await sendInvite(page, org.subdomain, email, 'ADMIN');
  await expect(page.getByText('User is already a member of this organization')).toBeVisible();
});

test('Member list page, edit role successfully', async ({ page }, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const email = memberEmail(org.subdomain, 'edit-role');
  await seedMember(org, email);

  await openMemberEditPage(page, org.subdomain, email);
  await page.locator('#role').selectOption('ADMIN');
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(page.locator('h5')).toContainText(`${email} (ADMIN)`);
});

test('Member list page, regenerate password successfully', async ({ page }, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const email = memberEmail(org.subdomain, 'regen-password');
  await seedMember(org, email);

  await openMemberEditPage(page, org.subdomain, email);
  const passwordInput = page.locator('input[type="password"]').first();
  const oldPassword = await passwordInput.inputValue();

  await page.getByRole('button', { name: 'Regenerate password' }).click();

  await expect(async () => {
    const newPassword = await passwordInput.inputValue();
    expect(newPassword).not.toEqual(oldPassword);
  }).toPass({ timeout: 5000 });
});

test('Member list page, resend invite is limited to 3 times per day', async ({
  page,
}, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const inviteEmail = memberEmail(org.subdomain, 'resend-invite');

  await sendInvite(page, org.subdomain, inviteEmail, 'MEMBER');
  await expect(page.getByText('Invite Sent Successfully')).toBeVisible();
  await waitForMessageCount(page.request, inviteEmail, 1);

  await openPendingInvitesTab(page);
  await expectInviteRow(page, inviteEmail);

  for (let attempt = 1; attempt <= 3; attempt++) {
    await ageInviteEmailCooldown(org.subdomain, inviteEmail);

    const row = page.locator('tbody tr').filter({ hasText: inviteEmail }).first();
    await row.getByRole('button', { name: 'Resend' }).click();
    await expect(page.getByText('Invite resent successfully').first()).toBeVisible();
    await waitForMessageCount(page.request, inviteEmail, attempt + 1);
    await expect(row.getByRole('cell', { name: String(attempt), exact: true })).toBeVisible();
  }

  await ageInviteEmailCooldown(org.subdomain, inviteEmail);
  const row = page.locator('tbody tr').filter({ hasText: inviteEmail }).first();
  await row.getByRole('button', { name: 'Resend' }).click();

  await expect(
    page.getByText('This invitation can only be resent 3 times in 24 hours.'),
  ).toBeVisible();
  await expect(row.getByRole('cell', { name: '3', exact: true })).toBeVisible();
});

test('Members list page, pagination works correctly', async ({ page }, testInfo) => {
  const org = await createOrgForTest(testInfo);
  const emails = Array.from({ length: 10 }, (_, index) =>
    `member-${String(index + 1).padStart(2, '0')}@${org.subdomain}.example.com`,
  );
  await seedMembers(org, emails);

  await gotoMembersPage(page, org.subdomain);
  await page.locator('#itemsPerPage').selectOption('5');

  await expect(page.locator('tbody tr').filter({ hasText: emails[0] })).toBeVisible();
  await expect(page.locator('tbody tr').filter({ hasText: emails[4] })).toBeVisible();
  await expect(page.locator('tbody tr').filter({ hasText: emails[5] })).toHaveCount(0);

  await page.locator('nav li').filter({ hasText: '2' }).click();

  await expect(page.locator('tbody tr').filter({ hasText: emails[5] })).toBeVisible();
  await expect(page.locator('tbody tr').filter({ hasText: emails[9] })).toBeVisible();
});
