import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { Client } from 'pg';
import { v4 as uuid } from 'uuid';

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

const composeArgs = [
  'compose',
  '-f',
  'docker-compose-e2e.yaml',
  '--env-file',
  '.env.e2e',
  '-p',
  'comcent-e2e',
];

const SBC_ADMIN_SERVICE = process.env.E2E_SBC_ADMIN_SERVICE || 'sbc';

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

async function deleteKamailioCacheKey(table: string, key: string) {
  await execFileAsync(
    'docker',
    [
      ...composeArgs,
      'exec',
      '-T',
      SBC_ADMIN_SERVICE,
      'kamcmd',
      'htable.delete',
      table,
      key,
    ],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  ).catch(() => undefined);
}

function buildDialGraph(target: string) {
  const nodeId = 'dial-node-1';

  return {
    start: nodeId,
    nodes: {
      [nodeId]: {
        id: nodeId,
        type: 'Dial',
        data: {
          to: target,
          shouldSpoof: false,
          timeout: 20,
        },
        outlets: {},
        screen: {
          tx: 0,
          ty: 0,
        },
      },
    },
  };
}

function buildQueueGraph(queueName: string) {
  const nodeId = 'queue-node-1';

  return {
    start: nodeId,
    nodes: {
      [nodeId]: {
        id: nodeId,
        type: 'Queue',
        data: {
          queue: queueName,
        },
        screen: {
          tx: 0,
          ty: 0,
        },
      },
    },
  };
}

function buildDialGroupGraph(
  targets: string[],
  options?: { timeout?: number; timeoutFallbackTarget?: string },
) {
  const nodeId = 'dial-group-node-1';
  const fallbackId = 'dial-group-timeout-fallback-node-1';
  const timeout = options?.timeout ?? 20;

  const nodes: Record<string, unknown> = {
    [nodeId]: {
      id: nodeId,
      type: 'DialGroup',
      data: {
        to: targets,
        shouldSpoof: false,
        timeout,
      },
      outlets: options?.timeoutFallbackTarget ? { timeout: fallbackId } : {},
      screen: { tx: 0, ty: 0 },
    },
  };

  if (options?.timeoutFallbackTarget) {
    nodes[fallbackId] = {
      id: fallbackId,
      type: 'Dial',
      data: {
        to: options.timeoutFallbackTarget,
        shouldSpoof: false,
      },
      outlets: {},
      screen: { tx: 200, ty: 0 },
    };
  }

  return { start: nodeId, nodes };
}

function buildMenuDialGraph(params: {
  selectedDigit: string;
  target: string;
  fallbackTarget?: string;
}) {
  const menuNodeId = 'menu-node-1';
  const selectedDialNodeId = 'dial-menu-selected-node-1';
  const fallbackDialNodeId = 'dial-menu-fallback-node-1';

  return {
    start: menuNodeId,
    nodes: {
      [menuNodeId]: {
        id: menuNodeId,
        type: 'Menu',
        data: {
          promptAudio: 'silence_stream://1000',
          errorAudio: 'silence_stream://250',
          repeat: 1,
          afterPromptWaitTime: 2,
          multiDigitWaitTime: 2,
        },
        outlets: {
          [params.selectedDigit]: selectedDialNodeId,
          ...(params.fallbackTarget ? { 9: fallbackDialNodeId } : {}),
        },
        screen: {
          tx: 0,
          ty: 0,
        },
      },
      [selectedDialNodeId]: {
        id: selectedDialNodeId,
        type: 'Dial',
        data: {
          to: params.target,
          shouldSpoof: false,
          timeout: 20,
        },
        outlets: {},
        screen: {
          tx: 40,
          ty: 40,
        },
      },
      ...(params.fallbackTarget
        ? {
            [fallbackDialNodeId]: {
              id: fallbackDialNodeId,
              type: 'Dial',
              data: {
                to: params.fallbackTarget,
                shouldSpoof: false,
                timeout: 20,
              },
              outlets: {},
              screen: {
                tx: 80,
                ty: 80,
              },
            },
          }
        : {}),
    },
  };
}

function buildVoiceBotGraph(voiceBotId: string) {
  const nodeId = 'voice-bot-node-1';

  return {
    start: nodeId,
    nodes: {
      [nodeId]: {
        id: nodeId,
        type: 'VoiceBot',
        data: {
          voice_bot_id: voiceBotId,
        },
        screen: {
          tx: 0,
          ty: 0,
        },
      },
    },
  };
}

function buildWeekTimeDialGraph(params: {
  timezone: string;
  day: 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun';
  trueTarget: string;
  falseTarget: string;
}) {
  const weekTimeNodeId = 'weektime-node-1';
  const trueDialNodeId = 'dial-true-node-1';
  const falseDialNodeId = 'dial-false-node-1';

  const blankDay = {
    include: false,
    timeSlots: [
      {
        from: '09:00',
        to: '17:00',
      },
    ],
  };

  const days = {
    mon: { ...blankDay },
    tue: { ...blankDay },
    wed: { ...blankDay },
    thu: { ...blankDay },
    fri: { ...blankDay },
    sat: { ...blankDay },
    sun: { ...blankDay },
  };

  days[params.day] = {
    include: true,
    timeSlots: [
      {
        from: '00:00',
        to: '23:59',
      },
    ],
  };

  return {
    start: weekTimeNodeId,
    nodes: {
      [weekTimeNodeId]: {
        id: weekTimeNodeId,
        type: 'WeekTime',
        data: {
          timezone: params.timezone,
          ...days,
        },
        outlets: {
          true: trueDialNodeId,
          false: falseDialNodeId,
        },
        screen: {
          tx: 0,
          ty: 0,
        },
      },
      [trueDialNodeId]: {
        id: trueDialNodeId,
        type: 'Dial',
        data: {
          to: params.trueTarget,
          shouldSpoof: false,
          timeout: 20,
        },
        outlets: {},
        screen: {
          tx: 40,
          ty: 40,
        },
      },
      [falseDialNodeId]: {
        id: falseDialNodeId,
        type: 'Dial',
        data: {
          to: params.falseTarget,
          shouldSpoof: false,
          timeout: 20,
        },
        outlets: {},
        screen: {
          tx: 80,
          ty: 80,
        },
      },
    },
  };
}

export async function setNumberInboundFlowToDial(
  number: string,
  target: string,
) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildDialGraph(target);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function setNumberInboundFlowToQueue(
  number: string,
  queueName: string,
) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildQueueGraph(queueName);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function setNumberInboundFlowToWeekTimeDial(params: {
  number: string;
  timezone: string;
  day: 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun';
  trueTarget: string;
  falseTarget: string;
}) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildWeekTimeDialGraph(params);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [params.number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function setNumberInboundFlowToDialGroup(
  number: string,
  targets: string[],
  options?: { timeout?: number; timeoutFallbackTarget?: string },
) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildDialGroupGraph(targets, options);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function setNumberInboundFlowToMenuDial(params: {
  number: string;
  selectedDigit: string;
  target: string;
  fallbackTarget?: string;
}) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildMenuDialGraph(params);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [params.number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function setNumberInboundFlowToVoiceBot(
  number: string,
  voiceBotId: string,
) {
  const client = createClient();
  await client.connect();

  try {
    const graph = buildVoiceBotGraph(voiceBotId);

    await client.query(
      `
        UPDATE numbers
        SET inbound_flow_graph = $2::jsonb,
            updated_at = NOW()
        WHERE number = $1
      `,
      [number, JSON.stringify(graph)],
    );
  } finally {
    await client.end();
  }
}

export async function ensureDefaultOutboundRoute(params: {
  subdomain: string;
  number: string;
  sipTrunkName: string;
  outboundContact: string;
  outboundUsername?: string;
  outboundPassword?: string;
  inboundIps?: string[];
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

    const existingSipTrunk = await client.query<{ id: string }>(
      `
        SELECT id
        FROM sip_trunks
        WHERE org_id = $1
          AND name = $2
        LIMIT 1
      `,
      [orgId, params.sipTrunkName],
    );

    const sipTrunkId = existingSipTrunk.rows[0]?.id ?? uuid();

    if (existingSipTrunk.rows[0]) {
      await client.query(
        `
          UPDATE sip_trunks
          SET outbound_username = $2,
              outbound_password = $3,
              outbound_contact = $4,
              inbound_ips = $5::text[],
              updated_at = NOW()
          WHERE id = $1
        `,
        [
          sipTrunkId,
          params.outboundUsername ?? null,
          params.outboundPassword ?? null,
          params.outboundContact,
          params.inboundIps ?? ['172.29.0.0/16'],
        ],
      );
    } else {
      await client.query(
        `
          INSERT INTO sip_trunks
            (id, org_id, name, outbound_username, outbound_password, outbound_contact, inbound_ips, created_at, updated_at)
          VALUES
            ($1, $2, $3, $4, $5, $6, $7::text[], NOW(), NOW())
        `,
        [
          sipTrunkId,
          orgId,
          params.sipTrunkName,
          params.outboundUsername ?? null,
          params.outboundPassword ?? null,
          params.outboundContact,
          params.inboundIps ?? ['172.29.0.0/16'],
        ],
      );
    }

    if (!sipTrunkId) {
      throw new Error(
        `Failed to create or update SIP trunk ${params.sipTrunkName}`,
      );
    }

    await client.query(
      `
        UPDATE numbers
        SET sip_trunk_id = $2,
            is_default_outbound_number = true,
            updated_at = NOW()
        WHERE org_id = $1
          AND number = $3
      `,
      [orgId, sipTrunkId, params.number],
    );
  } finally {
    await client.end();
  }

  await deleteKamailioCacheKey('cache', `trunk_${params.number}`);
}

export async function ensureMemberInOrg(params: {
  subdomain: string;
  email: string;
  name: string;
  username: string;
  sipPassword: string;
  presence?: string;
}) {
  const client = createClient();
  await client.connect();
  let result: { orgId: string; userId: string } | undefined;

  try {
    const orgResult = await client.query<{ id: string }>(
      'SELECT id FROM orgs WHERE subdomain = $1',
      [params.subdomain],
    );

    const orgId = orgResult.rows[0]?.id;
    if (!orgId) {
      throw new Error(`Org ${params.subdomain} not found`);
    }

    const userResult = await client.query<{ id: string }>(
      'SELECT id FROM users WHERE email = $1',
      [params.email],
    );

    const userId = userResult.rows[0]?.id ?? uuid();

    if (!userResult.rows[0]) {
      await client.query(
        `
          INSERT INTO users (id, name, email, created_at, updated_at)
          VALUES ($1, $2, $3, NOW(), NOW())
        `,
        [userId, params.name, params.email],
      );
    }

    await client.query(
      `
        INSERT INTO org_members
          (user_id, org_id, role, username, sip_password, presence)
        VALUES
          ($1, $2, 'MEMBER', $3, $4, $5)
        ON CONFLICT (org_id, user_id)
        DO UPDATE SET
          username = EXCLUDED.username,
          sip_password = EXCLUDED.sip_password,
          presence = EXCLUDED.presence
      `,
      [
        userId,
        orgId,
        params.username,
        params.sipPassword,
        params.presence ?? 'Available',
      ],
    );

    result = { orgId, userId };
  } finally {
    await client.end();
  }

  await deleteKamailioCacheKey(
    'cache',
    `user_${params.username}@${params.subdomain}.comcent.io`,
  );

  if (!result) {
    throw new Error(
      `Failed to ensure member ${params.email} in org ${params.subdomain}`,
    );
  }

  return result;
}

export async function getMemberPresence(params: {
  subdomain: string;
  username: string;
}) {
  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{ presence: string | null }>(
      `
        SELECT om.presence
        FROM org_members om
        JOIN orgs o ON o.id = om.org_id
        WHERE o.subdomain = $1
          AND om.username = $2
        LIMIT 1
      `,
      [params.subdomain, params.username],
    );

    return result.rows[0]?.presence ?? null;
  } finally {
    await client.end();
  }
}

export async function waitForMemberPresence(params: {
  subdomain: string;
  username: string;
  presence: string;
  timeoutMs?: number;
  intervalMs?: number;
}) {
  const deadline = Date.now() + (params.timeoutMs ?? 60_000);
  const intervalMs = params.intervalMs ?? 1_000;
  let lastPresence: string | null = null;

  while (Date.now() < deadline) {
    lastPresence = await getMemberPresence({
      subdomain: params.subdomain,
      username: params.username,
    });

    if (lastPresence === params.presence) {
      return lastPresence;
    }

    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error(
    `Timed out waiting for ${params.username} presence ${params.presence}; last seen ${lastPresence ?? 'null'}`,
  );
}

export async function ensureQueue(params: {
  subdomain: string;
  name: string;
  extension?: string;
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

    const existing = await client.query<{ id: string }>(
      'SELECT id FROM queues WHERE org_id = $1 AND name = $2',
      [orgId, params.name],
    );

    const queueId = existing.rows[0]?.id ?? uuid();

    if (existing.rows[0]) {
      await client.query(
        `
          UPDATE queues
          SET extension = $3,
              updated_at = NOW()
          WHERE id = $1 AND org_id = $2
        `,
        [queueId, orgId, params.extension ?? null],
      );
    } else {
      await client.query(
        `
          INSERT INTO queues
            (id, name, extension, org_id, created_at, updated_at, max_no_answers, wrap_up_time, reject_delay_time)
          VALUES
            ($1, $2, $3, $4, NOW(), NOW(), 2, 30, 30)
        `,
        [queueId, params.name, params.extension ?? null, orgId],
      );
    }

    return { orgId, queueId };
  } finally {
    await client.end();
  }
}

export async function ensureUserAcceptedTerms(email: string) {
  const client = createClient();
  await client.connect();

  try {
    await client.query(
      `
        UPDATE users
        SET has_agreed_to_tos = true,
            agreed_to_tos_at = COALESCE(agreed_to_tos_at, NOW())
        WHERE email = $1
      `,
      [email],
    );
  } finally {
    await client.end();
  }
}

export async function ensureUserEmailVerified(email: string) {
  const client = createClient();
  await client.connect();

  try {
    await client.query(
      `
        UPDATE users
        SET is_email_verified = true
        WHERE email = $1
      `,
      [email],
    );
  } finally {
    await client.end();
  }
}

export async function ensureVoiceBot(params: {
  subdomain: string;
  name: string;
  instructions?: string;
  notToDoInstructions?: string;
  greetingInstructions?: string;
  pipeline?: string;
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

    const existing = await client.query<{ id: string }>(
      'SELECT id FROM voice_bots WHERE org_id = $1 AND name = $2 LIMIT 1',
      [orgId, params.name],
    );

    const voiceBotId = existing.rows[0]?.id ?? uuid();
    const commonValues = {
      name: params.name,
      instructions:
        params.instructions ?? 'Handle the inbound caller as a test voice bot.',
      notToDoInstructions:
        params.notToDoInstructions ?? 'Do not deviate from the test flow.',
      greetingInstructions:
        params.greetingInstructions ??
        'Greet the caller and continue the test.',
      mcpServers: '[]',
      apiKey: 'dummy-api-key',
      isHangup: false,
      isEnqueue: false,
      queues: '{}',
      pipeline: params.pipeline ?? 'default',
    };

    if (existing.rows[0]) {
      await client.query(
        `
          UPDATE voice_bots
          SET name = $3,
              instructions = $4,
              not_to_do_instructions = $5,
              greeting_instructions = $6,
              mcp_servers = $7::jsonb,
              api_key = $8,
              is_hangup = $9,
              is_enqueue = $10,
              queues = $11::text[],
              pipeline = $12
          WHERE id = $1
            AND org_id = $2
        `,
        [
          voiceBotId,
          orgId,
          commonValues.name,
          commonValues.instructions,
          commonValues.notToDoInstructions,
          commonValues.greetingInstructions,
          commonValues.mcpServers,
          commonValues.apiKey,
          commonValues.isHangup,
          commonValues.isEnqueue,
          commonValues.queues,
          commonValues.pipeline,
        ],
      );
    } else {
      await client.query(
        `
          INSERT INTO voice_bots
            (id, org_id, name, instructions, not_to_do_instructions, greeting_instructions, mcp_servers, api_key, is_hangup, is_enqueue, queues, pipeline)
          VALUES
            ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11::text[], $12)
        `,
        [
          voiceBotId,
          orgId,
          commonValues.name,
          commonValues.instructions,
          commonValues.notToDoInstructions,
          commonValues.greetingInstructions,
          commonValues.mcpServers,
          commonValues.apiKey,
          commonValues.isHangup,
          commonValues.isEnqueue,
          commonValues.queues,
          commonValues.pipeline,
        ],
      );
    }

    return { orgId, voiceBotId };
  } finally {
    await client.end();
  }
}

export async function ensureVoiceBotEndpoint(serviceName = 'sipp-uas') {
  const { stdout: containerId } = await execFileAsync(
    'docker',
    [...composeArgs, 'ps', '-q', serviceName],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  );

  const trimmedContainerId = containerId.trim();
  if (!trimmedContainerId) {
    throw new Error(`Unable to resolve container for ${serviceName}`);
  }

  const { stdout: ipAddress } = await execFileAsync(
    'docker',
    [
      'inspect',
      '-f',
      '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}',
      trimmedContainerId,
    ],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  );

  const trimmedIpAddress = ipAddress.trim();
  if (!trimmedIpAddress) {
    throw new Error(`Unable to resolve IP address for ${serviceName}`);
  }

  const { stdout: existingVoiceBotKeys } = await execFileAsync(
    'docker',
    [
      ...composeArgs,
      'exec',
      '-T',
      'redis',
      'redis-cli',
      '--raw',
      'KEYS',
      'voice.bot.ip.*',
    ],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  );

  const staleVoiceBotKeys = existingVoiceBotKeys
    .split('\n')
    .map((key) => key.trim())
    .filter(Boolean);

  if (staleVoiceBotKeys.length > 0) {
    await execFileAsync(
      'docker',
      [
        ...composeArgs,
        'exec',
        '-T',
        'redis',
        'redis-cli',
        'DEL',
        ...staleVoiceBotKeys,
      ],
      {
        cwd: repoRoot,
        timeout: 30_000,
        maxBuffer: 4 * 1024 * 1024,
      },
    );
  }

  await execFileAsync(
    'docker',
    [
      ...composeArgs,
      'exec',
      '-T',
      'redis',
      'redis-cli',
      'SET',
      `voice.bot.ip.${trimmedIpAddress}`,
      'ready',
    ],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  );

  await execFileAsync(
    'docker',
    [
      ...composeArgs,
      'exec',
      '-T',
      'redis',
      'redis-cli',
      'DEL',
      'voice.bot.last.used',
    ],
    {
      cwd: repoRoot,
      timeout: 30_000,
      maxBuffer: 4 * 1024 * 1024,
    },
  );

  return trimmedIpAddress;
}

export async function addMemberToQueue(params: {
  orgId: string;
  userId: string;
  queueId: string;
}) {
  const client = createClient();
  await client.connect();

  try {
    await client.query(
      `
        INSERT INTO queue_memberships
          (queue_id, org_id, user_id, created_at, updated_at)
        VALUES
          ($1, $2, $3, NOW(), NOW())
        ON CONFLICT DO NOTHING
      `,
      [params.queueId, params.orgId, params.userId],
    );
  } finally {
    await client.end();
  }
}

export async function waitForInboundCallStory(params: {
  caller: string;
  callee: string;
  timeoutMs?: number;
}) {
  return waitForCallStory({
    caller: params.caller,
    callee: params.callee,
    direction: 'inbound',
    timeoutMs: params.timeoutMs,
  });
}

export async function waitForInboundCallStoryObserved(params: {
  caller: string;
  callee: string;
  timeoutMs?: number;
}) {
  return waitForCallStoryObserved({
    caller: params.caller,
    callee: params.callee,
    direction: 'inbound',
    timeoutMs: params.timeoutMs,
  });
}

export async function waitForCallStory(params: {
  caller?: string;
  callee?: string;
  direction?: string;
  timeoutMs?: number;
}) {
  const client = createClient();
  await client.connect();

  const deadline = Date.now() + (params.timeoutMs ?? 45_000);

  try {
    while (Date.now() < deadline) {
      const result = await client.query<{
        id: string;
        caller: string;
        callee: string;
        direction: string;
        end_at: Date | null;
        spans: number;
      }>(
        `
          SELECT
            cs.id,
            cs.caller,
            cs.callee,
            cs.direction,
            cs.end_at,
            COUNT(sp.id)::int AS spans
          FROM call_stories cs
          LEFT JOIN call_spans sp ON sp.call_story_id = cs.id
          WHERE ($1::text IS NULL OR cs.caller = $1)
            AND ($2::text IS NULL OR cs.callee = $2)
            AND ($3::text IS NULL OR cs.direction = $3)
          GROUP BY cs.id, cs.caller, cs.callee, cs.direction, cs.end_at
          ORDER BY cs.start_at DESC
          LIMIT 1
        `,
        [
          params.caller ?? null,
          params.callee ?? null,
          params.direction ?? null,
        ],
      );

      const row = result.rows[0];
      if (row && row.spans > 0 && row.end_at) {
        return row;
      }

      await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    throw new Error(
      `Timed out waiting for call story caller=${params.caller} callee=${params.callee} direction=${params.direction}`,
    );
  } finally {
    await client.end();
  }
}

export async function waitForCallStoryObserved(params: {
  caller?: string;
  callee?: string;
  direction?: string;
  timeoutMs?: number;
}) {
  const client = createClient();
  await client.connect();

  const deadline = Date.now() + (params.timeoutMs ?? 45_000);

  try {
    while (Date.now() < deadline) {
      const result = await client.query<{
        id: string;
        caller: string;
        callee: string;
        direction: string;
        end_at: Date | null;
        spans: number;
      }>(
        `
          SELECT
            cs.id,
            cs.caller,
            cs.callee,
            cs.direction,
            cs.end_at,
            COUNT(sp.id)::int AS spans
          FROM call_stories cs
          LEFT JOIN call_spans sp ON sp.call_story_id = cs.id
          WHERE ($1::text IS NULL OR cs.caller = $1)
            AND ($2::text IS NULL OR cs.callee = $2)
            AND ($3::text IS NULL OR cs.direction = $3)
          GROUP BY cs.id, cs.caller, cs.callee, cs.direction, cs.end_at
          ORDER BY cs.start_at DESC
          LIMIT 1
        `,
        [
          params.caller ?? null,
          params.callee ?? null,
          params.direction ?? null,
        ],
      );

      const row = result.rows[0];
      if (row && row.spans > 0) {
        return row;
      }

      await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    throw new Error(
      `Timed out waiting for observed call story caller=${params.caller} callee=${params.callee} direction=${params.direction}`,
    );
  } finally {
    await client.end();
  }
}

export async function getCallStoryById(callStoryId: string) {
  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{
      id: string;
      caller: string;
      callee: string;
      direction: string;
      end_at: Date | null;
    }>(
      `
        SELECT id, caller, callee, direction, end_at
        FROM call_stories
        WHERE id = $1
      `,
      [callStoryId],
    );

    return result.rows[0] ?? null;
  } finally {
    await client.end();
  }
}

export async function getCallSpans(callStoryId: string) {
  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{
      id: string;
      type: string;
      current_party: string | null;
      channel_id: string;
      start_at: Date;
      end_at: Date | null;
      metadata: Record<string, string> | null;
    }>(
      `
        SELECT id, type, current_party, channel_id, start_at, end_at, metadata
        FROM call_spans
        WHERE call_story_id = $1
        ORDER BY start_at ASC
      `,
      [callStoryId],
    );

    return result.rows;
  } finally {
    await client.end();
  }
}

export async function getCallStoryEvents(callStoryId: string) {
  const client = createClient();
  await client.connect();

  try {
    const result = await client.query<{
      id: string;
      type: string;
      current_party: string | null;
      channel_id: string | null;
      occurred_at: Date;
      metadata: Record<string, unknown> | null;
    }>(
      `
        SELECT id, type, current_party, channel_id, occurred_at, metadata
        FROM call_story_events
        WHERE call_story_id = $1
        ORDER BY occurred_at ASC, id ASC
      `,
      [callStoryId],
    );

    return result.rows;
  } finally {
    await client.end();
  }
}

export async function waitForCallSpans(
  callStoryId: string,
  predicate: (spans: Awaited<ReturnType<typeof getCallSpans>>) => boolean,
  timeoutMs = 45_000,
) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const spans = await getCallSpans(callStoryId);
    if (predicate(spans)) {
      return spans;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  throw new Error(`Timed out waiting for spans for call story ${callStoryId}`);
}

export async function assertNoCallStory(params: {
  caller?: string;
  callee?: string;
  direction?: string;
  waitMs?: number;
}) {
  const client = createClient();
  await client.connect();

  try {
    await new Promise((resolve) => setTimeout(resolve, params.waitMs ?? 5_000));

    const result = await client.query<{ count: string }>(
      `
        SELECT COUNT(*)::text AS count
        FROM call_stories cs
        WHERE ($1::text IS NULL OR cs.caller = $1)
          AND ($2::text IS NULL OR cs.callee = $2)
          AND ($3::text IS NULL OR cs.direction = $3)
      `,
      [params.caller ?? null, params.callee ?? null, params.direction ?? null],
    );

    if (Number(result.rows[0]?.count ?? '0') > 0) {
      throw new Error(
        `Expected no call story for caller=${params.caller} callee=${params.callee} direction=${params.direction}`,
      );
    }
  } finally {
    await client.end();
  }
}

export async function assertRecordingProduced(
  callStoryId: string,
  timeoutMs = 90_000,
) {
  const spans = await waitForCallSpans(
    callStoryId,
    (rows) =>
      rows.some(
        (row) =>
          row.type === 'RECORDING' &&
          row.metadata?.file_name != null &&
          row.end_at !== null,
      ),
    timeoutMs,
  );

  const span = spans.find(
    (row) => row.type === 'RECORDING' && row.metadata?.file_name != null,
  );

  if (!span) {
    throw new Error(
      `No RECORDING span with a file_name found for call story ${callStoryId}`,
    );
  }

  return {
    fileName: span.metadata!.file_name!,
    sha512: span.metadata?.sha512 ?? null,
    fileSize: span.metadata?.fileSize ? Number(span.metadata.fileSize) : null,
  };
}

export async function waitForFreeSwitchReady(params?: {
  timeoutMs?: number;
  settleMs?: number;
}) {
  const timeoutMs = params?.timeoutMs ?? 60_000;
  const settleMs = params?.settleMs ?? 2_000;
  const deadline = Date.now() + timeoutMs;

  const readHeartbeatSnapshot = async () => {
    const { stdout } = await execFileAsync(
      'docker',
      [
        ...composeArgs,
        'exec',
        '-T',
        'redis',
        'redis-cli',
        '--raw',
        'KEYS',
        'fs.*',
      ],
      {
        cwd: repoRoot,
        timeout: 30_000,
        maxBuffer: 4 * 1024 * 1024,
      },
    );

    const keys = stdout
      .split('\n')
      .map((key) => key.trim())
      .filter(Boolean)
      .sort();

    if (keys.length === 0) {
      return new Map<string, string>();
    }

    const { stdout: valuesOutput } = await execFileAsync(
      'docker',
      [
        ...composeArgs,
        'exec',
        '-T',
        'redis',
        'redis-cli',
        '--raw',
        'MGET',
        ...keys,
      ],
      {
        cwd: repoRoot,
        timeout: 30_000,
        maxBuffer: 4 * 1024 * 1024,
      },
    );

    const values = valuesOutput.split('\n');
    return new Map(keys.map((key, index) => [key, values[index] ?? '']));
  };

  const initialSnapshot = await readHeartbeatSnapshot();

  while (Date.now() < deadline) {
    const snapshot = await readHeartbeatSnapshot();
    const hasFreshHeartbeat =
      snapshot.size > 0 &&
      (initialSnapshot.size === 0 ||
        snapshot.size !== initialSnapshot.size ||
        [...snapshot.entries()].some(
          ([key, value]) => initialSnapshot.get(key) !== value,
        ));

    if (hasFreshHeartbeat) {
      await new Promise((resolve) => setTimeout(resolve, settleMs));
      return [...snapshot.keys()];
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  throw new Error('Timed out waiting for FreeSWITCH heartbeat readiness');
}
