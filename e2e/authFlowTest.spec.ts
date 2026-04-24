import { expect, test, type Page } from '@playwright/test';
import { LoginPage } from './pages/login';
import { ageVerificationEmailCooldown } from './utils/db';
import { waitForVerificationLink } from './utils/mailhog';

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

  await expect(page).toHaveURL('/terms-conditions');
  await expect(
    page.getByText('Terms of Service and Privacy Policy'),
  ).toBeVisible();

  await page.getByRole('button', { name: 'I accept' }).click();
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
