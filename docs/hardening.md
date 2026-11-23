# Server Hardening Notes

Baseline setup for the RHEL/Rocky/AlmaLinux 9 VM.

## Network
- Adapter 1 (NAT): used during package installation, disabled later for air-gapped testing.
- Adapter 2 (Host-Only): local SSH access from the host while external network is down.

## SSH
Generate a key pair on the host and copy it to the VM before applying sshd changes:

```bash
ssh-keygen -t ed25519
ssh-copy-id <user>@<vm-ip>
```

Test key-based login, then run:

```bash
sudo ./scripts/harden_server.sh
sudo ./scripts/harden_server.sh --apply
```

## Firewalld
Only `ssh` is allowed on the `public` zone. PostgreSQL (`9999/tcp`) stays bound to localhost.

## SELinux
The host runs in `Enforcing` mode (`getenforce`). Since PostgreSQL runs on custom port `9999`, allow it in SELinux policy:

```bash
sudo semanage port -a -t postgresql_port_t -p tcp 9999
```

If a service or backup path gets blocked:

```bash
sudo ausearch -m avc -ts recent
```

Fix the underlying file context (`semanage fcontext`, `restorecon`) or boolean (`setsebool -P`). Only drop to `setenforce 0` briefly to confirm SELinux is the cause, then switch back to `setenforce 1`.

## Air-gapped Test
After PostgreSQL and required packages are installed, disable the NAT adapter and verify external traffic fails while local SSH, PostgreSQL, backups and health checks keep working.
