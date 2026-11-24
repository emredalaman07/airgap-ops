-- Schema for bastion_ops
-- Usage: sudo -u postgres psql -p 9999 -d bastion_ops < sql/init.sql

CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.assets (
    id          SERIAL PRIMARY KEY,
    hostname    VARCHAR(64) NOT NULL UNIQUE,
    ip_address  INET NOT NULL,
    environment VARCHAR(32) NOT NULL DEFAULT 'homelab',
    status      VARCHAR(24) NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.maintenance_logs (
    id           SERIAL PRIMARY KEY,
    asset_id     INT NOT NULL REFERENCES ops.assets(id) ON DELETE CASCADE,
    action       VARCHAR(100) NOT NULL,
    performed_by VARCHAR(64) NOT NULL,
    notes        TEXT,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.audit_events (
    id          BIGSERIAL PRIMARY KEY,
    source      VARCHAR(64) NOT NULL,
    severity    VARCHAR(16) NOT NULL CHECK (severity IN ('INFO', 'WARN', 'ERROR', 'CRITICAL')),
    message     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_maintenance_asset_id ON ops.maintenance_logs(asset_id);
CREATE INDEX IF NOT EXISTS idx_audit_severity_time ON ops.audit_events(severity, created_at DESC);

-- Grant access to ops_user when present
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ops_user') THEN
        GRANT USAGE ON SCHEMA ops TO ops_user;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ops TO ops_user;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ops TO ops_user;
    END IF;
END
$$;
