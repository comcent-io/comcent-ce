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
  // CE org creation has no billing address fields; success returns to the
  // org picker rather than the billing page.
  await page.getByRole('button', { name: 'Create Organization' }).click();
  await page.waitForURL('/org');
  await page.goto('/app/acme');
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('aiet');
  await expect(page).toHaveURL('/app/aiet');
  await page.getByRole('button', { name: 'Switch Organization' }).click();
  await page.locator('#switchOrganization').selectOption('acme');
  await expect(page).toHaveURL('/app/acme');
});
