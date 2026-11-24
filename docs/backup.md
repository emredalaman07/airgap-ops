# Automated Backup and Retention

Backups are taken with `pg_dump -Fc` (compressed custom format) on port `9999`, paired with a `.sha256` checksum and logged to `/var/log/bastion-pg/backup.log`.

## Prepare Directories
```bash
sudo mkdir -p /var/backups/bastion-pg /var/log/bastion-pg
sudo chown -R postgres:postgres /var/backups/bastion-pg /var/log/bastion-pg
sudo chmod 750 /var/backups/bastion-pg /var/log/bastion-pg
```

## Manual Run
```bash
sudo -u postgres ./scripts/pg_backup.sh
```

Verify checksum:
```bash
sha256sum -c /var/backups/bastion-pg/bastion_ops_*.dump.sha256
```

## Schedule with systemd Timer
```bash
sudo install -m 755 scripts/pg_backup.sh /usr/local/bin/pg_backup.sh
sudo cp systemd/bastion-pg-backup.service systemd/bastion-pg-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bastion-pg-backup.timer
systemctl list-timers bastion-pg-backup.timer
```

## Retention
By default, backups older than `7` days are deleted automatically. Override via `RETENTION_DAYS`:
```bash
sudo -u postgres RETENTION_DAYS=14 /usr/local/bin/pg_backup.sh
```
