-- Only real violations get a row here, not every compliant request.
-- No `path` column: there's only one honeypot, so it's the same on every row.
-- No `referer` column: `tier` already says bad-bot vs from-href directly.
CREATE TABLE IF NOT EXISTS violations (
  id          BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip          INET        NOT NULL,
  user_agent  TEXT        NOT NULL,
  tier        TEXT        NOT NULL CHECK (tier IN ('bad-bot', 'from-href', 'user-question-bot', 'forged')),
  action      TEXT        NOT NULL CHECK (action IN ('pass', 'throttle', 'block'))
  -- forged is future work, kept here so it needs no later migration.
);

CREATE INDEX IF NOT EXISTS violations_ip_idx ON violations (ip, occurred_at DESC);
CREATE INDEX IF NOT EXISTS violations_occurred_idx ON violations (occurred_at DESC);
