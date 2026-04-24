import { Client } from 'pg';

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

export async function truncateAllTables() {
  const client = createClient();
  await client.connect();
  try {
    const result = await client.query<{ table_name: string }>(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    `);

    const tables = result.rows
      .filter(
        ({ table_name }) =>
          !table_name.startsWith('_') && table_name !== 'schema_migrations',
      )
      .map(({ table_name }) => `"${table_name}"`)
      .join(', ');

    if (tables) {
      await client.query(`TRUNCATE ${tables} RESTART IDENTITY CASCADE`);
      console.log('All tables truncated successfully.');
    }
  } catch (error) {
    console.error('Error truncating tables:', error);
  } finally {
    await client.end();
  }
}

export async function ageVerificationEmailCooldown(
  email: string,
  seconds = 61,
) {
  const client = createClient();
  await client.connect();
  try {
    await client.query(
      `
        UPDATE users
        SET verification_email_sent_at = NOW() - ($2 || ' seconds')::interval
        WHERE email = $1
      `,
      [email, seconds],
    );
  } finally {
    await client.end();
  }
}

export async function ageInviteEmailCooldown(
  subdomain: string,
  email: string,
  seconds = 61,
) {
  const client = createClient();
  await client.connect();
  try {
    await client.query(
      `
        UPDATE org_invites AS oi
        SET invite_email_sent_at = NOW() - ($3 || ' seconds')::interval
        FROM orgs AS o
        WHERE oi.org_id = o.id
          AND o.subdomain = $1
          AND oi.email = $2
          AND oi.status = 'PENDING'
      `,
      [subdomain, email, seconds],
    );
  } finally {
    await client.end();
  }
}
