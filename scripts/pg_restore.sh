#!/usr/bin/env bash
# Verify and restore a PostgreSQL custom-format dump into a target database
# Usage: sudo -u postgres ./scripts/pg_restore.sh <dump_file> [target_db]

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <dump_file> [target_db]" >&2
    exit 1
fi

DUMP_FILE="$1"
# Default to a separate test database so production is not overwritten by accident
TARGET_DB="${2:-bastion_ops_restore_test}"

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-9999}"
PG_USER="${PG_USER:-postgres}"
LOG_FILE="${LOG_FILE:-/var/log/bastion-pg/restore.log}"

mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

if [[ ! -f "${DUMP_FILE}" ]]; then
    log "ERROR: dump file not found: ${DUMP_FILE}"
    exit 1
fi

# Verify checksum if a matching .sha256 file exists
if [[ -f "${DUMP_FILE}.sha256" ]]; then
    log "VERIFY: checking sha256 for ${DUMP_FILE}"
    if ! sha256sum -c "${DUMP_FILE}.sha256" >/dev/null; then
        log "ERROR: checksum mismatch for ${DUMP_FILE}"
        exit 1
    fi
    log "VERIFY: checksum OK"
else
    log "WARN: no .sha256 file found, skipping checksum check"
fi

log "START: restoring ${DUMP_FILE} into '${TARGET_DB}' (${PG_HOST}:${PG_PORT})"

# Recreate target database cleanly before restoring
psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"${TARGET_DB}\";" \
    -c "CREATE DATABASE \"${TARGET_DB}\";"

pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${TARGET_DB}" \
    --no-owner --exit-on-error "${DUMP_FILE}"

# Basic row-count check to confirm data came back intact
COUNTS="$(psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${TARGET_DB}" -tAc "
    SELECT 'assets=' || (SELECT count(*) FROM ops.assets)
        || ', maintenance_logs=' || (SELECT count(*) FROM ops.maintenance_logs)
        || ', audit_events=' || (SELECT count(*) FROM ops.audit_events);
")"

log "OK: restore completed into '${TARGET_DB}' (${COUNTS})"
