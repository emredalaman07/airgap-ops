# Server Hardening

Baseline setup used on the Rocky Linux 9 VM (`airgap-db-01`).

## VM Network
- Adapter 1 (NAT): used during initial `dnf` package installation, disabled afterwards to test air-gapped operation.
- Adapter 2 (Host-Only, `192.168.56.0/24`): local SSH access from the host when external internet is cut.

## SSH
Generate an ed25519 key on the host and copy it to `~/.ssh/authorized_keys` on the VM before disabling password logins:

```bash
ssh-keygen -t ed25519
ssh-copy-id emre@192.168.56.101
```

Confirm key login works, then run:

```bash
sudo ./scripts/harden_server.sh
sudo ./scripts/harden_server.sh --apply
```

## Firewalld
`firewalld` stays active with `public` as the default zone and only `ssh` allowed. PostgreSQL listens on `localhost:9999` and is not exposed on external interfaces.

## SELinux
Keep SELinux in `Enforcing` mode (`getenforce`). Because PostgreSQL uses non-default port `9999`, `setup_postgres.sh` registers it under `postgresql_port_t`:

```bash
sudo semanage port -a -t postgresql_port_t -p tcp 9999
```

When troubleshooting a permission block, check AVC denials first:

```bash
sudo ausearch -m avc -ts recent
```

Fix the file context (`semanage fcontext` + `restorecon`) or boolean (`setsebool -P`). Only switch to `setenforce 0` temporarily if needed to isolate the issue, then return to `setenforce 1`.

## Air-gapped Check
Once packages are installed, disable Adapter 1 (NAT) in VirtualBox and verify external routing fails while local SSH, PostgreSQL, backups and health checks continue working.
