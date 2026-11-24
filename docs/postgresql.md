# PostgreSQL Setup

PostgreSQL runs locally on `localhost:9999`. Local maintenance scripts (`pg_backup.sh`, `pg_restore.sh`) connect as `postgres` over the Unix socket (`peer` auth), while TCP connections on `127.0.0.1` / `::1` require `scram-sha-256`.

## Install and Start
```bash
sudo ./scripts/setup_postgres.sh
sudo ./scripts/setup_postgres.sh --apply
```

Check service status:
```bash
systemctl status postgresql
pg_isready -h localhost -p 9999
```

## Create Role, Database and Schema
Note: redirect SQL files via `<` so the shell opens them before switching to `postgres` (avoids permission errors if the repo lives under `/home/<user>`).

```bash
sudo -u postgres psql -p 9999 -c "CREATE ROLE ops_user WITH LOGIN PASSWORD 'change_me';"
sudo -u postgres psql -p 9999 -c "CREATE DATABASE bastion_ops OWNER ops_user;"
sudo -u postgres psql -p 9999 -d bastion_ops -v ON_ERROR_STOP=1 < sql/init.sql
sudo -u postgres psql -p 9999 -d bastion_ops -v ON_ERROR_STOP=1 < sql/seed.sql
```

Test query (both via peer socket and `ops_user` over TCP):
```bash
sudo -u postgres psql -p 9999 -d bastion_ops -c "SELECT hostname, ip_address, status FROM ops.assets;"
psql -h localhost -p 9999 -U ops_user -d bastion_ops -c "SELECT count(*) FROM ops.audit_events;"
```

## Air-gapped Check
With the NAT adapter disabled:
```bash
ping -c 2 8.8.8.8        # should fail
pg_isready -h localhost -p 9999
```
