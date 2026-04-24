import { defineConfig, devices } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from 'dotenv';

config({
  path: path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    '..',
    '.env.e2e',
  ),
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const STORAGE_STATE = path.join(__dirname, 'playwright/.auth/user.json');

export default defineConfig({
  testDir: '.',
  testMatch: '**/*.{spec,setup}.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  workers: process.env.CI ? 8 : 6,
  reporter: process.env.PLAYWRIGHT_REPORTER || 'line',
  use: {
    baseURL: process.env.PUBLIC_ROOT_URL || 'http://localhost:4173',
    trace: 'on-first-retry',
    permissions: ['microphone'],
    launchOptions: {
      args: [
        '--use-fake-ui-for-media-stream',
        '--use-fake-device-for-media-stream',
        '--autoplay-policy=no-user-gesture-required',
      ],
    },
  },

  projects: [
    {
      name: 'createOrg',
      testMatch: /global.setup\.ts/,
      timeout: 120000,
    },
    {
      name: 'auth',
      testMatch: /authFlowTest\.spec\.ts/,
      timeout: 120000,
      dependencies: ['createOrg'],
      use: {
        ...devices['Desktop Chrome'],
        timezoneId: 'America/New_York',
      },
    },
    {
      name: 'chromium',
      testMatch: '**/*.spec.ts',
      testIgnore: /authFlowTest\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        storageState: STORAGE_STATE,
        timezoneId: 'America/New_York',
      },
      dependencies: ['createOrg'],
      timeout: 30000,
    },
  ],
});
