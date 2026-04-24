import pg from 'pg';

const { Client } = pg;

async function getCallStoryAssociation(callStoryId) {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
  });

  await client.connect();

  try {
    const callStoryResult = await client.query(
      `
        SELECT cs.*, row_to_json(o.*) AS org
        FROM "CallStory" cs
        JOIN "Org" o ON o.id = cs."orgId"
        WHERE cs.id = $1
      `,
      [callStoryId],
    );

    const callStory = callStoryResult.rows[0];
    if (!callStory) return null;

    const [callSpansResult, webhooksResult] = await Promise.all([
      client.query(
        `
          SELECT *
          FROM "CallSpan"
          WHERE "callStoryId" = $1
          ORDER BY "startAt" ASC
        `,
        [callStoryId],
      ),
      client.query(
        `
          SELECT *
          FROM "OrgWebhook"
          WHERE "orgId" = $1
          ORDER BY name ASC
        `,
        [callStory.orgId],
      ),
    ]);

    return {
      ...callStory,
      org: {
        ...callStory.org,
        webhooks: webhooksResult.rows,
      },
      callSpans: callSpansResult.rows,
    };
  } finally {
    await client.end();
  }
}

async function main() {
  const callStoryId = '';
  const callStoryWithAssociation = await getCallStoryAssociation(callStoryId);
  console.log(JSON.stringify(callStoryWithAssociation, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
