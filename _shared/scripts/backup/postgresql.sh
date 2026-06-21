#!/usr/bin/env bash
# Backup PostgreSQL — pg_dump per database, no downtime
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/postgresql/${TIMESTAMP}"
# N06 FIX: Gunakan INFRA_STACK_ROOT dari Makefile environment, bukan hardcode
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

# Load env dari shared .env
if [ ! -f "${INFRA_ROOT}/_shared/.env" ]; then
    echo "  [postgresql] ERROR: ${INFRA_ROOT}/_shared/.env tidak ditemukan"
    exit 1
fi
set -a; source "${INFRA_ROOT}/_shared/.env"; set +a

echo "  [postgresql] Backing up database: ${GITLAB_DB_NAME}..."
docker exec postgresql pg_dump \
    -U "${POSTGRES_USER}" \
    --no-password \
    "${GITLAB_DB_NAME}" | \
    gzip > "${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz"

echo "  [postgresql] Backup complete: ${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz"
echo "  [postgresql] Size: $(du -sh "${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz" | cut -f1)"
