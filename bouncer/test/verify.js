const robots = require('../src/robots');
const store = require('../src/store');
const { verdict } = require('../src/verdict');

robots.load();

const HONEYPOT = '/ghosthref-internal/';
const HOMEPAGE = 'https://ghosthref.example/';

// Each case is a known scenario with a known correct answer.
const CASES = [
  { name: 'compliant visitor', ip: '10.0.0.1', ua: 'Mozilla/5.0', path: '/', expect: { tier: 'compliant', action: 'pass' } },
  { name: 'allowlisted crawler', ip: '10.0.0.2', ua: 'Googlebot/2.1', path: HONEYPOT, expect: { tier: 'compliant', action: 'pass' } },
  { name: 'user-question-bot', ip: '10.0.0.3', ua: 'ChatGPT-User/1.0', path: HONEYPOT, expect: { tier: 'user-question-bot', action: 'pass' } },
  { name: 'bad-bot, no referer', ip: '10.0.0.4', ua: 'bad-scanner/1.0', path: HONEYPOT, expect: { tier: 'bad-bot', action: 'pass' } },
  { name: 'from-href, referer set', ip: '10.0.0.5', ua: 'LinkHarvester/1.0', path: HONEYPOT, referer: HOMEPAGE, expect: { tier: 'from-href', action: 'pass' } },
  { name: 'escalates to block at 20 hits', ip: '10.0.0.6', ua: 'bad-scanner/1.0', path: HONEYPOT, repeat: 20, expect: { tier: 'bad-bot', action: 'block' } },
  { name: 'user-question-bot never blocks', ip: '10.0.0.7', ua: 'ChatGPT-User/1.0', path: HONEYPOT, repeat: 25, expect: { tier: 'user-question-bot', action: 'pass' } },
];

async function run() {
  // Clean slate every run — we removed TTLs, so a past run's blocks would otherwise stick around.
  for (const c of CASES) await store.resetForTests(c.ip);

  let passed = 0;
  for (const c of CASES) {
    let result;
    for (let i = 0; i < (c.repeat || 1); i++) {
      // use our existing function to test mock cases..
      result = await verdict({ ip: c.ip, ua: c.ua, path: c.path, referer: c.referer || null });
    }
    const ok = result.tier === c.expect.tier && result.action === c.expect.action;
    if (ok) passed++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.name.padEnd(32)} expected ${JSON.stringify(c.expect)}  got ${JSON.stringify(result)}`);
  }

  console.log(`\n${passed}/${CASES.length} passed`);
  process.exit(passed === CASES.length ? 0 : 1);
}

run();
