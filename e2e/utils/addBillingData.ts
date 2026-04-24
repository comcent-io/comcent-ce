import { Client } from 'pg';
import { getOrgBySubdomain } from './org';
import { getCallStories, getOrgAuditLogs } from './callStoryData';

function createClient() {
  return new Client({ connectionString: process.env.DATABASE_URL });
}

export async function addBillingUsageData() {
  const org = await getOrgBySubdomain('acme');
  if (!org) {
    throw new Error('Organization with subdomain acme not found');
  }

  const client = createClient();
  await client.connect();
  try {
    const callStories = getCallStories(org.id);
    for (const s of callStories) {
      await client.query(
        `INSERT INTO call_stories (id, org_id, start_at, end_at, caller, callee, outbound_caller_id, direction, is_transcribed, is_summarized, is_sentiment_analyzed, is_anonymized, hangup_party)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
         ON CONFLICT (id) DO NOTHING`,
        [
          s.id,
          s.org_id,
          s.start_at,
          s.end_at,
          s.caller,
          s.callee,
          s.outbound_caller_id,
          s.direction,
          s.is_transcribed,
          s.is_summarized,
          s.is_sentiment_analyzed,
          s.is_anonymized,
          s.hangup_party,
        ],
      );
    }

    const orgAuditLogs = getOrgAuditLogs(org.id);
    for (const l of orgAuditLogs) {
      await client.query(
        `INSERT INTO org_audit_logs (id, type, org_id, call_story_id, quantity, created_at, cost)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (id) DO NOTHING`,
        [
          l.id,
          l.type,
          l.org_id,
          l.call_story_id,
          l.quantity,
          l.created_at,
          l.cost,
        ],
      );
    }
  } finally {
    await client.end();
  }
}
