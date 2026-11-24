#!/usr/bin/env bash
# Automated PostgreSQL backup with logging, sha256 checksum, and retention cleanup
# Usage: sudo -u postgres ./scripts/pg_backup.sh

set -euo pipefail

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-9999}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-bastion_ops}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/bastion-pg}"
LOG_FILE="${LOG_FILE:-/var/log/bastion-pg/backup.log}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DUMP_FILE="${BACKUP_DIR}/${PG_DB}_${TIMESTAMP}.dump"
CHECKSUM_FILE="${DUMP_FILE}.sha256"

mkdir -p "${BACKUP_DIR}" "$(dirname "${LOG_FILE}")"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

on_error() {
    log "ERROR: backup failed for database '${PG_DB}' (port ${PG_PORT})"
    # Remove partial dump if pg_dump failed mid-way
    rm -f "${DUMP_FILE}" "${CHECKSUM_FILE}"
    exit 1
}
trap on_error ERR

log "START: backing up database '${PG_DB}' on ${PG_HOST}:${PG_PORT}"

# Custom format (-Fc) gives built-in compression and supports pg_restore
pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -Fc -f "${DUMP_FILE}" "${PG_DB}"

if [[ ! -s "${DUMP_FILE}" ]]; then
    log "ERROR: dump file is empty: ${DUMP_FILE}"
    exit 1
fi

sha256sum "${DUMP_FILE}" > "${CHECKSUM_FILE}"
SIZE="$(du -h "${DUMP_FILE}" | awk '{print $1}')"
log "OK: backup created -> ${DUMP_FILE} (${SIZE})"

# Clean up backups older than RETENTION_DAYS
REMOVED="$(find "${BACKUP_DIR}" -type f \( -name "${PG_DB}_*.dump" -o -name "${PG_DB}_*.dump.sha256" \) -mtime +"${RETENTION_DAYS}" -print -delete | wc -l)"
if (( REMOVED > 0 )); then
    log "CLEANUP: removed ${REMOVED} expired file(s) older than ${RETENTION_DAYS} days"
fi
