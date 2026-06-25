#!/usr/bin/env bash
set -euo pipefail

BACKUP_TIMESTAMP="${1:?backup timestamp required}"

BACKUP_FILE="/data/backups/mysql/${BACKUP_TIMESTAMP}/all-databases.sql.gz"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "ERROR: backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "==> Restoring MySQL backup..."

gunzip -c "${BACKUP_FILE}" | \
docker exec -i mysql \
    sh -c 'exec mysql -u root -p"$MYSQL_ROOT_PASSWORD"'

echo "==> Restore complete."
