# Backup and Retention

`pg_backup.sh` creates compressed custom-format dumps (`pg_dump -Fc`) from port `9999`, writes a `.sha256` file next to each dump, logs results to `/var/log/bastion-pg/backup.log`, and deletes backups older than `RETENTION_DAYS` (default `7`).

## Setup Directories and Script
Install the backup and restore scripts into `/usr/local/bin` so the `postgres` user and `systemd` can execute them cleanly regardless of home directory permissions:

```bash
sudo install -m 755 scripts/pg_backup.sh scripts/pg_restore.sh /usr/local/bin/
sudo mkdir -p /var/backups/bastion-pg /var/log/bastion-pg
sudo chown -R postgres:postgres /var/backups/bastion-pg /var/log/bastion-pg
sudo chmod 750 /var/backups/bastion-pg /var/log/bastion-pg
```

## Run Manually
```bash
sudo -u postgres /usr/local/bin/pg_backup.sh
sudo ls -lh /var/backups/bastion-pg
sudo tail -n 10 /var/log/bastion-pg/backup.log
```

Verify checksum manually:
```bash
sudo bash -c 'cd /var/backups/bastion-pg && sha256sum -c *.sha256'
```

## Enable Daily systemd Timer
```bash
sudo cp systemd/bastion-pg-backup.service systemd/bastion-pg-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bastion-pg-backup.timer
systemctl list-timers bastion-pg-backup.timer
```

## Retention Override
```bash
sudo -u postgres RETENTION_DAYS=14 /usr/local/bin/pg_backup.sh
```
