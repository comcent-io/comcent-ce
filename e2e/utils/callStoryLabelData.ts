import { Client } from 'pg';
import { v4 as uuidv4 } from 'uuid';

// Callers of the seeded calls, by the labels each call has.
export const LABELLED_CALLS = [
  { caller: '+15550100001', labels: ['Billing'] },
  { caller: '+15550100002', labels: ['Refund'] },
  { caller: '+15550100003', labels: ['Shipping'] },
  { caller: '+15550100004', labels: [] as string[] },
];

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

// An org of its own for the Call Story label filter, so the calls the
// telephony specs make in acme don't change what its list shows: the
// baseline admin, three org labels and LABELLED_CALLS. A new subdomain each
// run, so a retry starts from the same list. Returns the subdomain.
export async function seedLabelledCallsOrg(): Promise<string> {
  const subdomain = `labels${Date.now().toString(36)}`;
  const orgId = uuidv4();
  const now = new Date();

  const client = createClient();
  await client.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `
      INSERT INTO orgs (
        id, name, subdomain, use_custom_domain, assign_ext_automatically,
        is_active, max_members, enable_call_recording, labels, created_at,
        updated_at
      )
      VALUES ($1, 'Lantern Labs', $2, false, false, true, 10, true, $3::jsonb,
              $4, $4)
    `,
      [
        orgId,
        subdomain,
        JSON.stringify([
          { name: 'Billing', description: 'Questions about an invoice' },
          { name: 'Refund', description: 'The caller wants money back' },
          { name: 'Shipping', description: 'Where an order is' },
        ]),
        now,
      ],
    );

    await client.query(
      `
      INSERT INTO org_members (
        user_id, org_id, role, username, sip_password, extension_number, presence
      )
      SELECT id, $1, 'ADMIN', 'testadmin', 'ytgJ6sp9xcvofYT8UlKlr', NULL, 'Logged Out'
      FROM users WHERE email = 'test.admin@example.com'
    `,
      [orgId],
    );

    for (const [i, call] of LABELLED_CALLS.entries()) {
      const startAt = new Date(now.getTime() - (i + 1) * 60 * 60 * 1000);
      await client.query(
        `
        INSERT INTO call_stories (
          id, org_id, start_at, end_at, caller, callee, direction,
          is_labeled, labels
        )
        VALUES ($1, $2, $3, $4, $5, '+15550109999', 'inbound', true, $6::jsonb)
      `,
        [
          uuidv4(),
          orgId,
          startAt,
          new Date(startAt.getTime() + 5 * 60 * 1000),
          call.caller,
          JSON.stringify(call.labels),
        ],
      );
    }

    await client.query('COMMIT');
    return subdomain;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    await client.end();
  }
}
