#!/usr/bin/env bash
# Host and PostgreSQL health check
# Exit codes: 0 = ok, 1 = warn, 2 = crit

set -euo pipefail

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-9999}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/bastion-pg}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"

MEM_WARN="${MEM_WARN:-80}"
MEM_CRIT="${MEM_CRIT:-90}"
DISK_WARN="${DISK_WARN:-80}"
DISK_CRIT="${DISK_CRIT:-90}"
PG_CONN_WARN="${PG_CONN_WARN:-50}"

STATUS=0

set_status() {
    local level="$1"
    if (( level > STATUS )); then
        STATUS="${level}"
    fi
}

report() {
    local tag="$1"
    shift
    printf '[%-4s] %s\n' "${tag}" "$*"
}

check_cpu() {
    local cores load1
    cores="$(nproc)"
    load1="$(awk '{print $1}' /proc/loadavg)"

    if awk -v l="${load1}" -v c="${cores}" 'BEGIN { exit !(l > c) }'; then
        report WARN "cpu load (1m): ${load1} (${cores} cores)"
        set_status 1
    else
        report OK "cpu load (1m): ${load1} (${cores} cores)"
    fi
}

check_memory() {
    local pct
    pct="$(free | awk '/^Mem:/ { printf "%.0f", ($3 / $2) * 100 }')"

    if (( pct >= MEM_CRIT )); then
        report CRIT "memory usage: ${pct}%"
        set_status 2
    elif (( pct >= MEM_WARN )); then
        report WARN "memory usage: ${pct}%"
        set_status 1
    else
        report OK "memory usage: ${pct}%"
    fi
}

check_disk() {
    local pct
    pct="$(df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"

    if (( pct >= DISK_CRIT )); then
        report CRIT "disk usage (/): ${pct}%"
        set_status 2
    elif (( pct >= DISK_WARN )); then
        report WARN "disk usage (/): ${pct}%"
        set_status 1
    else
        report OK "disk usage (/): ${pct}%"
    fi
}

check_postgres() {
    if ! systemctl is-active --quiet postgresql; then
        report CRIT "postgresql service is down"
        set_status 2
        return
    fi

    if pg_isready -q -h "${PG_HOST}" -p "${PG_PORT}"; then
        report OK "postgresql ready on ${PG_HOST}:${PG_PORT}"
    else
        report CRIT "postgresql running but not accepting connections on ${PG_HOST}:${PG_PORT}"
        set_status 2
        return
    fi

    local conns=""
    if [[ "${USER:-}" == "postgres" ]]; then
        conns="$(cd / && psql -p "${PG_PORT}" -d postgres -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || true)"
    elif [[ "${EUID}" -eq 0 ]]; then
        conns="$(cd / && sudo -u postgres psql -p "${PG_PORT}" -d postgres -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || true)"
    fi

    if [[ -n "${conns}" ]]; then
        if (( conns >= PG_CONN_WARN )); then
            report WARN "active connections: ${conns} (warn >= ${PG_CONN_WARN})"
            set_status 1
        else
            report OK "active connections: ${conns}"
        fi
    else
        report WARN "active connections: skipped (run with sudo to query pg_stat_activity)"
        set_status 1
    fi
}

check_last_backup() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        report CRIT "backup dir missing: ${BACKUP_DIR}"
        set_status 2
        return
    fi

    local latest=""
    latest="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2- || true)"

    if [[ -z "${latest}" ]]; then
        report CRIT "no .dump files in ${BACKUP_DIR}"
        set_status 2
        return
    fi

    local now mtime age_hours size
    now="$(date +%s)"
    mtime="$(stat -c %Y "${latest}")"
    age_hours="$(( (now - mtime) / 3600 ))"
    size="$(du -h "${latest}" | awk '{print $1}')"

    if (( age_hours > BACKUP_MAX_AGE_HOURS )); then
        report WARN "last backup is ${age_hours}h old (max ${BACKUP_MAX_AGE_HOURS}h): $(basename "${latest}") (${size})"
        set_status 1
    else
        report OK "last backup: $(basename "${latest}") (${size}, ${age_hours}h ago)"
    fi
}

check_selinux() {
    if ! command -v getenforce >/dev/null 2>&1; then
        report WARN "getenforce not found"
        set_status 1
        return
    fi

    local mode
    mode="$(getenforce)"
    if [[ "${mode}" == "Enforcing" ]]; then
        report OK "selinux: Enforcing"
    else
        report CRIT "selinux: ${mode} (expected Enforcing)"
        set_status 2
    fi
}

check_journal() {
    local err_count
    err_count="$(journalctl -p err --since "1 hour ago" --no-pager -q 2>/dev/null | wc -l || echo 0)"
    if (( err_count > 0 )); then
        report WARN "journal errors (last 1h): ${err_count}"
        set_status 1
    else
        report OK "journal errors (last 1h): 0"
    fi
}

printf 'host: %s | %s\n' "$(hostname -s 2>/dev/null || hostname)" "$(date '+%Y-%m-%d %H:%M:%S')"
check_cpu
check_memory
check_disk
check_postgres
check_last_backup
check_selinux
check_journal

exit "${STATUS}"
