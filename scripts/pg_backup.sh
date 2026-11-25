#!/usr/bin/env bash
# Take a compressed pg_dump backup, write sha256 checksum, and prune old dumps.
# Intended to run as the postgres user (via peer auth over local unix socket).

set -euo pipefail

# Avoid "could not identify current directory" when invoked via sudo from /home/<user>
cd /

PG_HOST="${PG_HOST:-}"
PG_PORT="${PG_PORT:-9999}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-airgap_ops}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/airgap-db}"
LOG_FILE="${LOG_FILE:-/var/log/airgap-db/backup.log}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
DUMP_NAME="${PG_DB}_${TIMESTAMP}.dump"
DUMP_FILE="${BACKUP_DIR}/${DUMP_NAME}"
CHECKSUM_FILE="${DUMP_FILE}.sha256"

mkdir -p "${BACKUP_DIR}" "$(dirname "${LOG_FILE}")"

PG_CONN_ARGS=(-p "${PG_PORT}" -U "${PG_USER}")
if [[ -n "${PG_HOST}" ]]; then
    PG_CONN_ARGS+=(-h "${PG_HOST}")
fi

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"
}

cleanup_failed() {
    log "error: backup failed for ${PG_DB}"
    rm -f "${DUMP_FILE}" "${CHECKSUM_FILE}"
    exit 1
}
trap cleanup_failed ERR

log "starting backup for ${PG_DB} (port ${PG_PORT})"

pg_dump "${PG_CONN_ARGS[@]}" -Fc -f "${DUMP_FILE}" "${PG_DB}"

if [[ ! -s "${DUMP_FILE}" ]]; then
    log "error: dump file is empty: ${DUMP_FILE}"
    rm -f "${DUMP_FILE}"
    exit 1
fi

# Store relative filename in .sha256 so backups stay verifiable if moved
(
    cd "${BACKUP_DIR}"
    sha256sum "${DUMP_NAME}" > "${DUMP_NAME}.sha256"
)

SIZE="$(du -h "${DUMP_FILE}" | awk '{print $1}')"
log "backup finished: ${DUMP_FILE} (${SIZE})"

REMOVED="$(find "${BACKUP_DIR}" -type f \( -name "${PG_DB}_*.dump" -o -name "${PG_DB}_*.dump.sha256" \) -mtime +"${RETENTION_DAYS}" -print -delete | wc -l)"
if (( REMOVED > 0 )); then
    log "pruned ${REMOVED} file(s) older than ${RETENTION_DAYS} days"
fi
