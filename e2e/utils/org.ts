import { Client } from 'pg';

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

export async function getOrgBySubdomain(orgSubdomain: string) {
  const client = createClient();
  await client.connect();
  try {
    const result = await client.query<{
      id: string;
      name: string;
      subdomain: string;
    }>('SELECT id, name, subdomain FROM orgs WHERE subdomain = $1', [
      orgSubdomain,
    ]);
    return result.rows[0] ?? null;
  } finally {
    await client.end();
  }
}
