#!/usr/bin/env bash
# =============================================================================
# PostgreSQL Restore — restore one database from pg_dump gzip
# =============================================================================

set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"

INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

if [ ! -f "${INFRA_ROOT}/_shared/.env" ]; then
    echo "  [postgresql] ERROR: ${INFRA_ROOT}/_shared/.env tidak ditemukan"
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "${INFRA_ROOT}/_shared/.env"
set +a

BACKUP_FILE="/data/backups/postgresql/${TIMESTAMP}/${GITLAB_DB_NAME}.sql.gz"
SHA_FILE="/data/backups/postgresql/${TIMESTAMP}/sha256.txt"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "  [postgresql] ERROR: backup file tidak ditemukan: ${BACKUP_FILE}"
    exit 1
fi

if [ ! -f "${SHA_FILE}" ]; then
    echo "  [postgresql] ERROR: sha256 file tidak ditemukan: ${SHA_FILE}"
    exit 1
fi

EXPECTED_SHA256="$(awk '{print $1}' "${SHA_FILE}")"
ACTUAL_SHA256="$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')"

if [ "${EXPECTED_SHA256}" != "${ACTUAL_SHA256}" ]; then
    echo "  [postgresql] ERROR: SHA256 mismatch"
    echo "  [postgresql] Expected: ${EXPECTED_SHA256}"
    echo "  [postgresql] Actual  : ${ACTUAL_SHA256}"
    exit 1
fi

echo "  [postgresql] Restoring database: ${GITLAB_DB_NAME}..."
gunzip -c "${BACKUP_FILE}" | \
docker exec -i postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    --no-psqlrc \
    -v ON_ERROR_STOP=1

echo "  [postgresql] Restore complete: ${BACKUP_FILE}"
