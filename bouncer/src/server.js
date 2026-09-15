const express = require('express');
const robots = require('./robots');
const { verdict } = require('./verdict');

const PORT = process.env.PORT || 3000;
const STATUS_FOR_ACTION = { pass: 204, throttle: 401, block: 403 };

robots.load();

const app = express();

// Always healthy, no checks — keeps a verdict bug from also failing this.
app.get('/healthz', (_req, res) => res.status(200).send('ok'));

// nginx asks this before serving anything. Must reply 204, 401, or 403.
app.get('/verdict', async (req, res) => {
  const ip = req.get('X-Real-IP') || req.ip;
  const ua = req.get('User-Agent') || '';
  const path = req.get('X-Original-URI') || '/';
  const referer = req.get('Referer') || null;

  try {
    const { tier, action } = await verdict({ ip, ua, path, referer });
    // Only nginx reads this header — never sent on to the client.
    res.set('X-Tier', tier);
    res.status(STATUS_FOR_ACTION[action]).end();
  } catch (err) {
    // A bug here should never take the site down, so default to allow.
    console.error('[verdict] error, failing open:', err.message);
    res.status(204).end();
  }
});

app.listen(PORT, () => console.log(`[bouncer] listening on ${PORT}`));
