#!/usr/bin/env bash
# Verify sha256 (if present) and restore a custom-format dump into a target DB.
# Defaults to airgap_ops_restore_test so the main DB is not overwritten by mistake.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <dump_file> [target_db]" >&2
    exit 1
fi

# Resolve dump path before switching working directory
DUMP_FILE="$(realpath "$1")"
TARGET_DB="${2:-airgap_ops_restore_test}"

cd /

PG_HOST="${PG_HOST:-}"
PG_PORT="${PG_PORT:-9999}"
PG_USER="${PG_USER:-postgres}"
LOG_FILE="${LOG_FILE:-/var/log/airgap-db/restore.log}"

mkdir -p "$(dirname "${LOG_FILE}")"

PG_CONN_ARGS=(-p "${PG_PORT}" -U "${PG_USER}")
if [[ -n "${PG_HOST}" ]]; then
    PG_CONN_ARGS+=(-h "${PG_HOST}")
fi

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"
}

if [[ ! -f "${DUMP_FILE}" ]]; then
    log "error: dump file not found: ${DUMP_FILE}"
    exit 1
fi

if [[ -f "${DUMP_FILE}.sha256" ]]; then
    if ! (cd "$(dirname "${DUMP_FILE}")" && sha256sum -c "$(basename "${DUMP_FILE}").sha256" >/dev/null); then
        log "error: sha256 mismatch for ${DUMP_FILE}"
        exit 1
    fi
    log "checksum verified: $(basename "${DUMP_FILE}")"
else
    log "warn: ${DUMP_FILE}.sha256 not found, skipping checksum check"
fi

log "restoring $(basename "${DUMP_FILE}") into ${TARGET_DB} (port ${PG_PORT})"

psql "${PG_CONN_ARGS[@]}" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"${TARGET_DB}\";" \
    -c "CREATE DATABASE \"${TARGET_DB}\";" >/dev/null

pg_restore "${PG_CONN_ARGS[@]}" -d "${TARGET_DB}" \
    --no-owner --exit-on-error "${DUMP_FILE}"

COUNTS="$(psql "${PG_CONN_ARGS[@]}" -d "${TARGET_DB}" -tAc "
    SELECT 'assets=' || (SELECT count(*) FROM ops.assets)
        || ', maintenance_logs=' || (SELECT count(*) FROM ops.maintenance_logs)
        || ', audit_events=' || (SELECT count(*) FROM ops.audit_events);
")"

log "restore ok: ${TARGET_DB} (${COUNTS})"
