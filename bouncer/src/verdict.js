const robots = require('./robots');
const store = require('./store');

// Bots that always get through, no checks at all.
const ALLOWLIST = ['Googlebot', 'Bingbot'];

// Bots fetching one page live for a real person right now — never block.
const USER_QUESTION_BOTS = [
  'ChatGPT-User',   // OpenAI
  'Claude-User',    // Anthropic
  'Perplexity-User', // Perplexity
  'Meta-ExternalFetcher', // Meta
];

const WARN_THRESHOLD = 5;   // below this: just log it
const BLOCK_THRESHOLD = 20; // at or above this: block

function matches(ua, list) {
  return list.some((name) => ua.includes(name));
}

async function verdict({ ip, ua, path, referer }) {
  // 1. On the allowlist? Always pass.
  if (matches(ua, ALLOWLIST)) {
    return { tier: 'compliant', action: 'pass' };
  }

  // 2. Already blocked? Stay blocked.
  if (await store.isBlocked(ip)) {
    return { tier: 'bad-bot', action: 'block' };
  }

  // 3. Path allowed by robots.txt? Then pass.
  if (!robots.isDisallowed(path, ua)) {
    return { tier: 'compliant', action: 'pass' };
  }

  // 4. Path disallowed, but this bot is ok. Pass and log it.
  if (matches(ua, USER_QUESTION_BOTS)) {
    store.logViolation({ ip, ua, tier: 'user-question-bot', action: 'pass' });
    return { tier: 'user-question-bot', action: 'pass' };
  }

  // 5. A real violation. No referer = read robots.txt directly. A referer
  //    = followed the invisible link on the homepage.
  const tier = referer ? 'from-href' : 'bad-bot';

  // 6. Count it and escalate.
  const count = await store.recordViolation(ip);
  let action = 'pass';
  if (count >= BLOCK_THRESHOLD) {
    action = 'block';
    await store.block(ip);
  } else if (count >= WARN_THRESHOLD) {
    action = 'throttle';
  }

  store.logViolation({ ip, ua, tier, action });
  return { tier, action };
}

module.exports = { verdict };
