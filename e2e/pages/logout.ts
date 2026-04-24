import type { Page } from '@playwright/test';

export class Logout {
  private page: Page;
  private profileBtn;
  private logoutBtn;

  constructor(page: Page) {
    this.page = page;
    this.profileBtn = page.locator(
      'button:has(span:text-is("Open user menu"))',
    );
    this.logoutBtn = page.locator('button:has-text("Logout")');
  }

  async executeLogout() {
    await this.profileBtn.locator('img').click();
    await this.logoutBtn.click();
  }
}
