// Redis holds live state. Postgres holds permanent history.
const { Pool } = require('pg');
const Redis = require('ioredis');

// --- Redis ---
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis',
  port: Number(process.env.REDIS_PORT || 6379),
  maxRetriesPerRequest: 1,
});

async function isBlocked(ip) {
  return (await redis.exists(`block:${ip}`)) === 1;
}

async function block(ip) {
  await redis.set(`block:${ip}`, '1');
}

// Counts violations for one IP, forever.
async function recordViolation(ip) {
  return redis.incr(`viol:${ip}`);
}

// Test-only: wipes one IP's state so the test suite starts clean every run.
async function resetForTests(ip) {
  await redis.del(`block:${ip}`, `viol:${ip}`);
}

// --- Postgres ---
const pg = new Pool({
  host: process.env.PG_HOST || 'postgres',
  port: Number(process.env.PG_PORT || 5432),
  user: process.env.PG_USER || 'ghosthref',
  password: process.env.PG_PASSWORD || 'ghosthref',
  database: process.env.PG_DATABASE || 'ghosthref',
});

function logViolation({ ip, ua, tier, action }) {
  pg.query(
    `INSERT INTO violations (ip, user_agent, tier, action)
     VALUES ($1, $2, $3, $4)`,
    [ip, ua, tier, action]
  ).catch((err) => console.error('[store] failed to log violation:', err.message));
}

module.exports = { isBlocked, block, recordViolation, logViolation, resetForTests };
