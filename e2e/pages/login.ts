import type { Page } from '@playwright/test';

export class LoginPage {
  private page: Page;
  private emailTxtBox;
  private passwordTxtBox;
  private submitBtn;
  private createAccountBtn;
  private nameTxtBox;
  private createSubmitBtn;

  constructor(page: Page) {
    this.page = page;
    this.emailTxtBox = page.getByLabel('Email address');
    this.passwordTxtBox = page.getByLabel('Password');
    this.submitBtn = page.getByRole('button', {
      name: 'Continue',
      exact: true,
    });
    this.createAccountBtn = page.getByRole('button', {
      name: 'Create account',
      exact: true,
    });
    this.nameTxtBox = page.getByLabel('Full name');
    this.createSubmitBtn = page.getByRole('button', {
      name: 'Create account',
    });
  }

  private async openLoginForm() {
    const logoutBtn = this.page.getByRole('button', { name: 'Logout' });
    if (await logoutBtn.isVisible().catch(() => false)) {
      await logoutBtn.click();
    }

    return this.emailTxtBox.isVisible().catch(() => false);
  }

  private async waitForLoginPageReady() {
    for (let attempt = 0; attempt < 30; attempt++) {
      try {
        const response = await this.page.request.get('/login', {
          failOnStatusCode: false,
        });
        const bodyText = await response.text();

        if (
          response.status() === 200 &&
          !bodyText.includes('502 Bad Gateway')
        ) {
          return;
        }
      } catch {
        // App is still starting up.
      }

      await this.page.waitForTimeout(2000);
    }

    throw new Error('Login page never became ready');
  }

  async gotoLoginPage() {
    await this.waitForLoginPageReady();

    for (let attempt = 0; attempt < 6; attempt++) {
      await this.page.goto('/login', { waitUntil: 'domcontentloaded' });

      if (await this.openLoginForm()) return;

      const bodyText =
        (await this.page
          .locator('body')
          .textContent()
          .catch(() => '')) ?? '';
      if (bodyText.includes('502 Bad Gateway')) {
        await this.page.waitForTimeout(2000);
        continue;
      }

      await this.page.waitForTimeout(1000);
    }

    throw new Error('Unable to reach login form');
  }

  async loginPage(email: string, password: string) {
    await this.emailTxtBox.fill(email);
    await this.passwordTxtBox.fill(password);
    await this.submitBtn.click();
  }

  async registerPage(name: string, email: string, password: string) {
    await this.createAccountBtn.first().click();
    await this.nameTxtBox.fill(name);
    await this.emailTxtBox.fill(email);
    await this.passwordTxtBox.fill(password);
    await this.createSubmitBtn.last().click();
  }
}
