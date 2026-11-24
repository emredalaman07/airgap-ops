# PostgreSQL Setup Notes

PostgreSQL runs locally on port `9999` (`listen_addresses = 'localhost'`).

## Install and Configure
```bash
sudo ./scripts/setup_postgres.sh
sudo ./scripts/setup_postgres.sh --apply
```

Verify the service and port:
```bash
systemctl status postgresql
pg_isready -h localhost -p 9999
```

## Create Role and Database
Switch to the `postgres` user and create the project role/database:

```bash
sudo -u postgres psql -p 9999 -c "CREATE ROLE ops_user WITH LOGIN PASSWORD 'change_me';"
sudo -u postgres psql -p 9999 -c "CREATE DATABASE bastion_ops OWNER ops_user;"
```

Load the schema and sample data:
```bash
sudo -u postgres psql -p 9999 -d bastion_ops -f sql/init.sql
sudo -u postgres psql -p 9999 -d bastion_ops -f sql/seed.sql
```

Quick check:
```bash
sudo -u postgres psql -p 9999 -d bastion_ops -c "SELECT hostname, ip_address, status FROM ops.assets;"
```

## Air-gapped Check
After packages are installed, disable the VM's NAT adapter and verify local database access still works over the Host-Only SSH session:
```bash
ping -c 2 8.8.8.8        # expected to fail
pg_isready -h localhost -p 9999
```
