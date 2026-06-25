#!/usr/bin/env bash
# =============================================================================
# MySQL Backup
# =============================================================================

set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"

BACKUP_DIR="/data/backups/mysql/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

if [ ! -f "${INFRA_ROOT}/_shared/.env" ]; then
    echo "  [mysql] ERROR: ${INFRA_ROOT}/_shared/.env tidak ditemukan"
    exit 1
fi

set -a
source "${INFRA_ROOT}/_shared/.env"
set +a

echo "  [mysql] Backing up all databases..."

docker exec mysql mysqldump \
    -u root \
    -p"${MYSQL_ROOT_PASSWORD}" \
    --all-databases \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    --events \
    | gzip > "${BACKUP_DIR}/all-databases.sql.gz"

SHA256=$(sha256sum "${BACKUP_DIR}/all-databases.sql.gz" | awk '{print $1}')

cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "backup_id": "${TIMESTAMP}",
  "service": "mysql",
  "created_at": "$(date -Iseconds)",
  "mysql_container": "mysql",
  "dump_file": "all-databases.sql.gz",
  "sha256": "${SHA256}"
}
EOF

echo "${SHA256}  all-databases.sql.gz" \
    > "${BACKUP_DIR}/sha256.txt"

echo "  [mysql] Backup complete"
echo "  [mysql] Size   : $(du -sh "${BACKUP_DIR}/all-databases.sql.gz" | cut -f1)"
echo "  [mysql] SHA256 : ${SHA256}"
