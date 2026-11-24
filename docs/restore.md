# Backup Restore and Verification

`pg_restore.sh` validates the backup checksum, restores a `.dump` file into a clean target database, and checks row counts across the `ops` tables.

## Restore Drill (Safe Test Database)
By default, the script restores into `bastion_ops_restore_test` so `bastion_ops` stays untouched:

```bash
LATEST="$(ls -t /var/backups/bastion-pg/bastion_ops_*.dump | head -n 1)"
sudo -u postgres ./scripts/pg_restore.sh "${LATEST}"
```

Inspect restored data:
```bash
sudo -u postgres psql -p 9999 -d bastion_ops_restore_test \
    -c "SELECT hostname, ip_address, status FROM ops.assets;"
```

Clean up the test database after verification:
```bash
sudo -u postgres psql -p 9999 -d postgres \
    -c "DROP DATABASE IF EXISTS bastion_ops_restore_test;"
```

## Restoring Into Production
To overwrite the main database, pass `bastion_ops` explicitly as the second argument (ensure active connections are stopped first):

```bash
sudo -u postgres ./scripts/pg_restore.sh "${LATEST}" bastion_ops
```
