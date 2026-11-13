CREATE TABLE IF NOT EXISTS neural.password_reset_logs (
  id bigserial PRIMARY KEY,
  email text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL,
  detail text NOT NULL DEFAULT ''
);
