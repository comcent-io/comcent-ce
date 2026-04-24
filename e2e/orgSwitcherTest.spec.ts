import { test, expect } from '@playwright/test';

test('Home page, switch organization successfully', async ({ page }) => {
  // heartcoders org is created in global setup
  await page.goto('/app/acme');
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('heartcoders');
  await expect(page).toHaveURL('/app/heartcoders');
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('acme');
  await expect(page).toHaveURL('/app/acme');
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.getByRole('link', { name: 'Create Organization' }).click();
  await page.getByPlaceholder('your.name').click();
  await page.getByPlaceholder('your.name').fill('aiet');
  await page.getByPlaceholder('ACME Corp').fill('Alvas');
  await page.getByPlaceholder('acme', { exact: true }).fill('aiet');
  await page.getByPlaceholder('Billing Name').fill('aiet');
  await page.getByLabel('Country').selectOption('IN');
  await page.getByLabel('State').selectOption('Karnataka');
  await page.getByPlaceholder('City').click();
  await page.getByPlaceholder('City').fill('Moodbidri');
  await page.getByLabel('Zip Code').click();
  await page.getByLabel('Zip Code').fill('574227');
  await page.getByRole('button', { name: 'Create Organization' }).click();
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('aiet');
  await expect(page).toHaveURL(
    '/app/aiet/settings/billing/balance?redirected=true',
  );
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('acme');
  await expect(page).toHaveURL('/app/acme');
});
