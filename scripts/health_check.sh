#!/usr/bin/env bash
# System and PostgreSQL health check for bastion-pg-ops
# Exit codes: 0=OK, 1=WARN, 2=CRIT

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
    (( level > STATUS )) && STATUS="${level}"
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

    # Warn if 1-minute load exceeds core count
    if awk -v l="${load1}" -v c="${cores}" 'BEGIN { exit !(l > c) }'; then
        report WARN "CPU load (1m): ${load1} (${cores} cores)"
        set_status 1
    else
        report OK "CPU load (1m): ${load1} (${cores} cores)"
    fi
}

check_memory() {
    local pct
    pct="$(free | awk '/^Mem:/ { printf "%.0f", ($3 / $2) * 100 }')"

    if (( pct >= MEM_CRIT )); then
        report CRIT "Memory usage: ${pct}%"
        set_status 2
    elif (( pct >= MEM_WARN )); then
        report WARN "Memory usage: ${pct}%"
        set_status 1
    else
        report OK "Memory usage: ${pct}%"
    fi
}

check_disk() {
    local pct
    pct="$(df -P / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"

    if (( pct >= DISK_CRIT )); then
        report CRIT "Disk usage (/): ${pct}%"
        set_status 2
    elif (( pct >= DISK_WARN )); then
        report WARN "Disk usage (/): ${pct}%"
        set_status 1
    else
        report OK "Disk usage (/): ${pct}%"
    fi
}

check_postgres() {
    if ! systemctl is-active --quiet postgresql; then
        report CRIT "PostgreSQL service is not active"
        set_status 2
        return
    fi

    if pg_isready -q -h "${PG_HOST}" -p "${PG_PORT}"; then
        report OK "PostgreSQL accepting connections on ${PG_HOST}:${PG_PORT}"
    else
        report CRIT "PostgreSQL service is running but not ready on ${PG_HOST}:${PG_PORT}"
        set_status 2
        return
    fi

    # Query active connection count via local socket (requires postgres or root/sudo)
    local conns=""
    if [[ "${USER:-}" == "postgres" ]]; then
        conns="$(psql -p "${PG_PORT}" -d postgres -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || true)"
    elif [[ "${EUID}" -eq 0 ]]; then
        conns="$(sudo -u postgres psql -p "${PG_PORT}" -d postgres -tAc "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || true)"
    fi

    if [[ -n "${conns}" ]]; then
        if (( conns >= PG_CONN_WARN )); then
            report WARN "PostgreSQL active connections: ${conns} (warn >= ${PG_CONN_WARN})"
            set_status 1
        else
            report OK "PostgreSQL active connections: ${conns}"
        fi
    else
        report WARN "PostgreSQL active connections: skipped (run as root or postgres to query pg_stat_activity)"
        set_status 1
    fi
}

check_last_backup() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        report CRIT "Backup directory missing: ${BACKUP_DIR}"
        set_status 2
        return
    fi

    local latest
    latest="$(ls -t "${BACKUP_DIR}"/*.dump 2>/dev/null | head -n 1 || true)"

    if [[ -z "${latest}" ]]; then
        report CRIT "No backup .dump files found in ${BACKUP_DIR}"
        set_status 2
        return
    fi

    local now mtime age_hours size
    now="$(date +%s)"
    mtime="$(stat -c %Y "${latest}")"
    age_hours="$(( (now - mtime) / 3600 ))"
    size="$(du -h "${latest}" | awk '{print $1}')"

    if (( age_hours > BACKUP_MAX_AGE_HOURS )); then
        report WARN "Last backup is ${age_hours}h old (max ${BACKUP_MAX_AGE_HOURS}h): $(basename "${latest}") (${size})"
        set_status 1
    else
        report OK "Last backup: $(basename "${latest}") (${size}, ${age_hours}h ago)"
    fi
}

check_selinux() {
    if ! command -v getenforce >/dev/null 2>&1; then
        report WARN "SELinux tools not installed"
        set_status 1
        return
    fi

    local mode
    mode="$(getenforce)"
    if [[ "${mode}" == "Enforcing" ]]; then
        report OK "SELinux mode: Enforcing"
    else
        report CRIT "SELinux mode is ${mode} (expected Enforcing)"
        set_status 2
    fi
}

check_recent_errors() {
    local err_count
    err_count="$(journalctl -p err --since "1 hour ago" --no-pager -q 2>/dev/null | wc -l || echo 0)"
    if (( err_count > 0 )); then
        report WARN "System journal has ${err_count} error line(s) in the last hour"
        set_status 1
    else
        report OK "No system journal errors in the last hour"
    fi
}

echo "=== bastion-pg-ops health check ($(date '+%Y-%m-%d %H:%M:%S')) ==="
check_cpu
check_memory
check_disk
check_postgres
check_last_backup
check_selinux
check_recent_errors

exit "${STATUS}"
