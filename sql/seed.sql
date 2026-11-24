-- Sample records for testing queries, backups and restore verification
--   psql -p 9999 -d bastion_ops -f sql/seed.sql

INSERT INTO ops.assets (hostname, ip_address, environment, status)
VALUES
    ('bastion-db-01', '192.168.56.10', 'homelab', 'active'),
    ('sensor-gw-01',  '192.168.56.20', 'homelab', 'active'),
    ('telemetry-01',  '192.168.56.21', 'homelab', 'maintenance')
ON CONFLICT (hostname) DO NOTHING;

INSERT INTO ops.maintenance_logs (asset_id, action, performed_by, notes)
SELECT id, 'initial_hardening', 'emre', 'ssh key-only, firewalld enabled, selinux enforcing'
FROM ops.assets
WHERE hostname = 'bastion-db-01';

INSERT INTO ops.audit_events (source, severity, message)
VALUES
    ('sshd',       'INFO', 'Key-only authentication enabled'),
    ('firewalld',  'INFO', 'Public zone restricted to ssh'),
    ('postgresql', 'INFO', 'Database cluster initialized on port 9999');
