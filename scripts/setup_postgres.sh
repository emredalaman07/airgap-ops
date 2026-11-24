#!/usr/bin/env bash
# Install and configure PostgreSQL on Rocky/RHEL 9 (127.0.0.1:9999)
# Dry-run by default; pass --apply to make changes.

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
    APPLY=1
fi

PG_PORT="${PG_PORT:-9999}"
PG_DATA="/var/lib/pgsql/data"
PG_CONF="${PG_DATA}/postgresql.conf"
PG_HBA="${PG_DATA}/pg_hba.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "error: run with sudo/root" >&2
    exit 1
fi

install_packages() {
    if rpm -q postgresql-server policycoreutils-python-utils >/dev/null 2>&1; then
        echo "packages: postgresql-server and semanage already installed"
        return 0
    fi

    if (( APPLY )); then
        dnf install -y postgresql-server postgresql-contrib policycoreutils-python-utils
    else
        echo "[dry-run] dnf install -y postgresql-server postgresql-contrib policycoreutils-python-utils"
    fi
}

init_cluster() {
    if [[ -f "${PG_DATA}/PG_VERSION" ]]; then
        echo "postgres: cluster already initialized at ${PG_DATA}"
        return 0
    fi

    if (( APPLY )); then
        postgresql-setup --initdb
    else
        echo "[dry-run] postgresql-setup --initdb"
    fi
}

configure_selinux_port() {
    # Custom port 9999 must be labeled postgresql_port_t or systemd start will fail under Enforcing
    if command -v semanage >/dev/null 2>&1 && semanage port -l | grep -E "^postgresql_port_t\b" | grep -qw "${PG_PORT}"; then
        echo "selinux: tcp/${PG_PORT} already labeled postgresql_port_t"
        return 0
    fi

    if (( APPLY )); then
        semanage port -a -t postgresql_port_t -p tcp "${PG_PORT}"
        echo "selinux: added tcp/${PG_PORT} to postgresql_port_t"
    else
        echo "[dry-run] semanage port -a -t postgresql_port_t -p tcp ${PG_PORT}"
    fi
}

configure_postgres() {
    if (( APPLY )); then
        sed -i -E "s|^#?listen_addresses\s*=.*|listen_addresses = 'localhost'|" "${PG_CONF}"
        sed -i -E "s|^#?port\s*=.*|port = ${PG_PORT}|" "${PG_CONF}"

        # Keep local unix socket on peer auth for postgres maintenance scripts;
        # require scram-sha-256 on loopback TCP connections.
        sed -i -E 's|^(host\s+all\s+all\s+127\.0\.0\.1/32\s+).*|\1scram-sha-256|' "${PG_HBA}"
        sed -i -E 's|^(host\s+all\s+all\s+::1/128\s+).*|\1scram-sha-256|' "${PG_HBA}"

        systemctl enable --now postgresql
        systemctl restart postgresql
        echo "postgres: listening on localhost:${PG_PORT}"
    else
        echo "[dry-run] update postgresql.conf (localhost:${PG_PORT}), pg_hba.conf (scram-sha-256) and restart postgresql"
    fi
}

install_packages
init_cluster
configure_selinux_port
configure_postgres
