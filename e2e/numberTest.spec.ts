import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { Client } from 'pg';
import { v4 as uuid } from 'uuid';

type TestOrg = {
  id: string;
  name: string;
  subdomain: string;
  sipTrunks: Array<{ id: string; name: string }>;
};

type SeededNumber = {
  id: string;
  name: string;
  number: string;
  sipTrunkId: string;
  isDefaultOutboundNumber?: boolean;
  inboundFlowGraph?: string;
};

type SeededVoiceBot = {
  id: string;
  name: string;
};

type SeededQueue = {
  id: string;
  name: string;
};

const DEFAULT_INBOUND_FLOW = JSON.stringify({
  start: '',
  nodes: {},
});

test.describe.configure({ mode: 'parallel' });

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

function uniqueSlug(testInfo: TestInfo) {
  return [
    Date.now().toString(36),
    testInfo.parallelIndex.toString(36),
    Math.random().toString(36).slice(2, 10),
  ].join('');
}

function uniquePhone(seed: string, suffix: number) {
  const tail = `${seed}${suffix}`
    .replace(/[^0-9]/g, '')
    .slice(-10)
    .padStart(10, '0');
  return `+1${tail}`;
}

async function createOrgWithSipTrunks(testInfo: TestInfo): Promise<TestOrg> {
  const client = createClient();
  await client.connect();

  const slug = uniqueSlug(testInfo);
  const org: TestOrg = {
    id: uuid(),
    name: `Numbers ${slug}`,
    subdomain: `n-${slug}`.slice(0, 40),
    sipTrunks: [
      { id: uuid(), name: `Alpha Trunk ${slug}` },
      { id: uuid(), name: `Beta Trunk ${slug}` },
    ],
  };

  try {
    await client.query('BEGIN');

    const adminResult = await client.query<{ id: string }>(
      "SELECT id FROM users WHERE email = 'test.admin@example.com'",
    );
    const adminId = adminResult.rows[0]?.id;

    if (!adminId) {
      throw new Error('Baseline admin user not found');
    }

    await client.query(
      `
        INSERT INTO orgs (
          id,
          name,
          subdomain,
          use_custom_domain,
          assign_ext_automatically,
          is_active,
          enable_sentiment_analysis,
          enable_summary,
          enable_transcription,
          alert_threshold_balance,
          max_members,
          enable_call_recording,
          wallet_balance,
          max_monthly_storage_used,
          storage_used,
          low_balance_alert_count,
          enable_labels,
          enable_daily_summary,
          daily_summary_time_zone,
          created_at,
          updated_at
        )
        VALUES (
          $1, $2, $3, false, false, true, true, true, true, 5, 100, true, 30000000, 0, 0, 0, true, true, 'America/New_York', NOW(), NOW()
        )
      `,
      [org.id, org.name, org.subdomain],
    );

    await client.query(
      `
        INSERT INTO org_members (
          user_id,
          org_id,
          role,
          username,
          sip_password,
          extension_number,
          presence
        )
        VALUES ($1, $2, 'ADMIN', $3, $4, NULL, 'Logged Out')
      `,
      [
        adminId,
        org.id,
        `numbers_${slug}`.slice(0, 20),
        'ytgJ6sp9xcvofYT8UlKlr',
      ],
    );

    for (const trunk of org.sipTrunks) {
      await client.query(
        `
          INSERT INTO sip_trunks (
            id,
            org_id,
            name,
            outbound_username,
            outbound_password,
            outbound_contact,
            inbound_ips,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, 'username', 'password', $4, ARRAY['1.1.1.0/26']::text[], NOW(), NOW())
        `,
        [
          trunk.id,
          org.id,
          trunk.name,
          `${trunk.name.toLowerCase().replace(/\s+/g, '-')}.example.com`,
        ],
      );
    }

    await client.query('COMMIT');
    return org;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function seedNumbers(org: TestOrg, numbers: SeededNumber[]) {
  const client = createClient();
  await client.connect();

  try {
    await client.query('BEGIN');

    for (const number of numbers) {
      await client.query(
        `
          INSERT INTO numbers (
            id,
            name,
            number,
            allow_outbound_regex,
            org_id,
            sip_trunk_id,
            is_default_outbound_number,
            inbound_flow_graph,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, NULL, $4, $5, $6, $7::jsonb, NOW(), NOW())
        `,
        [
          number.id,
          number.name,
          number.number,
          org.id,
          number.sipTrunkId,
          number.isDefaultOutboundNumber ?? false,
          number.inboundFlowGraph ?? DEFAULT_INBOUND_FLOW,
        ],
      );
    }

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function seedVoiceBots(org: TestOrg, voiceBots: SeededVoiceBot[]) {
  const client = createClient();
  await client.connect();

  try {
    await client.query('BEGIN');

    for (const voiceBot of voiceBots) {
      await client.query(
        `
          INSERT INTO voice_bots
            (id, org_id, name, instructions, not_to_do_instructions, greeting_instructions, mcp_servers, api_key, is_hangup, is_enqueue, queues, pipeline)
          VALUES
            ($1, $2, $3, 'Help callers', 'Do not be rude', 'Hello there', '[]'::jsonb, 'dummy-key', false, false, ARRAY[]::text[], 'default')
        `,
        [voiceBot.id, org.id, voiceBot.name],
      );
    }

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function gotoNumbersPage(page: Page, subdomain: string) {
  await page.goto(`/app/${subdomain}/numbers`);
  await expect(page.getByRole('heading', { name: 'Numbers' })).toBeVisible();
  await expect(page.locator('#add-new-no-btn')).toBeVisible();
}

async function gotoCreateNumberPage(page: Page, subdomain: string) {
  await page.goto(`/app/${subdomain}/numbers/create`);
  await expect(
    page.getByRole('heading', { name: 'Create Number' }),
  ).toBeVisible();
  await expect(page.getByPlaceholder('Friendly Name')).toBeVisible();
  await expect(page.getByPlaceholder('Number in E.164 format')).toBeVisible();
  await expect(page.locator('#sipTrunkId')).toBeVisible();
}

async function fillStable(
  page: Page,
  locator: ReturnType<Page['locator']>,
  value: string,
) {
  for (let attempt = 0; attempt < 3; attempt++) {
    await locator.fill(value);
    await expect(locator).toHaveValue(value);
    await page.waitForTimeout(200);

    if ((await locator.inputValue()) === value) {
      return;
    }
  }

  await expect(locator).toHaveValue(value);
}

async function fillNumberForm(
  page: Page,
  input: {
    name: string;
    number: string;
    trunkName: string;
    allowOutboundRegex?: string;
  },
) {
  await fillStable(page, page.getByPlaceholder('Friendly Name'), input.name);
  await fillStable(
    page,
    page.getByPlaceholder('Number in E.164 format'),
    input.number,
  );
  await page.locator('#sipTrunkId').selectOption({ label: input.trunkName });
  await expect(page.locator('#sipTrunkId')).toHaveValue(/.+/);

  if (input.allowOutboundRegex !== undefined) {
    await fillStable(
      page,
      page.getByPlaceholder('^\\+1[0-9]{10}$'),
      input.allowOutboundRegex,
    );
  }
}

async function createNumber(
  page: Page,
  subdomain: string,
  input: {
    name: string;
    number: string;
    trunkName: string;
    allowOutboundRegex?: string;
  },
) {
  await gotoCreateNumberPage(page, subdomain);
  await fillNumberForm(page, input);
  await page.getByRole('button', { name: 'Add', exact: true }).click();
}

async function openEditNumberPage(page: Page, subdomain: string, name: string) {
  await gotoNumbersPage(page, subdomain);
  const row = page.locator('tbody tr').filter({ hasText: name }).first();
  await expect(row).toBeVisible();
  await row.getByRole('link', { name: 'Edit' }).click();
  await expect(
    page.getByRole('heading', { name: 'Numbers Edit' }),
  ).toBeVisible();
}

async function getNumberFlowGraph(numberId: string) {
  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{ inbound_flow_graph: unknown }>(
      'SELECT inbound_flow_graph FROM numbers WHERE id = $1',
      [numberId],
    );
    return result.rows[0]?.inbound_flow_graph as {
      start?: string;
      nodes?: Record<string, any>;
    };
  } finally {
    await client.end();
  }
}

async function waitForCreatedNumberId(orgId: string, name: string) {
  await expect
    .poll(
      async () => {
        const client = createClient();
        await client.connect();

        try {
          const result = await client.query<{ id: string }>(
            'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
            [orgId, name],
          );
          return result.rows[0]?.id ?? '';
        } finally {
          await client.end();
        }
      },
      {
        message: `waiting for number ${name} to be created`,
        timeout: 15_000,
      },
    )
    .not.toBe('');

  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{ id: string }>(
      'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
      [orgId, name],
    );
    return result.rows[0]?.id ?? '';
  } finally {
    await client.end();
  }
}

function findGraphNodeByType(
  graph: { nodes?: Record<string, any> } | undefined,
  type: string,
) {
  return Object.values(graph?.nodes ?? {}).find(
    (node: any) => node.type === type || node.data?.type === type,
  ) as any;
}

async function seedQueueForOrg(
  orgId: string,
  name: string,
): Promise<SeededQueue> {
  const client = createClient();
  await client.connect();

  const queue = {
    id: uuid(),
    name,
  };

  try {
    await client.query(
      `
        INSERT INTO queues
          (id, name, extension, org_id, created_at, updated_at, max_no_answers, wrap_up_time, reject_delay_time)
        VALUES
          ($1, $2, NULL, $3, NOW(), NOW(), 2, 30, 30)
      `,
      [queue.id, queue.name, orgId],
    );
    return queue;
  } finally {
    await client.end();
  }
}

function createMenuGraph(menuId: string, outletKey = '1') {
  return JSON.stringify({
    start: menuId,
    nodes: {
      [menuId]: {
        id: menuId,
        type: 'Menu',
        data: {
          promptAudio: '',
          errorAudio: '',
          repeat: 3,
          afterPromptWaitTime: 3,
          multiDigitWaitTime: 3,
        },
        outlets: {
          [outletKey]: '',
        },
      },
    },
  });
}

function flowCanvas(page: Page) {
  return page.locator('.flow-canvas');
}

function menuBlock(page: Page) {
  return nodeBlock(page, 'Menu');
}

function voiceBotBlock(page: Page) {
  return nodeBlock(page, 'VoiceBot');
}

function nodeBlock(page: Page, heading: string) {
  return flowCanvas(page)
    .getByText(heading, { exact: true })
    .last()
    .locator('xpath=ancestor::div[contains(@class, "block")][1]');
}

async function addFlowStep(
  page: Page,
  stepName:
    | 'Dial'
    | 'Menu'
    | 'Queue'
    | 'Play'
    | 'WeekTime'
    | 'VoiceBot'
    | 'DialGroup',
) {
  await page.getByRole('button', { name: 'Add step' }).click();
  await page
    .locator('#dropdown')
    .getByRole('button', { name: stepName, exact: true })
    .click();
}

async function connectStartToNode(page: Page, targetHeading: string) {
  await flowCanvas(page)
    .getByRole('button', { name: /start begin here|connect from here start/i })
    .first()
    .click();

  const connectTargets = flowCanvas(page).getByRole('button', {
    name: /connect here|target/i,
  });
  if (await connectTargets.count()) {
    await connectTargets.first().click();
  } else {
    await nodeBlock(page, targetHeading).click({ force: true });
  }
}

async function addMenuOption(page: Page, digits: string) {
  const block = menuBlock(page);
  if (await block.getByRole('button', { name: 'Add option' }).count()) {
    await block.getByRole('button', { name: 'Add option' }).click();
    await block.getByLabel('Digits callers press').fill(digits);
    await block.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(block.getByText('Caller presses')).toBeVisible();
  } else {
    const input = block
      .getByPlaceholder('Enter prompt digit')
      .or(block.locator('input[type="number"]').last());
    await input.fill(digits);
    await input.press('Enter');
  }
  await expect(block.getByText(digits, { exact: true })).toBeVisible();
}

function queueBlock(page: Page) {
  return nodeBlock(page, 'Queue');
}

async function selectQueueNode(page: Page, queueName: string) {
  await flowCanvas(page)
    .locator('select')
    .last()
    .selectOption({ label: queueName });
}

async function connectMenuOptionToQueue(page: Page, digits: string) {
  await menuBlock(page)
    .getByRole('button', {
      name: new RegExp(
        `(route out|connect from here).*(^|\\s)${digits}(\\s|$)|(^|\\s)${digits}(\\s|$)`,
        'i',
      ),
    })
    .last()
    .click({ force: true });

  const queueTarget = queueBlock(page).getByRole('button', {
    name: /connect here|target/i,
  });
  if (await queueTarget.count()) {
    await queueTarget.click({ force: true });
  } else {
    await queueBlock(page).click({ force: true });
  }
}

async function connectOutletByLabel(page: Page, outletLabel: string) {
  await flowCanvas(page)
    .getByRole('button', {
      name: new RegExp(
        `(route out|connect from here).*(^|\\s)${outletLabel}(\\s|$)|(^|\\s)${outletLabel}(\\s|$)`,
        'i',
      ),
    })
    .last()
    .click({ force: true });

  await flowCanvas(page)
    .getByRole('button', { name: /connect here|target/i })
    .first()
    .click({ force: true });
}

async function selectVoiceBotNode(page: Page, voiceBotName: string) {
  const block = voiceBotBlock(page);
  const select = block.locator('select');
  if (await select.count()) {
    await select.selectOption({ label: voiceBotName });
  }
}

async function updateNumber(
  page: Page,
  subdomain: string,
  currentName: string,
  next: {
    name: string;
    number: string;
    trunkName: string;
    allowOutboundRegex: string;
  },
) {
  await openEditNumberPage(page, subdomain, currentName);
  await page.getByPlaceholder('Friendly Name').fill(next.name);
  await page.getByPlaceholder('Number in E.164 format').fill(next.number);
  await page.locator('#sipTrunkId').selectOption({ label: next.trunkName });
  await page.locator('#allowOutboundRegex').fill(next.allowOutboundRegex);
  await page.getByRole('button', { name: 'Update' }).click();
}

test('Numbers page, add number successfully', async ({ page }, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const newNumber = uniquePhone(org.subdomain, 11);
  const name = `Atlas ${org.subdomain}`;

  await createNumber(page, org.subdomain, {
    name,
    number: newNumber,
    trunkName: org.sipTrunks[1].name,
  });

  await expect(page).toHaveURL(`/app/${org.subdomain}/numbers`);
  const row = page.locator('tbody tr').filter({ hasText: name }).first();
  await expect(row).toContainText(newNumber);
  await expect(row).toContainText(org.sipTrunks[1].name);
});

test('Numbers page, add existing number', async ({ page }, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const existingNumber = uniquePhone(org.subdomain, 12);

  await seedNumbers(org, [
    {
      id: uuid(),
      name: 'Existing Number',
      number: existingNumber,
      sipTrunkId: org.sipTrunks[0].id,
    },
  ]);

  await createNumber(page, org.subdomain, {
    name: 'Duplicate Number',
    number: existingNumber,
    trunkName: org.sipTrunks[1].name,
  });

  await expect(page.getByText('Number already exists')).toBeVisible();
});

test('Numbers page, update number successfully', async ({ page }, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const original = {
    id: uuid(),
    name: 'Original Number',
    number: uniquePhone(org.subdomain, 13),
    sipTrunkId: org.sipTrunks[0].id,
  };
  await seedNumbers(org, [original]);

  const updatedName = `Updated ${org.subdomain}`;
  const updatedNumber = uniquePhone(org.subdomain, 14);

  await updateNumber(page, org.subdomain, original.name, {
    name: updatedName,
    number: updatedNumber,
    trunkName: org.sipTrunks[1].name,
    allowOutboundRegex: '^\\+1[0-9]{10}$',
  });

  await expect(page).toHaveURL(`/app/${org.subdomain}/numbers`);
  const row = page.locator('tbody tr').filter({ hasText: updatedName }).first();
  await expect(row).toContainText(updatedNumber);
  await expect(row).toContainText(org.sipTrunks[1].name);
});

test('Numbers page, try to update number with already existing number', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const primary = {
    id: uuid(),
    name: 'Primary Number',
    number: uniquePhone(org.subdomain, 15),
    sipTrunkId: org.sipTrunks[0].id,
  };
  const duplicateTarget = {
    id: uuid(),
    name: 'Duplicate Target',
    number: uniquePhone(org.subdomain, 16),
    sipTrunkId: org.sipTrunks[1].id,
  };
  await seedNumbers(org, [primary, duplicateTarget]);

  await updateNumber(page, org.subdomain, primary.name, {
    name: primary.name,
    number: duplicateTarget.number,
    trunkName: org.sipTrunks[1].name,
    allowOutboundRegex: duplicateTarget.number,
  });

  await expect(page.getByText('Number already exists')).toBeVisible();
});

test('Numbers page, set to default successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const first = {
    id: uuid(),
    name: 'Default Target',
    number: uniquePhone(org.subdomain, 17),
    sipTrunkId: org.sipTrunks[0].id,
  };
  const second = {
    id: uuid(),
    name: 'Other Number',
    number: uniquePhone(org.subdomain, 18),
    sipTrunkId: org.sipTrunks[1].id,
    isDefaultOutboundNumber: true,
  };
  await seedNumbers(org, [first, second]);

  await gotoNumbersPage(page, org.subdomain);
  const row = page.locator('tbody tr').filter({ hasText: first.name }).first();
  await row.getByRole('button', { name: 'Set As Default' }).click();

  await expect(row).toContainText('Yes');
});

test('Numbers page, pagination works correctly', async ({ page }, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const seededNumbers = Array.from({ length: 10 }, (_, index) => ({
    id: uuid(),
    name: `Number ${String(index + 1).padStart(2, '0')}`,
    number: uniquePhone(org.subdomain, index + 20),
    sipTrunkId: org.sipTrunks[index % 2].id,
  }));
  await seedNumbers(org, seededNumbers);

  await gotoNumbersPage(page, org.subdomain);
  await page.locator('#itemsPerPage').selectOption('5');
  await expect.poll(() => page.url()).toContain('itemsPerPage=5');
  await expect(page.locator('tbody tr')).toHaveCount(5);

  await expect(
    page.locator('tbody tr').filter({ hasText: 'Number 01' }),
  ).toBeVisible();
  await expect(
    page.locator('tbody tr').filter({ hasText: 'Number 05' }),
  ).toBeVisible();
  await expect(
    page.locator('tbody tr').filter({ hasText: 'Number 06' }),
  ).toHaveCount(0);

  await page.locator('nav li').filter({ hasText: '2' }).click();
  await expect.poll(() => page.url()).toContain('page=2');
  await expect(page.locator('tbody tr')).toHaveCount(5);

  await expect(
    page.locator('tbody tr').filter({ hasText: 'Number 06' }),
  ).toBeVisible();
  await expect(
    page.locator('tbody tr').filter({ hasText: 'Number 10' }),
  ).toBeVisible();
});

test('Numbers page, delete number successfully', async ({ page }, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const removable = {
    id: uuid(),
    name: 'Delete Me',
    number: uniquePhone(org.subdomain, 30),
    sipTrunkId: org.sipTrunks[0].id,
  };
  await seedNumbers(org, [removable]);

  await gotoNumbersPage(page, org.subdomain);
  const row = page
    .locator('tbody tr')
    .filter({ hasText: removable.name })
    .first();

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.getByRole('button', { name: 'No, cancel' }).click();
  await expect(row).toHaveCount(1);

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.locator('[data-modal-hide="popup-modal"]').click();
  await expect(row).toHaveCount(1);

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();
  await gotoNumbersPage(page, org.subdomain);
  await expect(
    page.locator('tbody tr').filter({ hasText: removable.name }),
  ).toHaveCount(0);
});

test('Numbers page, create number with dial flow node successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const name = `Dial Flow ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 34);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'Dial');
  await connectStartToNode(page, 'Dial');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const createdNumberId = await waitForCreatedNumberId(org.id, name);

  const graph = await getNumberFlowGraph(createdNumberId);
  const dialNode = findGraphNodeByType(graph, 'Dial');
  expect(dialNode).toBeTruthy();
  expect(graph?.start).toBe(dialNode.id);
  expect(dialNode.outlets).toEqual(
    expect.objectContaining({ timeout: expect.any(String) }),
  );
});

test('Numbers page, create number with dial group flow node successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const name = `DialGroup Flow ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 35);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'DialGroup');
  await connectStartToNode(page, 'DialGroup');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const createdNumberId = await waitForCreatedNumberId(org.id, name);

  const graph = await getNumberFlowGraph(createdNumberId);
  const dialGroupNode = findGraphNodeByType(graph, 'DialGroup');
  expect(dialGroupNode).toBeTruthy();
  expect(graph?.start).toBe(dialGroupNode.id);
  expect(dialGroupNode.outlets).toEqual(
    expect.objectContaining({ timeout: expect.any(String) }),
  );
});

test('Numbers page, create number with play flow node successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const name = `Play Flow ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 36);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'Play');
  await connectStartToNode(page, 'Play');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const createdNumberId = await waitForCreatedNumberId(org.id, name);

  const graph = await getNumberFlowGraph(createdNumberId);
  const playNode = findGraphNodeByType(graph, 'Play');
  expect(playNode).toBeTruthy();
  expect(graph?.start).toBe(playNode.id);
});

test('Numbers page, create number with week time flow node successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const name = `WeekTime Flow ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 37);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'WeekTime');
  await connectStartToNode(page, 'WeekTime');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const createdNumberId = await waitForCreatedNumberId(org.id, name);

  const graph = await getNumberFlowGraph(createdNumberId);
  const weekTimeNode = findGraphNodeByType(graph, 'WeekTime');
  expect(weekTimeNode).toBeTruthy();
  expect(weekTimeNode.outlets).toEqual(
    expect.objectContaining({
      true: expect.any(String),
      false: expect.any(String),
    }),
  );
});

test('Numbers page, create number with voice bot flow node successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const voiceBot = { id: uuid(), name: `Voice Bot ${org.subdomain}` };
  await seedVoiceBots(org, [voiceBot]);
  const name = `VoiceBot Flow ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 38);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'VoiceBot');
  await selectVoiceBotNode(page, voiceBot.name);
  await connectStartToNode(page, 'VoiceBot');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  const createdNumberId = await waitForCreatedNumberId(org.id, name);

  const graph = await getNumberFlowGraph(createdNumberId);
  const voiceBotNode = findGraphNodeByType(graph, 'VoiceBot');
  expect(voiceBotNode).toBeTruthy();
  expect(graph?.start).toBe(voiceBotNode.id);
  if (voiceBotNode.data.voiceBotId) {
    expect(voiceBotNode.data.voiceBotId).toBe(voiceBot.id);
  }
});

test('Numbers page, create number with menu flow diagram successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  uuid(); // generate but unused — keeps deterministic test ordering
  const name = `Flow Create ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 31);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });

  await addFlowStep(page, 'Menu');
  await addMenuOption(page, '1');
  await connectStartToNode(page, 'Menu');
  await page.getByRole('button', { name: 'Add', exact: true }).click();

  await expect(page).toHaveURL(`/app/${org.subdomain}/numbers`);
  const row = page.locator('tbody tr').filter({ hasText: name }).first();
  await expect(row).toContainText(number);

  const client = createClient();
  await client.connect();
  let createdNumberId = '';
  try {
    const result = await client.query<{ id: string }>(
      'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
      [org.id, name],
    );
    createdNumberId = result.rows[0]?.id ?? '';
  } finally {
    await client.end();
  }

  expect(createdNumberId).not.toBe('');

  const graph = await getNumberFlowGraph(createdNumberId);
  expect(graph?.start).toBeTruthy();
  expect(Object.values(graph?.nodes ?? {})).toHaveLength(1);
  const menuNode = findGraphNodeByType(graph, 'Menu');
  expect(menuNode).toBeTruthy();
  expect(menuNode.outlets).toEqual({ '1': '' });
});

test('Numbers page, update number flow diagram successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const menuId = uuid();
  const seeded = {
    id: uuid(),
    name: 'Flow Update Seed',
    number: uniquePhone(org.subdomain, 32),
    sipTrunkId: org.sipTrunks[0].id,
    inboundFlowGraph: createMenuGraph(menuId, '1'),
  };
  await seedNumbers(org, [seeded]);

  await openEditNumberPage(page, org.subdomain, seeded.name);
  await expect(menuBlock(page)).toBeVisible();
  await addFlowStep(page, 'Queue');
  await connectMenuOptionToQueue(page, '1');
  await page.getByRole('button', { name: 'Update' }).click({ force: true });

  await expect
    .poll(async () => {
      const graph = await getNumberFlowGraph(seeded.id);
      const menuNode = graph?.nodes?.[menuId] as any;
      const queueNodeEntry = findGraphNodeByType(graph, 'Queue');
      if (!menuNode || !queueNodeEntry) {
        return 'pending';
      }
      return menuNode.outlets?.['1'] === queueNodeEntry.id
        ? 'saved'
        : 'pending';
    })
    .toBe('saved');

  const graph = await getNumberFlowGraph(seeded.id);
  expect(graph?.start).toBe(menuId);
  const menuNode = graph?.nodes?.[menuId] as any;
  expect(menuNode.type).toBe('Menu');
  const queueNodeEntry = findGraphNodeByType(graph, 'Queue');
  expect(queueNodeEntry).toBeTruthy();
  expect(menuNode.outlets['1']).toBe(queueNodeEntry.id);
});

test('Numbers page, create number with dial timeout route successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const queue = await seedQueueForOrg(
    org.id,
    `timeout_${uniqueSlug(testInfo)}`,
  );
  const name = `Dial Timeout ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 39);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'Dial');
  await addFlowStep(page, 'Queue');
  await selectQueueNode(page, queue.name);
  await connectStartToNode(page, 'Dial');
  await connectOutletByLabel(page, 'Timeout');
  await page.getByRole('button', { name: 'Add', exact: true }).click();

  const client = createClient();
  await client.connect();
  let createdNumberId = '';
  try {
    const result = await client.query<{ id: string }>(
      'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
      [org.id, name],
    );
    createdNumberId = result.rows[0]?.id ?? '';
  } finally {
    await client.end();
  }

  const graph = await getNumberFlowGraph(createdNumberId);
  const dialNode = findGraphNodeByType(graph, 'Dial');
  const queueNodeEntry = findGraphNodeByType(graph, 'Queue');
  expect(dialNode).toBeTruthy();
  expect(queueNodeEntry).toBeTruthy();
  expect(graph?.start).toBe(dialNode.id);
  expect(dialNode.outlets?.timeout).toBe(queueNodeEntry.id);
});

test('Numbers page, create number with dial group timeout route successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const queue = await seedQueueForOrg(
    org.id,
    `timeout_${uniqueSlug(testInfo)}`,
  );
  const name = `DialGroup Timeout ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 40);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'DialGroup');
  await addFlowStep(page, 'Queue');
  await selectQueueNode(page, queue.name);
  await connectStartToNode(page, 'DialGroup');
  await connectOutletByLabel(page, 'Timeout');
  await page.getByRole('button', { name: 'Add', exact: true }).click();

  const client = createClient();
  await client.connect();
  let createdNumberId = '';
  try {
    const result = await client.query<{ id: string }>(
      'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
      [org.id, name],
    );
    createdNumberId = result.rows[0]?.id ?? '';
  } finally {
    await client.end();
  }

  const graph = await getNumberFlowGraph(createdNumberId);
  const dialGroupNode = findGraphNodeByType(graph, 'DialGroup');
  const queueNodeEntry = findGraphNodeByType(graph, 'Queue');
  expect(dialGroupNode).toBeTruthy();
  expect(queueNodeEntry).toBeTruthy();
  expect(graph?.start).toBe(dialGroupNode.id);
  expect(dialGroupNode.outlets?.timeout).toBe(queueNodeEntry.id);
});

test('Numbers page, create number with week time true and false routes successfully', async ({
  page,
}, testInfo) => {
  const org = await createOrgWithSipTrunks(testInfo);
  const queue = await seedQueueForOrg(
    org.id,
    `weektime_${uniqueSlug(testInfo)}`,
  );
  const name = `WeekTime Routes ${org.subdomain}`;
  const number = uniquePhone(org.subdomain, 41);

  await gotoCreateNumberPage(page, org.subdomain);
  await fillNumberForm(page, {
    name,
    number,
    trunkName: org.sipTrunks[0].name,
  });
  await addFlowStep(page, 'WeekTime');
  await addFlowStep(page, 'Play');
  await addFlowStep(page, 'Queue');
  await selectQueueNode(page, queue.name);
  await connectStartToNode(page, 'WeekTime');
  await connectOutletByLabel(page, 'true');
  await connectOutletByLabel(page, 'false');
  await page.getByRole('button', { name: 'Add', exact: true }).click();

  const client = createClient();
  await client.connect();
  let createdNumberId = '';
  try {
    const result = await client.query<{ id: string }>(
      'SELECT id FROM numbers WHERE org_id = $1 AND name = $2',
      [org.id, name],
    );
    createdNumberId = result.rows[0]?.id ?? '';
  } finally {
    await client.end();
  }

  const graph = await getNumberFlowGraph(createdNumberId);
  const weekTimeNode = findGraphNodeByType(graph, 'WeekTime');
  const playNode = findGraphNodeByType(graph, 'Play');
  const queueNodeEntry = findGraphNodeByType(graph, 'Queue');
  expect(weekTimeNode).toBeTruthy();
  expect(playNode).toBeTruthy();
  expect(queueNodeEntry).toBeTruthy();
  expect(graph?.start).toBe(weekTimeNode.id);
  expect(weekTimeNode.outlets?.true).toBe(playNode.id);
  expect(weekTimeNode.outlets?.false).toBe(queueNodeEntry.id);
});
