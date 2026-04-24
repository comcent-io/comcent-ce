import { test, expect, type Page } from '@playwright/test';

test.describe.configure({ mode: 'parallel' });

type SipTrunkFormInput = {
  name: string;
  provideOutboundCredentials?: boolean;
  username?: string;
  password?: string;
  proxyAddress: string;
  inboundIps: string[];
};

function uniqueSipTrunkName(prefix: string) {
  const suffix = Math.random().toString(36).slice(2, 8);
  const maxPrefixLength = 25 - suffix.length - 1;
  return `${prefix.slice(0, maxPrefixLength)}-${suffix}`;
}

function sipTrunkRow(page: Page, name: string) {
  return page.locator(`tr:has(td:has-text("${name}"))`);
}

function sipTrunkEditLink(page: Page, name: string) {
  return sipTrunkRow(page, name).getByRole('link', { name: 'Edit' });
}

function sipTrunkDeleteButton(page: Page, name: string) {
  return sipTrunkRow(page, name).getByRole('button', { name: 'Delete' });
}

async function gotoSipTrunkPage(page: Page) {
  await page.goto('/app/acme/sip-trunks');
  await expect(page.getByRole('link', { name: 'Create' })).toBeVisible();
}

async function gotoCreateSipTrunkPage(page: Page) {
  await gotoSipTrunkPage(page);
  await page.getByRole('link', { name: 'Create' }).click();
  await expect(page.getByPlaceholder('Your Name')).toBeVisible();
}

async function fillSipTrunkForm(page: Page, params: SipTrunkFormInput) {
  await page.getByPlaceholder('Your Name').fill(params.name);

  const credentialsCheckbox = page.getByLabel('Provide Outbound Credentials');
  const usernameInput = page.getByPlaceholder('your username');
  const passwordInput = page.getByPlaceholder('Password');

  if (params.provideOutboundCredentials) {
    await credentialsCheckbox.check();
    await expect(usernameInput).toBeVisible();
    await usernameInput.fill(params.username ?? '');
    await passwordInput.fill(params.password ?? '');
  } else {
    await credentialsCheckbox.uncheck();
    await expect(usernameInput).toHaveCount(0);
  }

  await page.getByPlaceholder('provider.example.com').fill(params.proxyAddress);
  await page.getByPlaceholder('/24').fill(params.inboundIps.join(', '));
}

async function createSipTrunk(page: Page, params: SipTrunkFormInput) {
  await gotoCreateSipTrunkPage(page);
  await fillSipTrunkForm(page, params);
  await page.getByRole('button', { name: 'Create' }).click();
}

async function openSipTrunkForEdit(page: Page, name: string) {
  await gotoSipTrunkPage(page);
  await sipTrunkEditLink(page, name).click();
  await expect(page.getByPlaceholder('Your Name')).toBeVisible();
}

async function updateSipTrunk(
  page: Page,
  currentName: string,
  params: SipTrunkFormInput,
) {
  await openSipTrunkForEdit(page, currentName);
  await fillSipTrunkForm(page, params);
  await page.getByRole('button', { name: 'Update' }).click();
}

async function expectSipTrunkError(page: Page, message: RegExp | string) {
  await expect(page.getByText(message).first()).toBeVisible();
}

async function createSipTrunkAndExpectSuccess(
  page: Page,
  params: SipTrunkFormInput,
) {
  await createSipTrunk(page, params);
  await expect(page).toHaveURL('/app/acme/sip-trunks');
  await expect(sipTrunkRow(page, params.name)).toHaveCount(1);
}

test('Sip trunk page, add sip trunk successfully', async ({ page }) => {
  const name = uniqueSipTrunkName('SecondSip');

  await createSipTrunkAndExpectSuccess(page, {
    name,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.second-sip.com',
    inboundIps: ['3.14.5.1/26'],
  });
});

test('Sip trunk page, add sip trunk successfully without outbound credentials', async ({
  page,
}) => {
  const name = uniqueSipTrunkName('NoCredential');

  await createSipTrunkAndExpectSuccess(page, {
    name,
    provideOutboundCredentials: false,
    proxyAddress: 'provider-no-auth.example.com',
    inboundIps: ['11.14.5.1/26'],
  });
});

test('Sip trunk page, add with invalid proxy address', async ({ page }) => {
  await createSipTrunk(page, {
    name: 'Invalid Sip',
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'sip:invalid-sip.com',
    inboundIps: ['23.14.5.1/24'],
  });
  await expectSipTrunkError(
    page,
    /Invalid SIP Proxy Address|Sip Proxy Address should be/i,
  );
});

test('Sip trunk page, add with invalid inbound ips', async ({ page }) => {
  await createSipTrunk(page, {
    name: 'Invalid Sip',
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.invalid-sip.com',
    inboundIps: ['23.14.5.1'],
  });
  await expectSipTrunkError(
    page,
    /Inbound IPs should be comma separated CIDR|Inbound IP Address at position 1 is invalid/i,
  );
});

test('Sip trunk page, add with invalid inbound ips at second position shows correct message', async ({
  page,
}) => {
  const name = uniqueSipTrunkName('SecondInvalidIp');

  await gotoCreateSipTrunkPage(page);
  await fillSipTrunkForm(page, {
    name,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'provider.example.com',
    inboundIps: ['23.14.5.1/24', '23.14.5.999/24'],
  });
  await page.getByRole('button', { name: 'Create' }).click();

  await expectSipTrunkError(
    page,
    /Error: Inbound IP Address at position 2 is invalid/i,
  );
});

test('Sip trunk page, add with too short name shows validation error', async ({
  page,
}) => {
  await gotoCreateSipTrunkPage(page);
  await fillSipTrunkForm(page, {
    name: 'AB',
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'provider.example.com',
    inboundIps: ['23.14.5.1/24'],
  });
  await page.getByRole('button', { name: 'Create' }).click();

  await expectSipTrunkError(
    page,
    /name: String must contain at least 3 character\(s\)/i,
  );
});

test('Sip trunk page, add with too long name shows validation error', async ({
  page,
}) => {
  await gotoCreateSipTrunkPage(page);
  await fillSipTrunkForm(page, {
    name: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'provider.example.com',
    inboundIps: ['23.14.5.1/24'],
  });
  await page.getByRole('button', { name: 'Create' }).click();

  await expectSipTrunkError(
    page,
    /name: String must contain at most 25 character\(s\)/i,
  );
});

test('Sip trunk page, update sip trunk successfully', async ({ page }) => {
  const existingName = uniqueSipTrunkName('EditableSip');
  const updatedName = uniqueSipTrunkName('UpdatedSip');

  await createSipTrunkAndExpectSuccess(page, {
    name: existingName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.editable-sip.com',
    inboundIps: ['3.15.4.1/26'],
  });

  await updateSipTrunk(page, existingName, {
    name: updatedName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.updated-sip.com',
    inboundIps: ['3.15.5.1/26'],
  });
  await expect(page).toHaveURL('/app/acme/sip-trunks');
  await expect(sipTrunkRow(page, updatedName)).toHaveCount(1);
  await expect(sipTrunkRow(page, existingName)).toHaveCount(0);
});

test('Sip trunk page, update with invalid proxy address', async ({ page }) => {
  const existingName = uniqueSipTrunkName('InvalidProxyBase');
  const attemptedName = uniqueSipTrunkName('InvalidProxyTry');

  await createSipTrunkAndExpectSuccess(page, {
    name: existingName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.proxy-base.com',
    inboundIps: ['3.15.6.1/26'],
  });

  await updateSipTrunk(page, existingName, {
    name: attemptedName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'sip:invalid-sip.com',
    inboundIps: ['3.15.5.1/24'],
  });
  await expectSipTrunkError(page, /Invalid SIP Proxy Address/i);
});

test('Sip trunk page, update with invalid inbound ips', async ({ page }) => {
  const existingName = uniqueSipTrunkName('InvalidInboundBase');
  const attemptedName = uniqueSipTrunkName('InvalidInboundTry');

  await createSipTrunkAndExpectSuccess(page, {
    name: existingName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.inbound-base.com',
    inboundIps: ['3.15.7.1/26'],
  });

  await updateSipTrunk(page, existingName, {
    name: attemptedName,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.invalid-sip.com',
    inboundIps: ['343.15.5.1/24'],
  });
  await expectSipTrunkError(
    page,
    /Inbound IP Address at position 1 is invalid/i,
  );
});

test('Sip trunk page, delete the sip trunk successfully', async ({ page }) => {
  const name = uniqueSipTrunkName('DeleteSip');

  await createSipTrunkAndExpectSuccess(page, {
    name,
    provideOutboundCredentials: true,
    username: 'username',
    password: 'password',
    proxyAddress: 'www.delete-sip.com',
    inboundIps: ['3.15.8.1/26'],
  });

  await page.goto('/app/acme/sip-trunks');
  await page.waitForTimeout(200);
  await sipTrunkDeleteButton(page, name).click();
  await page.getByRole('button', { name: 'No, cancel' }).click();
  await expect(sipTrunkRow(page, name)).toHaveCount(1);
  await sipTrunkDeleteButton(page, name).click();
  await page.locator('button').filter({ hasText: 'Close modal' }).click();
  await expect(sipTrunkRow(page, name)).toHaveCount(1);
  await sipTrunkDeleteButton(page, name).click();
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();
  await expect(sipTrunkRow(page, name)).toHaveCount(0);
});

test('Sip trunk page, deleting sip trunk used in numbers should fail', async ({
  page,
}) => {
  await page.goto('/app/acme/sip-trunks');
  await page.waitForTimeout(200);
  await sipTrunkDeleteButton(page, 'Last Sip').click();
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();
  await expect(
    page.getByText(
      'Cannot delete Last Sip as it is used in numbers +14155552672',
    ),
  ).toBeVisible();
});
