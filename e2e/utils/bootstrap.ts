import fs from 'fs/promises';
import path from 'path';
import type { APIRequestContext, Browser } from '@playwright/test';
import jsonwebtoken from 'jsonwebtoken';
import { Client } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import { ALL_TEST_DIDS } from '../telephony/testAllocations';

const DEFAULT_INBOUND_FLOW_GRAPH = {
  nodes: [],
  edges: [],
};

const WALLET_BALANCE = 30 * 1_000_000;

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

export async function waitForAppReady(request: APIRequestContext) {
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      const response = await request.get('/login', { failOnStatusCode: false });
      const bodyText = await response.text();

      if (response.status() === 200 && !bodyText.includes('502 Bad Gateway')) {
        return;
      }
    } catch {
      // App is still starting up.
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  throw new Error('Application never became ready');
}

export async function seedBaselineData() {
  const client = createClient();
  await client.connect();

  const userId = uuidv4();
  const acmeOrgId = uuidv4();
  const heartcodersOrgId = uuidv4();
  const firstSipTrunkId = uuidv4();
  const lastSipTrunkId = uuidv4();
  const firstNumberId = uuidv4();
  const secondNumberId = uuidv4();
  const now = new Date();

  try {
    await client.query('BEGIN');

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
      VALUES ($1, $2, $3, true, true, $4, $4, $4)
    `,
      [userId, 'Test Admin', 'test.admin@example.com', now],
    );

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
      VALUES
      ($1, 'ACME Corp', 'acme', false, false, true, true, true, true, 5, 10, true, $3, 0, 0, 0, true, true, 'America/New_York', $2, $2),
      ($4, 'Heart Coders', 'heartcoders', false, false, true, true, true, true, 5, 10, true, $3, 0, 0, 0, true, true, 'America/New_York', $2, $2)
    `,
      [acmeOrgId, now, WALLET_BALANCE, heartcodersOrgId],
    );

    await client.query(
      `
      INSERT INTO org_billing_addresses (
        id,
        org_id,
        username,
        line_1,
        city,
        state,
        country,
        postal_code
      )
      VALUES
      ($1, $2, 'testadmin', 'ACME Corp', 'Brahmavara', 'Karnataka', 'IN', '576213'),
      ($3, $4, 'opsadmin', 'Heart Coders', 'Hubballi', 'Karnataka', 'IN', '580030')
    `,
      [uuidv4(), acmeOrgId, uuidv4(), heartcodersOrgId],
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
      VALUES
      ($1, $2, 'ADMIN', 'testadmin', 'ytgJ6sp9xcvofYT8UlKlr', NULL, 'Logged Out'),
      ($1, $3, 'ADMIN', 'opsadmin', 'ytgJ6sp9xcvofYT8UlKlr', NULL, 'Logged Out')
    `,
      [userId, acmeOrgId, heartcodersOrgId],
    );

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
      VALUES
      ($1, $2, 'First Sip', 'username', 'password', 'www.first-sip.com', $3::text[], $4, $4),
      ($5, $2, 'Last Sip', 'username', 'password', 'www.last-sip.com', $6::text[], $4, $4)
    `,
      [
        firstSipTrunkId,
        acmeOrgId,
        ['1.1.1.0/26'],
        now,
        lastSipTrunkId,
        ['2.1.1.0/26'],
      ],
    );

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
      VALUES
      ($1, 'First Number', '+14155552671', NULL, $3, $4, false, $5::jsonb, $6, $6),
      ($2, 'A1 Number', '+14155552672', NULL, $3, $7, false, $5::jsonb, $6, $6)
    `,
      [
        firstNumberId,
        secondNumberId,
        acmeOrgId,
        firstSipTrunkId,
        JSON.stringify(DEFAULT_INBOUND_FLOW_GRAPH),
        now,
        lastSipTrunkId,
      ],
    );

    for (const did of ALL_TEST_DIDS) {
      if (did === '+14155552671' || did === '+14155552672') continue;
      await client.query(
        `INSERT INTO numbers (id, name, number, allow_outbound_regex, org_id, sip_trunk_id, is_default_outbound_number, inbound_flow_graph, created_at, updated_at)
         VALUES ($1, $2, $3, NULL, $4, $5, false, $6::jsonb, $7, $7)
         ON CONFLICT (number) DO NOTHING`,
        [
          uuidv4(),
          `Test ${did}`,
          did,
          acmeOrgId,
          firstSipTrunkId,
          JSON.stringify(DEFAULT_INBOUND_FLOW_GRAPH),
          now,
        ],
      );
    }

    await client.query('COMMIT');

    return {
      user: {
        id: userId,
        email: 'test.admin@example.com',
        name: 'Test Admin',
      },
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}

export async function writeAuthenticatedStorageState(
  browser: Browser,
  storageStatePath: string,
  user: { id: string; email: string; name: string },
  baseUrl: string,
) {
  const signingKey = process.env.SIGNING_KEY;

  if (!signingKey) {
    throw new Error(
      'SIGNING_KEY is required to write authenticated storage state',
    );
  }

  const token = jsonwebtoken.sign(
    {
      sub: user.id,
      email: user.email,
      name: user.name,
      picture: null,
      email_verified: true,
      auth_provider: 'password',
      token_type: 'session',
    },
    signingKey,
    {
      algorithm: 'HS256',
      expiresIn: '24h',
    },
  );

  const context = await browser.newContext();
  await context.addCookies([
    {
      name: 'idToken',
      value: token,
      url: baseUrl,
      httpOnly: false,
      sameSite: 'Lax',
      secure: baseUrl.startsWith('https://'),
    },
  ]);

  await fs.mkdir(path.dirname(storageStatePath), { recursive: true });
  await context.storageState({ path: storageStatePath });
  await context.close();
}
