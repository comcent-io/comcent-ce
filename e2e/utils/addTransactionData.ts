import { Client } from 'pg';
import { getTransactionData } from './transactionData';
import { getOrgBySubdomain } from './org';

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

export async function addTransactionData() {
  const org = await getOrgBySubdomain('acme');
  if (!org) {
    throw new Error('Organization with subdomain acme not found');
  }

  const client = createClient();
  await client.connect();
  try {
    const transactions = getTransactionData(org.id);
    for (const t of transactions) {
      await client.query(
        `INSERT INTO transactions (id, order_id, payment_gateway, customer_email, amount, date, description, org_id, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT (id) DO NOTHING`,
        [
          t.id,
          t.order_id,
          t.payment_gateway,
          t.customer_email,
          t.amount,
          t.date,
          t.description,
          t.org_id,
          t.created_at,
          t.updated_at,
        ],
      );
    }
  } finally {
    await client.end();
  }
}
