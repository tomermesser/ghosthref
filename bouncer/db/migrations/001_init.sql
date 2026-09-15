-- Only real violations get a row here, not every compliant request.
CREATE TABLE IF NOT EXISTS violations (
  id          BIGSERIAL PRIMARY KEY,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip          INET        NOT NULL,
  user_agent  TEXT        NOT NULL,
  tier        TEXT        NOT NULL CHECK (tier IN ('bad-bot', 'from-href', 'user-question-bot', 'forged')),
  action      TEXT        NOT NULL CHECK (action IN ('pass', 'throttle', 'block'))
  -- forged is future work.
);

CREATE INDEX IF NOT EXISTS violations_ip_idx ON violations (ip, occurred_at DESC);
CREATE INDEX IF NOT EXISTS violations_occurred_idx ON violations (occurred_at DESC);
