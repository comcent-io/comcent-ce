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
  // In CI: one worker per core ('100%'). The stack under test is 16
  // containers including FreeSWITCH, and the call flows are real-time with
  // fixed budgets (a caller that holds for 15 s, a 10 s ring window). With
  // more workers than cores FreeSWITCH is starved: on a 2-core runner at 8
  // workers it sat at 0-9% idle CPU, uuid_bridge took 6 s, agents were dialled
  // 8 s late, and a different telephony spec failed each run in ways that
  // looked like product bugs. The suite is CPU-bound, so the extra workers
  // bought almost no time either. A percentage rather than a number, so a
  // bigger runner is used without touching this. PW_WORKERS overrides it; the
  // workflow's manual-run "workers" input sets that, to try a count without a
  // commit.
  workers: Number(process.env.PW_WORKERS) || (process.env.CI ? '100%' : 6),
  // One retry on CI absorbs residual timing flakes; trace capture below
  // already assumes retries exist. Playwright reports a retried pass as
  // 'flaky', so anything that still needs one stays visible.
  retries: process.env.CI ? 1 : 0,
  // In CI also write the HTML report: it carries the trace of every retried
  // test, and it is what the workflow uploads. With 'line' alone that
  // artifact was empty and a red run left nothing to look at.
  reporter:
    process.env.PLAYWRIGHT_REPORTER ||
    (process.env.CI ? [['line'], ['html', { open: 'never' }]] : 'line'),
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
