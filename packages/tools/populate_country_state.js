import fs from 'fs';
import _ from 'lodash';
import pg from 'pg';

const { Client } = pg;

function readJsonFile(filePath) {
  const data = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(data);
}

async function insertData() {
  const countriesData = readJsonFile('data.json');
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
  });

  await client.connect();

  try {
    for (const chunk of _.chunk(countriesData, 20)) {
      const values = [];
      const placeholders = [];

      chunk.forEach((country, index) => {
        const offset = index * 2;
        placeholders.push(`($${offset + 1}, $${offset + 2})`);
        values.push(country.code2, country.name);
      });

      await client.query(
        `
          INSERT INTO "Country" ("code", "name")
          VALUES ${placeholders.join(', ')}
          ON CONFLICT ("code") DO NOTHING
        `,
        values,
      );
    }

    const statesData = countriesData.flatMap((country) =>
      country.states.map((state) => ({
        name: state.name,
        countryCode: country.code2,
      })),
    );

    for (const chunk of _.chunk(statesData, 20)) {
      const values = [];
      const placeholders = [];

      chunk.forEach((state, index) => {
        const offset = index * 2;
        placeholders.push(`($${offset + 1}, $${offset + 2})`);
        values.push(state.name, state.countryCode);
      });

      await client.query(
        `
          INSERT INTO "State" ("name", "countryCode")
          VALUES ${placeholders.join(', ')}
          ON CONFLICT DO NOTHING
        `,
        values,
      );
    }

    console.log('Data has been inserted successfully');
  } catch (error) {
    console.error('Error inserting data:', error);
  } finally {
    await client.end();
  }
}

insertData()
  .then(() => {
    console.log('Data insertion complete');
  })
  .catch((e) => {
    console.log('Error inserting data', e);
  });
