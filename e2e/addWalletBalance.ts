import { Client } from 'pg';

export async function addWalletBalance(amount: number) {
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    await client.query('UPDATE orgs SET wallet_balance = $1', [
      amount * 1_000_000,
    ]);
  } finally {
    await client.end();
  }
}
