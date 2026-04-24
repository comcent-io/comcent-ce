import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { Client } from 'pg';
import { v4 as uuid } from 'uuid';

test.describe.configure({ mode: 'parallel' });

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

function uniqueSlug(testInfo: TestInfo) {
  return [
    Date.now().toString(36),
    testInfo.parallelIndex.toString(36),
    Math.random().toString(36).slice(2, 8),
  ].join('');
}

function uniqueQueueName(prefix: string, testInfo: TestInfo) {
  const suffix = uniqueSlug(testInfo).replace(/[^a-z0-9_]/gi, '');
  return `${prefix}_${suffix}`.slice(0, 20);
}

function uniqueExtension(testInfo: TestInfo, seed = 0) {
  const digits = `${Date.now()}${testInfo.parallelIndex}${seed}`
    .replace(/\D/g, '')
    .slice(-5)
    .padStart(5, '0');
  return digits;
}

async function gotoQueuesPage(page: Page, subdomain = 'acme') {
  await page.goto(`/app/${subdomain}/queues`);
  await expect(page.getByRole('heading', { name: 'Queues' })).toBeVisible();
}

async function gotoQueueCreatePage(page: Page, subdomain = 'acme') {
  await gotoQueuesPage(page, subdomain);
  await page.getByRole('link', { name: 'Add' }).click();
  await expect(page.getByPlaceholder('Queue Name (e.g. sales,')).toBeVisible();
}

type QueueFormInput = {
  name: string;
  extension?: string;
};

async function fillQueueForm(page: Page, input: QueueFormInput) {
  await page.getByPlaceholder('Queue Name (e.g. sales,').fill(input.name);
  await page
    .getByPlaceholder('Optional extension number')
    .fill(input.extension ?? '');
}

async function createQueue(
  page: Page,
  input: QueueFormInput,
  subdomain = 'acme',
) {
  await gotoQueueCreatePage(page, subdomain);
  await fillQueueForm(page, input);
  await page.getByRole('button', { name: /^Add$/ }).click();
}

function queueRow(page: Page, queueName: string) {
  return page.locator(`tr:has(th:text-is("${queueName}"))`);
}

async function openDeleteDialog(row: ReturnType<typeof queueRow>) {
  await row.getByRole('button', { name: 'Delete' }).evaluate((button) => {
    (button as HTMLButtonElement).click();
  });
}

async function openQueueEdit(
  page: Page,
  queueName: string,
  subdomain = 'acme',
) {
  await gotoQueuesPage(page, subdomain);
  const row = queueRow(page, queueName);
  await expect(row).toHaveCount(1);
  const href = await row
    .getByRole('link', { name: 'Edit' })
    .getAttribute('href');
  if (!href) {
    throw new Error(`Edit link not found for queue ${queueName}`);
  }
  await page.goto(href);
  await expect(page.getByRole('heading', { name: 'Edit Queue' })).toBeVisible();
}

async function createQueueInDb(params: {
  subdomain: string;
  name: string;
  extension?: string | null;
}) {
  const client = createClient();
  await client.connect();

  try {
    const orgResult = await client.query<{ id: string }>(
      'SELECT id FROM orgs WHERE subdomain = $1',
      [params.subdomain],
    );
    const orgId = orgResult.rows[0]?.id;

    if (!orgId) {
      throw new Error(`Org ${params.subdomain} not found`);
    }

    const queueId = uuid();
    await client.query(
      `
        INSERT INTO queues
          (id, name, extension, org_id, created_at, updated_at, max_no_answers, wrap_up_time, reject_delay_time)
        VALUES
          ($1, $2, $3, $4, NOW(), NOW(), 2, 30, 30)
      `,
      [queueId, params.name, params.extension ?? null, orgId],
    );

    return { id: queueId, orgId };
  } finally {
    await client.end();
  }
}

async function seedOrgMemberForQueue(
  email: string,
  name: string,
  username: string,
  subdomain = 'acme',
) {
  const client = createClient();
  await client.connect();

  try {
    await client.query('BEGIN');

    const orgResult = await client.query<{ id: string }>(
      'SELECT id FROM orgs WHERE subdomain = $1',
      [subdomain],
    );
    const orgId = orgResult.rows[0]?.id;

    if (!orgId) {
      throw new Error(`${subdomain} org not found`);
    }

    const userId = uuid();

    await client.query(
      `
        INSERT INTO users (
          id,
          name,
          email,
          is_email_verified,
          has_agreed_to_tos,
          agreed_to_tos_at,
          created_at,
          updated_at
        )
        VALUES ($1, $2, $3, true, true, NOW(), NOW(), NOW())
      `,
      [userId, name, email],
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
        VALUES ($1, $2, 'MEMBER', $3, 'ytgJ6sp9xcvofYT8UlKlr', NULL, 'Logged Out')
      `,
      [userId, orgId, username],
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

async function seedNumberWithQueue(params: {
  subdomain: string;
  queueName: string;
  numberName: string;
  phoneNumber: string;
}) {
  const client = createClient();
  await client.connect();

  const queueNodeId = uuid();

  try {
    const orgResult = await client.query<{ id: string }>(
      'SELECT id FROM orgs WHERE subdomain = $1',
      [params.subdomain],
    );
    const orgId = orgResult.rows[0]?.id;

    const trunkResult = await client.query<{ id: string }>(
      'SELECT id FROM sip_trunks WHERE org_id = $1 ORDER BY created_at ASC LIMIT 1',
      [orgId],
    );
    const sipTrunkId = trunkResult.rows[0]?.id;

    if (!orgId || !sipTrunkId) {
      throw new Error(`${params.subdomain} org or sip trunk not found`);
    }

    const inboundFlowGraph = {
      start: queueNodeId,
      nodes: {
        [queueNodeId]: {
          id: queueNodeId,
          type: 'Queue',
          data: {
            queue: params.queueName,
          },
        },
      },
    };

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
        VALUES ($1, $2, $3, NULL, $4, $5, false, $6::jsonb, NOW(), NOW())
      `,
      [
        uuid(),
        params.numberName,
        params.phoneNumber,
        orgId,
        sipTrunkId,
        JSON.stringify(inboundFlowGraph),
      ],
    );
  } finally {
    await client.end();
  }
}

async function seedVoiceBotWithQueue(params: {
  subdomain: string;
  queueName: string;
  voiceBotName: string;
}) {
  const client = createClient();
  await client.connect();

  try {
    const orgResult = await client.query<{ id: string }>(
      'SELECT id FROM orgs WHERE subdomain = $1',
      [params.subdomain],
    );
    const orgId = orgResult.rows[0]?.id;

    if (!orgId) {
      throw new Error(`${params.subdomain} org not found`);
    }

    await client.query(
      `
        INSERT INTO voice_bots
          (id, org_id, name, instructions, not_to_do_instructions, greeting_instructions, mcp_servers, api_key, is_hangup, is_enqueue, queues, pipeline)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, false, true, $9, 'DEEPGRAM_AND_OPENAI')
      `,
      [
        uuid(),
        orgId,
        params.voiceBotName,
        'Handle queue calls for tests.',
        'Do not deviate from the test path.',
        'Greet the caller.',
        JSON.stringify([
          { url: 'http://server:4000/mcp', token: 'abcdefghijk' },
        ]),
        `api_${uuid().replace(/-/g, '')}`,
        [params.queueName],
      ],
    );
  } finally {
    await client.end();
  }
}

test('Queues page, add queue successfully', async ({ page }, testInfo) => {
  const queueName = uniqueQueueName('support', testInfo);
  const extension = uniqueExtension(testInfo, 1);

  await createQueue(page, { name: queueName, extension });

  await expect(
    page.getByText('Queue created successfully for org acme'),
  ).toBeVisible();
});

test('Queues page, add queue with existing name should fail', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('dupname', testInfo);

  await createQueue(page, {
    name: queueName,
    extension: uniqueExtension(testInfo, 1),
  });
  await createQueue(page, {
    name: queueName,
    extension: uniqueExtension(testInfo, 2),
  });

  await expect(
    page.getByText(`Queue already exists with name ${queueName}`),
  ).toBeVisible();
});

test('Queues page, add queue with existing extension should fail', async ({
  page,
}, testInfo) => {
  const extension = uniqueExtension(testInfo, 1);

  await createQueue(page, {
    name: uniqueQueueName('alpha', testInfo),
    extension,
  });
  await createQueue(page, {
    name: uniqueQueueName('beta', testInfo),
    extension,
  });

  await expect(
    page.getByText(`Queue with extension ${extension} already exists`),
  ).toBeVisible();
});

test('Queues page, add queue with invalid input', async ({
  page,
}, testInfo) => {
  await createQueue(page, {
    name: `Q${testInfo.parallelIndex}`,
    extension: '4',
  });
  await expect(
    page.getByText('extension: must be between 2 and 5 digits'),
  ).toBeVisible();
});

test('Queues page, update queue successfully', async ({ page }, testInfo) => {
  const queueName = uniqueQueueName('upq', testInfo);
  const updatedName = uniqueQueueName('sales', testInfo);
  const updatedExtension = uniqueExtension(testInfo, 4);

  await createQueue(page, {
    name: queueName,
    extension: uniqueExtension(testInfo, 3),
  });
  await openQueueEdit(page, queueName);
  await fillQueueForm(page, { name: updatedName, extension: updatedExtension });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(page).toHaveURL('/app/acme/queues');
  await expect(
    page.getByRole('rowheader', { name: updatedName, exact: true }),
  ).toBeVisible();
  await expect(queueRow(page, updatedName)).toContainText(updatedExtension);
});

test('Queue edit page, add member successfully', async ({ page }, testInfo) => {
  const slug = uniqueSlug(testInfo);
  const email = `queue.member+${slug}@example.com`;
  const name = `Queue Member ${slug}`;
  const username = `queuemember${slug}`.slice(0, 20);
  const queueName = uniqueQueueName('memberq', testInfo);
  const extension = uniqueExtension(testInfo, 5);

  await seedOrgMemberForQueue(email, name, username);
  await createQueue(page, { name: queueName, extension });

  await expect(page).toHaveURL(new RegExp('/app/acme/queues/.+/edit$'));
  await page.locator('#queue-member-search').fill(name.slice(0, 8));
  await expect(
    page.getByRole('button', { name: /Add to queue/i }),
  ).toBeVisible();
  await page.getByRole('button', { name: /Add to queue/i }).click();

  const assignedSection = page
    .locator('section')
    .filter({ hasText: 'Assigned members' })
    .first();
  await expect(assignedSection.getByText(name)).toBeVisible();
  await expect(assignedSection.getByText(username)).toBeVisible();
});

test('Queue edit page, remove member successfully', async ({
  page,
}, testInfo) => {
  const slug = uniqueSlug(testInfo);
  const email = `queue.remove+${slug}@example.com`;
  const name = `Queue Remove ${slug}`;
  const username = `queueremove${slug}`.slice(0, 20);
  const queueName = uniqueQueueName('removeq', testInfo);
  const extension = uniqueExtension(testInfo, 51);

  await seedOrgMemberForQueue(email, name, username);
  await createQueue(page, { name: queueName, extension });

  await expect(page).toHaveURL(new RegExp('/app/acme/queues/.+/edit$'));
  await page.locator('#queue-member-search').fill(name.slice(0, 8));
  await expect(
    page.getByRole('button', { name: /Add to queue/i }),
  ).toBeVisible();
  await page.getByRole('button', { name: /Add to queue/i }).click();

  const assignedSection = page
    .locator('section')
    .filter({ hasText: 'Assigned members' })
    .first();
  await expect(assignedSection.getByText(name)).toBeVisible();
  await expect(assignedSection.getByText(username)).toBeVisible();

  await assignedSection.getByRole('button', { name: 'Remove' }).click();
  await expect(page.getByText(`${name} removed from the queue`)).toBeVisible();

  await expect(assignedSection.getByText(name)).toHaveCount(0);
  await expect(assignedSection.getByText(username)).toHaveCount(0);
  await expect(
    assignedSection.getByText('No members are assigned to this queue yet.'),
  ).toBeVisible();
});

test('Queues page, update queue with invalid input', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('invalidq', testInfo);
  await createQueue(page, {
    name: queueName,
    extension: uniqueExtension(testInfo, 6),
  });

  await openQueueEdit(page, queueName);
  await fillQueueForm(page, { name: 'U', extension: '500' });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(
    page.getByText('name: must be at least 3 characters long'),
  ).toBeVisible();
});

test('Queues page, delete queue successfully', async ({ page }, testInfo) => {
  const queueName = uniqueQueueName('delqueue', testInfo);
  const extension = uniqueExtension(testInfo, 7);

  await createQueue(page, { name: queueName, extension });
  await expect(page).toHaveURL(new RegExp('/app/acme/queues/.+/edit$'));
  await gotoQueuesPage(page);

  const row = queueRow(page, queueName);
  await expect(row).toHaveCount(1);
  await openDeleteDialog(row);
  await page.getByRole('button', { name: 'No, cancel' }).click();
  await expect(row).toHaveCount(1);

  await openDeleteDialog(row);
  await page.locator('button').filter({ hasText: 'Close modal' }).click();
  await expect(row).toHaveCount(1);

  await openDeleteDialog(row);
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();
  await expect(row).toHaveCount(0);
});

test('Queues page, deleting queue present in numbers should fail', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('numqueue', testInfo);
  const phoneNumber =
    `+1${uniqueExtension(testInfo, 81).padEnd(10, '4')}`.slice(0, 12);

  await createQueueInDb({
    subdomain: 'acme',
    name: queueName,
    extension: uniqueExtension(testInfo, 8),
  });
  await seedNumberWithQueue({
    subdomain: 'acme',
    queueName,
    numberName: `QueueNumber${uniqueSlug(testInfo).slice(0, 4)}`,
    phoneNumber,
  });

  await gotoQueuesPage(page);
  const row = queueRow(page, queueName);
  await openDeleteDialog(row);
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();

  await expect(
    page.getByText(
      `Cannot delete ${queueName} as it is used in inbound flow graph in numbers: ${phoneNumber}`,
    ),
  ).toBeVisible({ timeout: 10000 });
  await expect(row).toHaveCount(1);
});

test('Queues page, deleting queue present in voicebots should fail', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('vbqueue', testInfo);
  const voiceBotName = uniqueQueueName('voicebot', testInfo);

  await createQueueInDb({
    subdomain: 'acme',
    name: queueName,
    extension: uniqueExtension(testInfo, 9),
  });
  await seedVoiceBotWithQueue({
    subdomain: 'acme',
    queueName,
    voiceBotName,
  });

  await gotoQueuesPage(page);
  const row = queueRow(page, queueName);
  await openDeleteDialog(row);
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();

  await expect(
    page.getByText(
      `Cannot delete ${queueName} as it is used in voice bots: ${voiceBotName}`,
    ),
  ).toBeVisible();
  await expect(row).toHaveCount(1);
});

test('Queues page, add queue without extension successfully', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('noext', testInfo);

  await createQueue(page, { name: queueName });
  await expect(
    page.getByText('Queue created successfully for org acme'),
  ).toBeVisible();
});

test('Queues page, update queue without extension successfully', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('taxbase', testInfo);
  const nextName = uniqueQueueName('tax', testInfo);

  await createQueue(page, { name: queueName });
  await openQueueEdit(page, queueName);
  await fillQueueForm(page, { name: nextName, extension: '' });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(page).toHaveURL('/app/acme/queues');
  await expect(queueRow(page, nextName)).toHaveCount(1);
});

test('Queues page, update queue with existing name should fail', async ({
  page,
}, testInfo) => {
  const firstQueueName = uniqueQueueName('firstq', testInfo);
  const secondQueueName = uniqueQueueName('secondq', testInfo);

  await createQueue(page, {
    name: firstQueueName,
    extension: uniqueExtension(testInfo, 10),
  });
  await createQueue(page, {
    name: secondQueueName,
    extension: uniqueExtension(testInfo, 11),
  });

  await openQueueEdit(page, secondQueueName);
  await fillQueueForm(page, {
    name: firstQueueName,
    extension: uniqueExtension(testInfo, 12),
  });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(
    page.getByText(`Queue with name ${firstQueueName} already exists`),
  ).toBeVisible();
});

test('Queues page, update queue with existing extension should fail', async ({
  page,
}, testInfo) => {
  const sharedExtension = uniqueExtension(testInfo, 13);
  const firstQueueName = uniqueQueueName('firstext', testInfo);
  const secondQueueName = uniqueQueueName('secondext', testInfo);

  await createQueue(page, { name: firstQueueName, extension: sharedExtension });
  await createQueue(page, {
    name: secondQueueName,
    extension: uniqueExtension(testInfo, 14),
  });

  await openQueueEdit(page, secondQueueName);
  await fillQueueForm(page, {
    name: uniqueQueueName('marketing', testInfo),
    extension: sharedExtension,
  });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(
    page.getByText(`Queue with extension ${sharedExtension} already exists`),
  ).toBeVisible();
});

test('Queues page, add queue in another organisation with the existing name and extension', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('sharedorg', testInfo);
  const extension = uniqueExtension(testInfo, 15);

  await createQueue(page, { name: queueName, extension }, 'acme');
  await createQueue(page, { name: queueName, extension }, 'heartcoders');

  await expect(
    page.getByText('Queue created successfully for org heartcoders'),
  ).toBeVisible();
});

test('Queues page, update queue in another organisation with the existing name and extension', async ({
  page,
}, testInfo) => {
  const queueName = uniqueQueueName('sharedupd', testInfo);
  const extension = uniqueExtension(testInfo, 16);
  const targetName = uniqueQueueName('updated', testInfo);
  const targetExtension = uniqueExtension(testInfo, 17);

  await createQueue(page, { name: queueName, extension }, 'acme');
  await createQueue(page, { name: queueName, extension }, 'heartcoders');

  await openQueueEdit(page, queueName, 'heartcoders');
  await fillQueueForm(page, { name: targetName, extension: targetExtension });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(page).toHaveURL('/app/heartcoders/queues');
  await expect(queueRow(page, targetName)).toHaveCount(1);
});
