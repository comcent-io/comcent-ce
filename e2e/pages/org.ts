import type { Page } from '@playwright/test';

export class Organization {
  private page: Page;
  private orgBtn;

  constructor(page: Page) {
    this.page = page;
    this.orgBtn = page.getByRole('link', { name: 'ACME Corp' });
  }

  async gotoDashboard() {
    await this.page.goto('/');
    await this.orgBtn.click({ timeout: 10000 });
  }
}
