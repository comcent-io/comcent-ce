import { test } from '@playwright/test';
import { Profile } from './pages/profile';

test.describe.configure({ mode: 'serial' });

test('My profile page, add key successfully', async ({ page }) => {
  const profile = new Profile(page);
  await profile.gotoMyProfile();
  await profile.addNewKey('First key');
});

test('My profile page, add key with invalid input', async ({ page }) => {
  const profile = new Profile(page);
  await profile.gotoMyProfile();
  await profile.addNewKeyWithInvalidInput('Fk');
});

test('My profile page, delete key successfully', async ({ page }) => {
  const profile = new Profile(page);
  await profile.gotoMyProfile();
  await profile.deleteKey('First key');
});

test('My profile page, update outbound number successfully', async ({
  page,
}) => {
  const profile = new Profile(page);
  await profile.gotoMyProfile();
  await profile.updateOutboundNumber('+14155552671');
});
