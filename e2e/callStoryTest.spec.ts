import { test, expect, type Page } from '@playwright/test';
import {
  LABELLED_CALLS,
  seedLabelledCallsOrg,
} from './utils/callStoryLabelData';

// The list's rows: each call has a View button.
function callRows(page: Page) {
  return page
    .getByRole('row')
    .filter({ has: page.getByRole('button', { name: 'View' }) });
}

// COM-155: unticking every label of an applied filter and pressing Apply shows
// all calls again, the same as Clear.
test('Call Story, unticking every applied label and applying shows all calls', async ({
  page,
}) => {
  const subdomain = await seedLabelledCallsOrg();
  await page.goto(`/app/${subdomain}/call-story`);
  await expect(callRows(page)).toHaveCount(LABELLED_CALLS.length);

  const labelsButton = page.getByRole('button', { name: 'Filter by labels' });
  const apply = page.getByRole('button', { name: 'Apply', exact: true });
  const clear = page.getByRole('button', { name: 'Clear', exact: true });

  // Nothing ticked and nothing applied: nothing to apply or clear.
  await labelsButton.click();
  await expect(page.getByText('0 selected')).toBeVisible();
  await expect(apply).toBeDisabled();
  await expect(clear).toHaveCount(0);

  await page.getByRole('checkbox', { name: 'Billing' }).check();
  await page.getByRole('checkbox', { name: 'Refund' }).check();
  await apply.click();
  await expect(page).toHaveURL(/labels=Billing(%2C|,)Refund/);
  await expect(callRows(page)).toHaveCount(2);
  await expect(page.getByRole('cell', { name: '+15550100003' })).toHaveCount(0);

  // Reopened unchanged, Apply has nothing to do.
  await labelsButton.click();
  await expect(apply).toBeDisabled();

  await page.getByRole('checkbox', { name: 'Billing' }).uncheck();
  await expect(apply).toBeEnabled();
  await page.getByRole('checkbox', { name: 'Refund' }).uncheck();
  await expect(page.getByText('0 selected')).toBeVisible();
  await expect(apply).toBeEnabled();
  await expect(clear).toBeVisible();

  await apply.click();
  await expect(page).not.toHaveURL(/labels=/);
  await expect(callRows(page)).toHaveCount(LABELLED_CALLS.length);
  for (const { caller } of LABELLED_CALLS) {
    await expect(page.getByRole('cell', { name: caller })).toBeVisible();
  }
  await expect(page.getByText('Showing calls labelled')).toHaveCount(0);
});
