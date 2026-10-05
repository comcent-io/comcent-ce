import { test, expect, type Page } from '@playwright/test';

// The organization list can always be reached; signing in (the
// /app entry point) is what reopens the last used org. The baseline admin is
// in acme and heartcoders (global setup).

async function rememberOrg(page: Page, subdomain: string) {
  await page.goto('/org');
  await page.evaluate(
    (value) => localStorage.setItem('selectedSubdomain', value),
    subdomain,
  );
}

test('the organization list shows, and marks the last used org, instead of opening it', async ({
  page,
}) => {
  await rememberOrg(page, 'heartcoders');

  await page.goto('/org');
  await expect(
    page.getByRole('heading', { name: 'Your organizations' }),
  ).toBeVisible();
  await expect(page).toHaveURL('/org');

  const heartcoders = page.getByRole('link', { name: /heartcoders/i });
  await expect(heartcoders.getByText('Last used')).toBeVisible();
  await expect(
    page.getByRole('link', { name: /acme/i }).getByText('Last used'),
  ).toHaveCount(0);

  // Create organization and back: still the list.
  await page.getByRole('link', { name: /Create Organization/ }).click();
  await page.waitForURL('/org/create');
  await page.goBack();
  await expect(page).toHaveURL('/org');
  await expect(
    page.getByRole('heading', { name: 'Your organizations' }),
  ).toBeVisible();
});

test('signing in reopens the last used org', async ({ page }) => {
  await rememberOrg(page, 'heartcoders');

  await page.goto('/app');
  await expect(page).toHaveURL(/\/app\/heartcoders(\/|$)/);
});

test('signing in shows the list when the last used org is no longer theirs', async ({
  page,
}) => {
  await rememberOrg(page, 'not-a-member-of-this');

  await page.goto('/app');
  await expect(page).toHaveURL('/org');
  await expect(
    page.getByRole('heading', { name: 'Your organizations' }),
  ).toBeVisible();
});
