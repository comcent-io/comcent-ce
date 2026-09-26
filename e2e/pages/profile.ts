import type { Page } from '@playwright/test';

export class Profile {
  private page: Page;
  private outboundNumberSelect;
  private updateBtn;

  constructor(page: Page) {
    this.page = page;
    this.outboundNumberSelect = page.getByLabel('Default Outbound Number');
    this.updateBtn = page.getByRole('button', { name: 'Update' });
  }

  async gotoMyProfile() {
    await this.page.goto('/app/acme/members/me');
  }

  async updateOutboundNumber(number: string) {
    await this.outboundNumberSelect.selectOption(number);
    await this.updateBtn.click();
  }
}
