-- Sample data for testing queries, backups and restore drills
-- Usage: sudo -u postgres psql -p 9999 -d airgap_ops < sql/seed.sql

INSERT INTO ops.assets (hostname, ip_address, environment, status)
VALUES
    ('airgap-01',     '192.168.56.101', 'homelab', 'active'),
    ('sensor-gw-01',  '192.168.56.102', 'homelab', 'active'),
    ('telemetry-01',  '192.168.56.103', 'homelab', 'maintenance')
ON CONFLICT (hostname) DO NOTHING;

INSERT INTO ops.maintenance_logs (asset_id, action, performed_by, notes)
SELECT id, 'initial_hardening', 'emre', 'ssh key-only, firewalld active, selinux enforcing'
FROM ops.assets
WHERE hostname = 'airgap-01'
  AND NOT EXISTS (
      SELECT 1 FROM ops.maintenance_logs m
      WHERE m.asset_id = ops.assets.id AND m.action = 'initial_hardening'
  );

INSERT INTO ops.audit_events (source, severity, message)
VALUES
    ('sshd',       'INFO', 'Password authentication disabled'),
    ('firewalld',  'INFO', 'Public zone restricted to ssh'),
    ('postgresql', 'INFO', 'Cluster listening on localhost:9999');
