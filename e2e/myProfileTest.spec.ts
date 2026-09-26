import { test } from '@playwright/test';
import { Profile } from './pages/profile';

test.describe.configure({ mode: 'serial' });

test('My profile page, update outbound number successfully', async ({
  page,
}) => {
  const profile = new Profile(page);
  await profile.gotoMyProfile();
  await profile.updateOutboundNumber('+14155552671');
});
