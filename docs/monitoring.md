# System Monitoring and Failure Scenarios

`scripts/health_check.sh` checks host resources, PostgreSQL readiness and active connections (port `9999`), latest backup freshness, SELinux mode, and recent journal errors.

## Usage
```bash
sudo ./scripts/health_check.sh
echo "exit code: $?"
```

Exit codes:
- `0` — all checks passed (`OK`)
- `1` — at least one warning (`WARN`)
- `2` — at least one critical failure (`CRIT`)

Thresholds can be overridden via environment variables (`MEM_WARN`, `MEM_CRIT`, `DISK_WARN`, `DISK_CRIT`, `BACKUP_MAX_AGE_HOURS`, `PG_PORT`).

## Failure Scenario Tests

### 1. PostgreSQL Service Down
Stop PostgreSQL and verify `health_check.sh` reports `CRIT` (exit code `2`):
```bash
sudo systemctl stop postgresql
./scripts/health_check.sh; echo "exit=$?"
sudo systemctl start postgresql
./scripts/health_check.sh; echo "exit=$?"
```

### 2. Missing Backup Directory / File
Test with an empty backup directory to confirm alerting:
```bash
BACKUP_DIR=/tmp/empty-backup-test ./scripts/health_check.sh; echo "exit=$?"
```

### 3. Inspecting System & Audit Logs
```bash
sudo journalctl -u postgresql -n 30 --no-pager
sudo ausearch -m avc -ts recent
```
