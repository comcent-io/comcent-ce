import { expect } from '@playwright/test';
import type { Page } from '@playwright/test';

export class Profile {
  private page: Page;
  private newKeyBtn;
  private nameTxtBox;
  private createBtn;
  private outboundNumberSelect;
  private updateBtn;
  private closeBtn;
  private newKeyModal;

  constructor(page: Page) {
    this.page = page;
    this.newKeyBtn = page.getByRole('button', { name: 'New key' });
    this.newKeyModal = page
      .locator('[aria-hidden="false"]')
      .filter({ has: page.getByText('New Api Key') });
    this.nameTxtBox = this.newKeyModal.getByPlaceholder('Friendly name');
    this.createBtn = this.newKeyModal.getByRole('button', { name: 'Create' });
    this.outboundNumberSelect = page.getByLabel('Default Outbound Number');
    this.updateBtn = page.getByRole('button', { name: 'Update' });
    this.closeBtn = this.newKeyModal.getByRole('button', {
      name: 'Close modal',
    });
  }

  async gotoMyProfile() {
    await this.page.goto('/app/acme/members/me');
  }

  async makeInput(name: string) {
    await this.newKeyBtn.click();
    await expect(this.newKeyModal).toBeVisible();
    await expect(this.nameTxtBox).toBeVisible();
    await this.nameTxtBox.fill(name);
    await this.createBtn.click();
  }

  async addNewKey(name: string) {
    await this.makeInput(name);
    await expect(this.page.locator(`th:has-text("${name}")`)).toHaveCount(1);
  }

  async addNewKeyWithInvalidInput(name: string) {
    await this.makeInput(name);
    await expect(
      this.page.getByText('Error Error! Name must be at'),
    ).toBeVisible();
    await this.closeBtn.click();
  }

  async deleteKey(name: string) {
    const row = this.page.locator(`tr:has(th:text-is("${name}"))`);
    await expect(row).toHaveCount(1);
    await row.getByRole('button', { name: 'Delete' }).click();
    await expect(row).toHaveCount(0);
  }

  async updateOutboundNumber(number: string) {
    await this.outboundNumberSelect.selectOption(number);
    await this.updateBtn.click();
  }
}
