#!/usr/bin/env bash
# Backup MySQL — mysqldump semua database, no downtime
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/mysql/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

if [ ! -f "${INFRA_ROOT}/_shared/.env" ]; then
    echo "  [mysql] ERROR: ${INFRA_ROOT}/_shared/.env tidak ditemukan"
    exit 1
fi
set -a; source "${INFRA_ROOT}/_shared/.env"; set +a

echo "  [mysql] Backing up all databases..."
docker exec mysql mysqldump \
    -u root \
    -p"${MYSQL_ROOT_PASSWORD}" \
    --all-databases \
    --single-transaction \
    --quick \
    --lock-tables=false | \
    gzip > "${BACKUP_DIR}/all-databases.sql.gz"

echo "  [mysql] Backup complete: ${BACKUP_DIR}/all-databases.sql.gz"
echo "  [mysql] Size: $(du -sh "${BACKUP_DIR}/all-databases.sql.gz" | cut -f1)"
