import { test, expect, type Page, type TestInfo } from '@playwright/test';
import { Client } from 'pg';
import { v4 as uuid } from 'uuid';

type TestOrg = {
  id: string;
  name: string;
  subdomain: string;
  queues: Array<{ id: string; name: string }>;
  sipTrunks: Array<{ id: string; name: string }>;
};

type SeededVoiceBot = {
  id: string;
  name: string;
  instructions: string;
  notToDoInstructions: string;
  greetingInstructions: string;
  mcpServers: Array<{ url: string; token: string }>;
  isHangup: boolean;
  isEnqueue: boolean;
  queues: string[];
  pipeline: 'DEEPGRAM_AND_OPENAI' | 'REALTIME_API';
  apiKey?: string;
};

const DEFAULT_MCP_SERVER = {
  url: 'http://server:4000/mcp',
  token: 'abcdefghijk',
};

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

function uniquePhone(testInfo: TestInfo, suffix: number) {
  const tail = `${Date.now()}${testInfo.parallelIndex}${suffix}`
    .replace(/[^0-9]/g, '')
    .slice(-10)
    .padStart(10, '0');
  return `+1${tail}`;
}

async function createVoiceBotOrg(testInfo: TestInfo, queueNames: string[] = []): Promise<TestOrg> {
  const client = createClient();
  await client.connect();

  const slug = uniqueSlug(testInfo);
  const org: TestOrg = {
    id: uuid(),
    name: `Voice Bots ${slug}`,
    subdomain: `vb-${slug}`.slice(0, 40),
    queues: queueNames.map((name) => ({ id: uuid(), name })),
    sipTrunks: [{ id: uuid(), name: `VoiceBot Trunk ${slug}` }],
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
        VALUES ($1, $2, 'ADMIN', $3, 'ytgJ6sp9xcvofYT8UlKlr', '101', 'Logged Out')
      `,
      [adminId, org.id, `owner_${slug}`.slice(0, 20)],
    );

    for (const queue of org.queues) {
      await client.query(
        `
          INSERT INTO queues
            (id, name, extension, org_id, created_at, updated_at, max_no_answers, wrap_up_time, reject_delay_time)
          VALUES
            ($1, $2, NULL, $3, NOW(), NOW(), 2, 30, 30)
        `,
        [queue.id, queue.name, org.id],
      );
    }

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
          VALUES ($1, $2, $3, 'tester', 'secret', 'sip.example.com', $4::text[], NOW(), NOW())
        `,
        [trunk.id, org.id, trunk.name, ['127.0.0.1']],
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

async function seedVoiceBot(org: TestOrg, voiceBot: SeededVoiceBot) {
  const client = createClient();
  await client.connect();

  try {
    await client.query(
      `
        INSERT INTO voice_bots
          (id, org_id, name, instructions, not_to_do_instructions, greeting_instructions, mcp_servers, api_key, is_hangup, is_enqueue, queues, pipeline)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12)
      `,
      [
        voiceBot.id,
        org.id,
        voiceBot.name,
        voiceBot.instructions,
        voiceBot.notToDoInstructions,
        voiceBot.greetingInstructions,
        JSON.stringify(voiceBot.mcpServers),
        voiceBot.apiKey ?? `api_${voiceBot.id.replace(/-/g, '')}`,
        voiceBot.isHangup,
        voiceBot.isEnqueue,
        voiceBot.queues,
        voiceBot.pipeline,
      ],
    );
  } finally {
    await client.end();
  }
}

async function seedNumberWithVoiceBot(org: TestOrg, voiceBot: SeededVoiceBot, name: string, number: string) {
  const client = createClient();
  await client.connect();

  const nodeId = uuid();
  const inboundFlowGraph = {
    start: nodeId,
    nodes: {
      [nodeId]: {
        id: nodeId,
        type: 'VoiceBot',
        data: {
          voiceBotId: voiceBot.id,
          voiceBotName: voiceBot.name,
        },
      },
    },
  };

  try {
    await client.query(
      `
        INSERT INTO numbers
          (id, name, number, allow_outbound_regex, is_default_outbound_number, inbound_flow_graph, org_id, sip_trunk_id, created_at, updated_at)
        VALUES
          ($1, $2, $3, '', false, $4::jsonb, $5, $6, NOW(), NOW())
      `,
      [uuid(), name, number, JSON.stringify(inboundFlowGraph), org.id, org.sipTrunks[0].id],
    );
  } finally {
    await client.end();
  }
}

function voiceBotsPath(subdomain: string) {
  return `/app/${subdomain}/voice-bots`;
}

async function gotoVoiceBotsPage(page: Page, subdomain: string) {
  await page.goto(voiceBotsPath(subdomain));
  await expect(page.getByRole('heading', { name: 'Voice Bots' })).toBeVisible();
}

async function gotoCreateVoiceBotPage(page: Page, subdomain: string) {
  await gotoVoiceBotsPage(page, subdomain);
  await page.getByRole('link', { name: 'Create' }).click();
  await expect(page.getByRole('heading', { name: 'Create Voice Bot' })).toBeVisible();
}

type VoiceBotFormInput = {
  name: string;
  instructions: string;
  notToDoInstructions: string;
  greetingInstructions: string;
  mcpServer?: { url: string; token: string };
  isHangup?: boolean;
  isEnqueue?: boolean;
  queueName?: string;
  pipeline?: 'DEEPGRAM_AND_OPENAI' | 'REALTIME_API';
};

async function fillVoiceBotForm(page: Page, input: VoiceBotFormInput) {
  await page.getByPlaceholder('Voice Bot Name').fill(input.name);
  await page.getByPlaceholder('Write your instructions here').fill(input.instructions);
  await page
    .getByPlaceholder('If conversation is not related to voice-bot name, then reply that you can\'t respond. If unrelated question is asked more than three times then hang up.')
    .fill(input.notToDoInstructions);
  await page
    .getByPlaceholder('Greet with appropriate greeting for EST timezone and explicitly mention that you are on recorded line')
    .fill(input.greetingInstructions);

  if (input.pipeline) {
    await page.locator('#pipeline').selectOption(input.pipeline);
  }

  const mcpServer = input.mcpServer ?? DEFAULT_MCP_SERVER;
  const urlInputs = page.locator('input[placeholder="MCP Server URL"]');
  if ((await urlInputs.count()) === 0) {
    await page.getByRole('button', { name: /Add MCP Server/i }).click();
  }
  await page.locator('input[placeholder="MCP Server URL"]').first().fill(mcpServer.url);
  await page.locator('input[placeholder="Authorization Token"]').first().fill(mcpServer.token);

  if (input.isHangup !== undefined) {
    const hangup = page.getByLabel('hangup (Description: used to hang up the call)');
    if (input.isHangup) {
      await hangup.check();
    } else {
      await hangup.uncheck();
    }
  }

  if (input.isEnqueue !== undefined) {
    const enqueue = page.getByLabel('enqueue (Description: used to transfer to queue specified in params)');
    if (input.isEnqueue) {
      await enqueue.check();
      if (input.queueName) {
        if ((await page.locator('select#queueName').count()) === 0) {
          await page.getByRole('button', { name: 'Add Queue' }).click();
        }
        const queueSelect = page.locator('select#queueName').first();
        await expect(async () => {
          const options = await queueSelect.locator('option').allTextContents();
          expect(options).toContain(input.queueName!);
        }).toPass({ timeout: 10000 });
        await queueSelect.selectOption({ label: input.queueName });
      }
    } else {
      await enqueue.uncheck();
    }
  }
}

async function openVoiceBotEditPage(page: Page, subdomain: string, voiceBotName: string) {
  await gotoVoiceBotsPage(page, subdomain);
  const row = page.locator('tbody tr').filter({ hasText: voiceBotName }).first();
  await expect(row).toBeVisible();
  await row.getByRole('link', { name: 'Edit' }).click();
  await expect(page.getByRole('heading', { name: 'Voice Bots Edit' })).toBeVisible();
}

function voiceBotRow(page: Page, name: string) {
  return page.locator('tbody tr').filter({ hasText: name }).first();
}

function validationError(page: Page) {
  return page.locator('text=/should be at least|error|invalid/i').first();
}

test('Voice Bot page, add voice-bot successfully', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo, ['sales_queue', 'service_queue']);
  const name = `car dealer ${uniqueSlug(testInfo)}`;

  await gotoCreateVoiceBotPage(page, org.subdomain);
  await fillVoiceBotForm(page, {
    name,
    instructions:
      'You are a helpful assistant that helps customers search for cars and book appointments.',
    notToDoInstructions:
      'If the caller asks unrelated questions more than three times, politely refuse and hang up.',
    greetingInstructions: 'Greet callers appropriately for EST timezone and mention the line is recorded.',
    isHangup: true,
    isEnqueue: true,
    queueName: org.queues[0].name,
  });
  await page.getByRole('button', { name: 'Create' }).click();

  await expect(page).toHaveURL(voiceBotsPath(org.subdomain));
  await expect(voiceBotRow(page, name)).toBeVisible();

  await openVoiceBotEditPage(page, org.subdomain, name);
  await expect(page.getByPlaceholder('Voice Bot Name')).toHaveValue(name);
  await expect(page.getByPlaceholder('Write your instructions here')).toHaveValue(
    'You are a helpful assistant that helps customers search for cars and book appointments.',
  );
  await expect(
    page.getByPlaceholder('If conversation is not related to voice-bot name, then reply that you can\'t respond. If unrelated question is asked more than three times then hang up.'),
  ).toHaveValue(
    'If the caller asks unrelated questions more than three times, politely refuse and hang up.',
  );
  await expect(
    page.getByPlaceholder('Greet with appropriate greeting for EST timezone and explicitly mention that you are on recorded line'),
  ).toHaveValue('Greet callers appropriately for EST timezone and mention the line is recorded.');
  await expect(page.getByLabel('hangup (Description: used to hang up the call)')).toBeChecked();
  await expect(page.getByLabel('enqueue (Description: used to transfer to queue specified in params)')).toBeChecked();
  await expect(page.locator('select#queueName').first()).toHaveValue(org.queues[0].name);
});

test('Voice Bot page, add voice-bot with invalid input', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo, ['sales_queue']);

  await gotoCreateVoiceBotPage(page, org.subdomain);
  await fillVoiceBotForm(page, {
    name: 'om',
    instructions: 'Yo',
    notToDoInstructions: 'If',
    greetingInstructions: 'gr',
    isHangup: true,
    isEnqueue: true,
    queueName: org.queues[0].name,
  });
  await page.getByRole('button', { name: 'Create' }).click();

  await expect(validationError(page)).toBeVisible();
  await expect(page).toHaveURL(new RegExp(`/app/${org.subdomain}/voice-bots/create$`));
});

test('Voice Bot page, update voice-bot successfully', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo, ['sales_queue', 'service_queue']);
  const voiceBot: SeededVoiceBot = {
    id: uuid(),
    name: `car dealer ${uniqueSlug(testInfo)}`,
    instructions: 'search the car and book appointment',
    notToDoInstructions: 'Only help with searching cars and booking appointments.',
    greetingInstructions: 'Greet customers with good messages according to EST timezone.',
    mcpServers: [DEFAULT_MCP_SERVER],
    isHangup: true,
    isEnqueue: true,
    queues: [org.queues[0].name],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  };
  await seedVoiceBot(org, voiceBot);

  await openVoiceBotEditPage(page, org.subdomain, voiceBot.name);
  await fillVoiceBotForm(page, {
    name: `${voiceBot.name} updated`,
    instructions: 'search the cars and book appointment with specific date',
    notToDoInstructions: 'Only help with car search and appointment booking for a specific date.',
    greetingInstructions: 'Greet customers with the best EST-friendly welcome message.',
    mcpServer: { url: 'http://server:4000/mcp', token: 'abcdefghijklm' },
    isHangup: true,
    isEnqueue: true,
    queueName: org.queues[1].name,
  });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(page).toHaveURL(voiceBotsPath(org.subdomain));
  await expect(voiceBotRow(page, `${voiceBot.name} updated`)).toBeVisible();

  await openVoiceBotEditPage(page, org.subdomain, `${voiceBot.name} updated`);
  await expect(page.getByPlaceholder('Voice Bot Name')).toHaveValue(`${voiceBot.name} updated`);
  await expect(page.locator('input[placeholder="Authorization Token"]').first()).toHaveValue('abcdefghijklm');
  await expect(page.locator('select#queueName').first()).toHaveValue(org.queues[1].name);
});

test('Voice Bot page, update voice-bot with invalid input', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo, ['sales_queue']);
  const voiceBot: SeededVoiceBot = {
    id: uuid(),
    name: `dealer ${uniqueSlug(testInfo)}`,
    instructions: 'help callers search for cars',
    notToDoInstructions: 'Do not answer unrelated questions.',
    greetingInstructions: 'Welcome callers politely.',
    mcpServers: [DEFAULT_MCP_SERVER],
    isHangup: true,
    isEnqueue: true,
    queues: [org.queues[0].name],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  };
  await seedVoiceBot(org, voiceBot);

  await openVoiceBotEditPage(page, org.subdomain, voiceBot.name);
  await fillVoiceBotForm(page, {
    name: 'ca',
    instructions: 'se',
    notToDoInstructions: 'do',
    greetingInstructions: 'gr',
    mcpServer: DEFAULT_MCP_SERVER,
    isHangup: true,
    isEnqueue: true,
    queueName: org.queues[0].name,
  });
  await page.getByRole('button', { name: 'Update' }).click();

  await expect(validationError(page)).toBeVisible();
});

test('Voice Bot page, delete the voice-bot successfully', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo);
  const voiceBot: SeededVoiceBot = {
    id: uuid(),
    name: `delete me ${uniqueSlug(testInfo)}`,
    instructions: 'help callers search for cars',
    notToDoInstructions: 'Do not answer unrelated questions.',
    greetingInstructions: 'Welcome callers politely.',
    mcpServers: [DEFAULT_MCP_SERVER],
    isHangup: true,
    isEnqueue: false,
    queues: [],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  };
  await seedVoiceBot(org, voiceBot);

  await gotoVoiceBotsPage(page, org.subdomain);
  const row = voiceBotRow(page, voiceBot.name);
  await expect(row).toBeVisible();

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.getByRole('button', { name: 'No, cancel' }).click();
  await expect(row).toHaveCount(1);

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.locator('button[data-modal-hide="popup-modal"]').click();
  await expect(row).toHaveCount(1);

  await row.getByRole('button', { name: 'Delete' }).click();
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();
  await expect(row).toHaveCount(0);
});

test('Voice Bot page, deleting voice-bot present in numbers inbound flow graph should fail', async ({ page }, testInfo) => {
  const org = await createVoiceBotOrg(testInfo);
  const protectedNumber = uniquePhone(testInfo, 72);
  const voiceBot: SeededVoiceBot = {
    id: uuid(),
    name: `protected bot ${uniqueSlug(testInfo)}`,
    instructions: 'help callers search for cars',
    notToDoInstructions: 'Do not answer unrelated questions.',
    greetingInstructions: 'Welcome callers politely.',
    mcpServers: [DEFAULT_MCP_SERVER],
    isHangup: true,
    isEnqueue: false,
    queues: [],
    pipeline: 'DEEPGRAM_AND_OPENAI',
  };
  await seedVoiceBot(org, voiceBot);
  await seedNumberWithVoiceBot(org, voiceBot, 'Protected Number', protectedNumber);

  await gotoVoiceBotsPage(page, org.subdomain);
  const row = voiceBotRow(page, voiceBot.name);
  await expect(row).toBeVisible();
  await row.getByRole('button', { name: 'Delete' }).click();
  await page.getByRole('button', { name: "Yes, I'm sure" }).click();

  await expect(
    page.getByText(
      new RegExp(`Cannot delete ${voiceBot.name} as it is used in inbound flow graph in numbers ${protectedNumber.replace('+', '\\+')}`, 'i'),
    ),
  ).toBeVisible();
  await expect(row).toHaveCount(1);
});
