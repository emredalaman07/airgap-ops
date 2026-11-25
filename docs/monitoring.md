# Monitoring and Failure Scenarios

`scripts/health_check.sh` checks CPU load, memory, `/` disk usage, PostgreSQL service/port readiness (`9999`), active connections (`pg_stat_activity`), last backup age, SELinux mode, and recent `journalctl` errors.

## Usage
Run with `sudo` so the script can read `/var/backups/airgap-ops` (`0750`) and query `pg_stat_activity`:

```bash
sudo ./scripts/health_check.sh
echo "exit=$?"
```

Exit codes:
- `0`: all checks OK
- `1`: warning (`WARN`)
- `2`: critical (`CRIT`)

Thresholds can be overridden with env vars (`MEM_WARN`, `MEM_CRIT`, `DISK_WARN`, `DISK_CRIT`, `PG_CONN_WARN`, `BACKUP_MAX_AGE_HOURS`, `PG_PORT`).

## Failure Tests

### 1. PostgreSQL stopped
```bash
sudo systemctl stop postgresql
sudo ./scripts/health_check.sh; echo "exit=$?"   # expects CRIT, exit=2
sudo systemctl start postgresql
sudo ./scripts/health_check.sh; echo "exit=$?"   # expects OK, exit=0
```

### 2. Missing backup
```bash
sudo BACKUP_DIR=/tmp/empty-backups ./scripts/health_check.sh; echo "exit=$?"
```

### 3. Log inspection
```bash
sudo journalctl -u postgresql -n 30 --no-pager
sudo ausearch -m avc -ts recent
```
