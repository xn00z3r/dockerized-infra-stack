#!/usr/bin/env bash
# =============================================================================
# PostgreSQL Backup — pg_dump per database, no downtime
# =============================================================================

set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"

BACKUP_DIR="/data/backups/postgresql/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

if [ ! -f "${INFRA_ROOT}/_shared/.env" ]; then
    echo "  [postgresql] ERROR: ${INFRA_ROOT}/_shared/.env tidak ditemukan"
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "${INFRA_ROOT}/_shared/.env"
set +a

echo "  [postgresql] Backing up database: ${GITLAB_DB_NAME}..."

docker exec postgresql pg_dump \
    -U "${POSTGRES_USER}" \
    --no-password \
    "${GITLAB_DB_NAME}" | \
    gzip > "${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz"

SHA256="$(sha256sum "${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz" | awk '{print $1}')"

cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "backup_id": "${TIMESTAMP}",
  "service": "postgresql",
  "database": "${GITLAB_DB_NAME}",
  "created_at": "$(date -Iseconds)",
  "dump_file": "${GITLAB_DB_NAME}.sql.gz",
  "sha256": "${SHA256}"
}
EOF

echo "${SHA256}  ${GITLAB_DB_NAME}.sql.gz" > "${BACKUP_DIR}/sha256.txt"

echo "  [postgresql] Backup complete: ${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz"
echo "  [postgresql] Size: $(du -sh "${BACKUP_DIR}/${GITLAB_DB_NAME}.sql.gz" | cut -f1)"
echo "  [postgresql] SHA256: ${SHA256}"
