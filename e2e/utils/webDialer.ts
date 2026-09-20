import {
  expect,
  type APIRequestContext,
  type Browser,
  type Page,
} from '@playwright/test';

const baseUrl = process.env.PUBLIC_ROOT_URL || 'http://localhost:4173';

type DialerDebugState = {
  consoleMessages: string[];
  requestFailures: string[];
  webSockets: string[];
};

function createDialerDebugState(): DialerDebugState {
  return {
    consoleMessages: [],
    requestFailures: [],
    webSockets: [],
  };
}

function attachDialerDebugListeners(page: Page, debug: DialerDebugState) {
  page.on('console', (message) => {
    debug.consoleMessages.push(`[${message.type()}] ${message.text()}`);
  });
  page.on('pageerror', (error) => {
    debug.consoleMessages.push(`[pageerror] ${error.message}`);
  });
  page.on('requestfailed', (request) => {
    const failure = request.failure();
    debug.requestFailures.push(
      `${request.method()} ${request.url()} :: ${failure?.errorText ?? 'request failed'}`,
    );
  });
  page.on('websocket', (webSocket) => {
    debug.webSockets.push(webSocket.url());
    webSocket.on('socketerror', (error) => {
      debug.consoleMessages.push(
        `[websocket-error] ${webSocket.url()} :: ${error}`,
      );
    });
    webSocket.on('close', () => {
      debug.consoleMessages.push(`[websocket-close] ${webSocket.url()}`);
    });
  });
}

async function readDialerStatus(page: Page) {
  return page.evaluate(() => {
    const dialerWidget = (
      window as Window & {
        dialerWidget?: {
          getUaStatus?: () => string;
        };
      }
    ).dialerWidget;
    return dialerWidget?.getUaStatus?.() ?? null;
  });
}

export async function ensureRegisteredUser(
  request: APIRequestContext,
  params: { name: string; email: string; password: string },
) {
  const response = await request.post('/api/v2/auth/register', {
    data: {
      name: params.name,
      email: params.email,
      password: params.password,
    },
  });

  if (response.ok()) {
    return;
  }

  const body = await response.text();
  if (
    response.status() === 400 &&
    body.toLowerCase().includes('email already exists')
  ) {
    return;
  }

  throw new Error(
    `Failed to register ${params.email}: ${response.status()} ${body}`,
  );
}

export async function loginAsMember(params: {
  browser: Browser;
  request: APIRequestContext;
  email: string;
  password: string;
  subdomain: string;
}) {
  const context = await params.browser.newContext({
    permissions: ['microphone'],
  });
  const page = await context.newPage();
  const debug = createDialerDebugState();
  attachDialerDebugListeners(page, debug);
  const loginResponse = await params.request.post(
    `${baseUrl}/api/v2/auth/login`,
    {
      data: {
        email: params.email,
        password: params.password,
      },
      failOnStatusCode: false,
    },
  );

  if (!loginResponse.ok()) {
    throw new Error(
      `Unable to login ${params.email}: ${loginResponse.status()} ${await loginResponse.text()}`,
    );
  }

  const loginBody = await loginResponse.json();
  const token = loginBody.token;
  if (!token) {
    throw new Error(`Auth login did not return a token for ${params.email}`);
  }

  await context.addCookies([
    {
      name: 'idToken',
      value: token,
      url: baseUrl,
    },
  ]);

  await page.goto(`${baseUrl}/app/${params.subdomain}`);
  await page.waitForLoadState('networkidle');
  await waitForDialerReady(page, debug);

  return { context, page };
}

export async function waitForDialerReady(page: Page, debug?: DialerDebugState) {
  await expect
    .poll(async () =>
      page.evaluate(() =>
        Boolean((window as Window & { dialerWidget?: unknown }).dialerWidget),
      ),
    )
    .toBe(true);

  try {
    await expect
      .poll(async () => (await readDialerStatus(page)) === 'Registered', {
        timeout: 30_000,
      })
      .toBe(true);
  } catch (error) {
    const dialerStatus = await readDialerStatus(page);
    const debugSummary = debug
      ? [
          `Dialer status: ${dialerStatus ?? 'unknown'}`,
          `Observed websockets: ${debug.webSockets.join(', ') || '(none)'}`,
          `Request failures: ${debug.requestFailures.join(' | ') || '(none)'}`,
          `Console: ${debug.consoleMessages.join(' | ') || '(none)'}`,
        ].join('\n')
      : `Dialer status: ${dialerStatus ?? 'unknown'}`;
    throw new Error(
      `${debugSummary}\n\n${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

const DIALER_PRESENCE_STATUSES =
  /^(Logged Out|Available|On Break|On Call|Wrap Up|Busy)$/;

export async function setDialerPresenceStatus(
  page: Page,
  status: 'Logged Out' | 'Available' | 'On Break',
) {
  const widget = page.locator('.dialer-widget');
  // The status pill is a button labelled with the current status; it opens a
  // menu of buttons, one per status. With the menu closed it is the only match.
  const statusPill = widget.getByRole('button', {
    name: DIALER_PRESENCE_STATUSES,
  });
  await expect(statusPill).toBeVisible({ timeout: 30_000 });
  await statusPill.click();
  // The menu follows the pill in the DOM, so when the target equals the
  // current status the menu item is the last match.
  await widget
    .getByRole('button', { name: status, exact: true })
    .last()
    .click();
}

export async function installDialerObservers(page: Page) {
  await page.evaluate(() => {
    const win = window as Window & {
      dialerWidget?: {
        setOnConnectedCallback: (callback: () => void) => void;
        setOnHangupCallback: (callback: () => void) => void;
      };
      __dialerTelemetry?: { connectedCount: number; hangupCount: number };
    };

    win.__dialerTelemetry = { connectedCount: 0, hangupCount: 0 };
    win.dialerWidget?.setOnConnectedCallback(() => {
      if (win.__dialerTelemetry) {
        win.__dialerTelemetry.connectedCount += 1;
      }
    });
    win.dialerWidget?.setOnHangupCallback(() => {
      if (win.__dialerTelemetry) {
        win.__dialerTelemetry.hangupCount += 1;
      }
    });
  });
}

export async function dialFromWidget(
  page: Page,
  params: { fromNumber: string; to: string },
) {
  await page.evaluate(
    async ({ fromNumber, to }) => {
      const win = window as Window & {
        dialerWidget?: {
          dial: (fromNumber: string, to: string) => Promise<void>;
        };
      };

      if (!win.dialerWidget) {
        throw new Error('Dialer widget is not ready');
      }

      await win.dialerWidget.dial(fromNumber, to);
    },
    { fromNumber: params.fromNumber, to: params.to },
  );
}

export async function waitForDialerConnected(page: Page, timeoutMs = 30_000) {
  await expect
    .poll(
      async () =>
        page.evaluate(
          () =>
            (
              window as Window & {
                __dialerTelemetry?: { connectedCount: number };
              }
            ).__dialerTelemetry?.connectedCount ?? 0,
        ),
      { timeout: timeoutMs },
    )
    .toBeGreaterThan(0);
}

export async function waitForDialerHungUp(page: Page, timeoutMs = 30_000) {
  await expect
    .poll(
      async () =>
        page.evaluate(
          () =>
            (
              window as Window & {
                __dialerTelemetry?: { hangupCount: number };
              }
            ).__dialerTelemetry?.hangupCount ?? 0,
        ),
      { timeout: timeoutMs },
    )
    .toBeGreaterThan(0);
}

export async function answerIncomingCall(page: Page) {
  await page.getByRole('button', { name: 'Answer' }).first().click();
}

export async function hangupCurrentCall(page: Page) {
  // Parked calls list their own End buttons above the current call's.
  await page
    .locator('.dialer-widget')
    .getByRole('button', { name: 'End', exact: true })
    .last()
    .click();
}

export async function toggleHold(page: Page) {
  const holdButton = page
    .locator('.dialer-widget')
    .getByRole('button', { name: /^(Hold|Unhold)$/ })
    .first();
  await holdButton.click();
}

async function openTransferMenu(
  page: Page,
  mode: 'Blind Transfer' | 'Attended Transfer',
  transferAddress: string,
) {
  const widget = page.locator('.dialer-widget');
  await widget.getByRole('button', { name: 'Transfer', exact: true }).click();
  await widget.getByRole('button', { name: mode, exact: true }).click();
  await widget.getByPlaceholder('Name or number').fill(transferAddress);

  // Typing a member name opens an autocomplete list over the confirm
  // button; pick the match the way an agent would. Phone numbers skip it.
  if (!/^\+?\d+$/.test(transferAddress)) {
    await widget
      .getByRole('button', { name: new RegExp(`^${transferAddress} \\[`) })
      .click();
  }
}

export async function blindTransferCurrentCall(
  page: Page,
  transferAddress: string,
) {
  await openTransferMenu(page, 'Blind Transfer', transferAddress);
  await page
    .locator('.dialer-widget')
    .getByRole('button', { name: 'Transfer Call', exact: true })
    .click();
}

export async function attendedTransferCurrentCall(
  page: Page,
  transferAddress: string,
) {
  await openTransferMenu(page, 'Attended Transfer', transferAddress);
  await page
    .locator('.dialer-widget')
    .getByRole('button', { name: 'Call Privately', exact: true })
    .click();
}

export async function confirmAttendedTransfer(page: Page) {
  await page
    .locator('.dialer-widget')
    .getByRole('button', { name: 'Complete Transfer', exact: true })
    .click();
}

export async function cancelAttendedTransfer(page: Page) {
  await page
    .locator('.dialer-widget')
    .getByRole('button', { name: 'Resume Call', exact: true })
    .click();
}
