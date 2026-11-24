# Restore Verification

`pg_restore.sh` checks the `.sha256` file first, drops/recreates the target database, runs `pg_restore`, and prints row counts from `ops.assets`, `ops.maintenance_logs`, and `ops.audit_events`.

## Test Restore (Separate Database)
If no target database name is given, `pg_restore.sh` restores into `bastion_ops_restore_test` so `bastion_ops` is left untouched:

```bash
LATEST="$(sudo find /var/backups/bastion-pg -maxdepth 1 -name 'bastion_ops_*.dump' | sort | tail -n 1)"
sudo -u postgres /usr/local/bin/pg_restore.sh "${LATEST}"
```

Check the restored rows:
```bash
sudo -u postgres psql -p 9999 -d bastion_ops_restore_test \
    -c "SELECT hostname, ip_address, status FROM ops.assets;"
```

Drop the test database when done:
```bash
sudo -u postgres psql -p 9999 -d postgres \
    -c "DROP DATABASE IF EXISTS bastion_ops_restore_test;"
```

## Full Restore Into Main Database
Stop client traffic first, then pass `bastion_ops` explicitly:

```bash
sudo -u postgres /usr/local/bin/pg_restore.sh "${LATEST}" bastion_ops
```
