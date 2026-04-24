import { test as setup } from '@playwright/test';
import { STORAGE_STATE } from './playwright.config';
import { truncateAllTables } from './utils/db';
import {
  seedBaselineData,
  waitForAppReady,
  writeAuthenticatedStorageState,
} from './utils/bootstrap';
import {
  killAllSippProcesses,
  restartServer,
  waitForKamailioDispatcher,
  waitForServerHealthy,
} from './utils/sipp';

setup(
  'seed baseline data and auth state',
  async ({ browser, request, baseURL }) => {
    setup.setTimeout(120_000);

    await waitForAppReady(request);
    await truncateAllTables();
    await killAllSippProcesses();

    await restartServer();
    await waitForServerHealthy();
    await waitForKamailioDispatcher();

    const { user } = await seedBaselineData();

    await writeAuthenticatedStorageState(
      browser,
      STORAGE_STATE,
      user,
      baseURL || 'http://localhost:4173',
    );
  },
);
