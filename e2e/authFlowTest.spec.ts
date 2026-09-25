import { expect, test, type Page } from '@playwright/test';
import { LoginPage } from './pages/login';
import { ageVerificationEmailCooldown } from './utils/db';
import {
  waitForPasswordResetLink,
  waitForVerificationLink,
} from './utils/mailhog';

async function clearSession(page: Page) {
  await page.context().clearCookies();
}

test('Password signup, email verification, and login flow works', async ({
  page,
}) => {
  const login = new LoginPage(page);
  const signupEmail = `test.user+auth-${Date.now()}@example.com`;
  const password = 'TestAdmin@1902';

  await login.gotoLoginPage();
  await login.registerPage('Test Admin', signupEmail, password);
  await expect(
    page.getByRole('heading', { name: 'Check your email.' }),
  ).toBeVisible();
  await expect(
    page.locator('p').filter({ hasText: signupEmail }).first(),
  ).toContainText(signupEmail);

  const verificationLink = await waitForVerificationLink(
    page.request,
    signupEmail,
  );
  await page.goto(verificationLink, {
    waitUntil: 'networkidle',
  });

  // CE has no terms-and-conditions gate after signup — email verification
  // lands straight on the org picker.
  await page.waitForURL('/org');

  await clearSession(page);

  await login.gotoLoginPage();
  await login.loginPage(signupEmail, password);
  await page.waitForURL('/org');
});

test('Password signup resend verification is limited to 3 times per day', async ({
  page,
}) => {
  const login = new LoginPage(page);
  const signupEmail = `test.user+resend-${Date.now()}@example.com`;
  const password = 'TestAdmin@1902';

  await login.gotoLoginPage();
  await login.registerPage('Test Admin', signupEmail, password);
  await expect(
    page.getByRole('heading', { name: 'Check your email.' }),
  ).toBeVisible();
  await expect(
    page.locator('p').filter({ hasText: signupEmail }).first(),
  ).toContainText(signupEmail);

  for (let attempt = 1; attempt <= 3; attempt++) {
    await ageVerificationEmailCooldown(signupEmail);

    const response = await page.request.post(
      '/api/v2/auth/resend-verification',
      {
        data: { email: signupEmail },
      },
    );

    expect(response.status(), `resend attempt ${attempt}`).toBe(200);
    await expect
      .poll(async () => (await response.json()) as { message: string })
      .toMatchObject({
        message:
          'If an account exists for that email, a verification email has been sent.',
      });
  }

  await ageVerificationEmailCooldown(signupEmail);

  const blockedResponse = await page.request.post(
    '/api/v2/auth/resend-verification',
    {
      data: { email: signupEmail },
    },
  );

  expect(blockedResponse.status()).toBe(429);
  await expect
    .poll(async () => (await blockedResponse.json()) as { error: string })
    .toMatchObject({
      error: 'You can request up to 3 verification emails per day.',
    });
});

test('Forgot password resets the password once and signs out other sessions', async ({
  page,
  browser,
}) => {
  const login = new LoginPage(page);
  const email = `test.user+reset-${Date.now()}@example.com`;
  const oldPassword = 'TestAdmin@1902';
  const newPassword = 'NewPassword@2026';

  await login.gotoLoginPage();
  await login.registerPage('Reset User', email, oldPassword);
  await page.goto(await waitForVerificationLink(page.request, email), {
    waitUntil: 'networkidle',
  });
  await page.waitForURL('/org');

  // A second browser stays signed in with the old password until the reset.
  const otherContext = await browser.newContext();
  const other = await otherContext.newPage();
  const otherLogin = new LoginPage(other);
  await otherLogin.gotoLoginPage();
  await otherLogin.loginPage(email, oldPassword);
  await other.waitForURL('/org');

  await clearSession(page);
  await login.gotoLoginPage();
  await page.getByRole('link', { name: 'Forgot password?' }).click();
  await page.waitForURL('/auth/forgot-password');
  await page.getByLabel('Email address').fill(email);
  await page.getByRole('button', { name: 'Send reset link' }).click();
  await expect(
    page.getByText(
      'If an account exists for that email, a password reset link has been sent.',
    ),
  ).toBeVisible();

  const resetLink = await waitForPasswordResetLink(page.request, email, 2);
  await page.goto(resetLink);
  await page.getByLabel('New password (8+ characters)').fill(newPassword);
  await page.getByLabel('Confirm new password').fill(newPassword);
  await page.getByRole('button', { name: 'Set new password' }).click();
  await page.waitForURL('/org');

  // The link works once.
  const reuse = await page.request.post('/api/v2/auth/reset-password', {
    data: { token: resetLink.split('/').pop(), password: 'Another@2026' },
  });
  expect(reuse.status()).toBe(400);

  // The other browser's session was issued before the reset.
  const stale = await other.request.get('/api/v2/user/session');
  expect(stale.status()).toBe(401);
  await otherContext.close();

  await clearSession(page);
  await login.gotoLoginPage();
  await login.loginPage(email, oldPassword);
  await expect(page.getByText('Invalid email or password')).toBeVisible();
  await login.loginPage(email, newPassword);
  await page.waitForURL('/org');
});
