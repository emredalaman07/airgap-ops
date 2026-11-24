#!/usr/bin/env bash
# Install and configure PostgreSQL on RHEL/Rocky/AlmaLinux 9 (port 9999, localhost only)
# Usage: sudo ./scripts/setup_postgres.sh [--apply]  (dry-run by default)

set -euo pipefail

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

PG_PORT="${PG_PORT:-9999}"
PG_DATA="/var/lib/pgsql/data"
PG_CONF="${PG_DATA}/postgresql.conf"
PG_HBA="${PG_DATA}/pg_hba.conf"

if [[ "${EUID}" -ne 0 ]]; then
    echo "run as root" >&2
    exit 1
fi

install_packages() {
    if rpm -q postgresql-server >/dev/null 2>&1; then
        echo "postgresql-server already installed"
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
        echo "cluster already initialized at ${PG_DATA}"
        return 0
    fi

    if (( APPLY )); then
        postgresql-setup --initdb
    else
        echo "[dry-run] postgresql-setup --initdb"
    fi
}

configure_selinux_port() {
    # Non-default ports need to be labeled for postgresql_port_t under Enforcing mode
    if semanage port -l | grep -qE "postgresql_port_t.*\b${PG_PORT}\b"; then
        echo "selinux port ${PG_PORT} already allowed for postgresql_port_t"
        return 0
    fi

    if (( APPLY )); then
        semanage port -a -t postgresql_port_t -p tcp "${PG_PORT}"
        echo "allowed tcp/${PG_PORT} in selinux postgresql_port_t"
    else
        echo "[dry-run] semanage port -a -t postgresql_port_t -p tcp ${PG_PORT}"
    fi
}

configure_postgres() {
    if (( APPLY )); then
        # Bind to localhost only and use custom port
        sed -i -E "s|^#?listen_addresses\s*=.*|listen_addresses = 'localhost'|" "${PG_CONF}"
        sed -i -E "s|^#?port\s*=.*|port = ${PG_PORT}|" "${PG_CONF}"

        # Enforce scram-sha-256 for local TCP connections
        sed -i -E 's|^(host\s+all\s+all\s+127\.0\.0\.1/32\s+).*|\1scram-sha-256|' "${PG_HBA}"
        sed -i -E 's|^(host\s+all\s+all\s+::1/128\s+).*|\1scram-sha-256|' "${PG_HBA}"

        systemctl enable --now postgresql
        systemctl restart postgresql
        echo "postgresql running on localhost:${PG_PORT}"
    else
        echo "[dry-run] set listen_addresses='localhost', port=${PG_PORT}, scram-sha-256 in pg_hba.conf and restart postgresql"
    fi
}

install_packages
init_cluster
configure_selinux_port
configure_postgres
