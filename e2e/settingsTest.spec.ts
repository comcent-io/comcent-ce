import { test } from '@playwright/test';
import { expect } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

async function gotToApiKeyPage(page) {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('link', { name: 'API Keys' }).click();
}

test('Settings page, add key successfully', async ({ page }) => {
  await gotToApiKeyPage(page);
  await page.getByRole('button', { name: 'New Key' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('Staging Key');
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(
    page.getByRole('rowheader', { name: 'Staging Key' }),
  ).toBeVisible();
});

test('Settings page, add key with invalid input', async ({ page }) => {
  await gotToApiKeyPage(page);
  await page.getByRole('button', { name: 'New Key' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('a');
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.getByText('Name must be at least 3')).toBeVisible();
});

test('Settings page, delete key successfully', async ({ page }) => {
  await gotToApiKeyPage(page);
  await page.getByRole('button', { name: 'Delete' }).click();
  await expect(page.getByRole('status')).toContainText(
    'API Key deleted successfully',
  );
});

test('Settings page, add webhook successfully', async ({ page }) => {
  const webhookUrl = 'https://abc.efg/ccef';
  const webhookName = 'Staging Webhook';
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'New Webhook' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill(webhookName);
  await page.getByPlaceholder('Friendly name').press('Tab');
  await page.getByPlaceholder('Webhook URL').fill(webhookUrl);
  await page.getByLabel('Call Update Event').check();
  await page.getByLabel('Presence Update Event').check();
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.locator('tbody')).toContainText(webhookName);
  await expect(page.locator('tbody')).toContainText(webhookUrl);
  await expect(page.locator('tbody')).toContainText(
    'CALL_UPDATE,PRESENCE_UPDATE',
  );
});

test('Settings page, add webhook with webhook url input', async ({ page }) => {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'New Webhook' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('Second Webhook');
  await page.getByPlaceholder('Friendly name').press('Tab');
  await page.getByPlaceholder('Webhook URL').fill('efg.com');
  await page.getByLabel('Presence Update Event').check();
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.getByRole('status')).toContainText(
    'Invalid Webhook URL format',
  );
});

test('Settings page, add webhook with invalid name input', async ({ page }) => {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'New Webhook' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('A');
  await page.getByPlaceholder('Friendly name').press('Tab');
  await page.getByPlaceholder('Webhook URL').fill('http://efg.com/sadf');
  await page.getByLabel('Presence Update Event').check();
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.getByRole('status')).toContainText(
    'String must contain at least 3 character(s)',
  );
});

test('Settings page, add webhook with no events selected', async ({ page }) => {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'New Webhook' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('No events');
  await page.getByPlaceholder('Friendly name').press('Tab');
  await page.getByPlaceholder('Webhook URL').fill('http://efg.com/sadf');
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.getByRole('status')).toContainText(
    'Please select at least one event',
  );
});

test('Settings page, update webhook successfully', async ({ page }) => {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'Edit' }).click();
  await page.getByPlaceholder('Friendly name').click();
  await page.getByPlaceholder('Friendly name').fill('Staging Webhook changed');
  await page.getByPlaceholder('Webhook URL').click();
  await page.getByPlaceholder('Webhook URL').fill('https://abc.efg/ccef/efg');
  await page.getByLabel('Presence Update Event').uncheck();
  await page.getByRole('button', { name: 'Create' }).click();
  await expect(page.locator('tbody')).toContainText('Staging Webhook changed');
  await expect(page.locator('tbody')).toContainText('https://abc.efg/ccef/efg');
  await expect(page.locator('tbody')).toContainText('CALL_UPDATE');
});

test('Settings page, delete webhook successfully', async ({ page }) => {
  await page.goto('/app/acme');
  await page.getByRole('link', { name: 'Settings' }).click();
  await page.getByRole('button', { name: 'Delete' }).click();
  await expect(page.getByRole('status')).toContainText(
    'Webhook deleted successfully',
  );
});
