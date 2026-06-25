#!/usr/bin/env bash
# =============================================================================
# PostgreSQL Backup Verification — create sentinel, backup, purge, restore, verify
# =============================================================================

set -euo pipefail

INFRA_ROOT="${INFRA_STACK_ROOT:-$(pwd)}"
cd "${INFRA_ROOT}"

if [ ! -f "_shared/.env" ]; then
    echo "ERROR: _shared/.env tidak ditemukan. Jalankan make init dulu."
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "_shared/.env"
set +a

BACKUP_TS="$(date +%Y-%m-%d_%H-%M-%S)"
VERIFY_ID="$(date +%s)"
BACKUP_DIR="/data/backups/postgresql/${BACKUP_TS}"

echo ""
echo "======================================================"
echo " PostgreSQL Backup Verification"
echo "======================================================"
echo ""

echo "[1/6] Creating verification record..."

docker exec postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE IF NOT EXISTS backup_validation (
    id BIGINT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO backup_validation (id)
VALUES (${VERIFY_ID})
ON CONFLICT (id) DO NOTHING;
SQL

echo "Verification ID = ${VERIFY_ID}"

echo ""
echo "[2/6] Running backup..."
bash _shared/scripts/backup/postgresql.sh "${BACKUP_TS}"

SHA256="$(awk '{print $1}' "${BACKUP_DIR}/sha256.txt")"

cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "backup_id": "${BACKUP_TS}",
  "service": "postgresql",
  "database": "${GITLAB_DB_NAME}",
  "created_at": "$(date -Iseconds)",
  "verify_id": "${VERIFY_ID}",
  "dump_file": "${GITLAB_DB_NAME}.sql.gz",
  "sha256": "${SHA256}"
}
EOF

echo ""
echo "[3/6] Purging PostgreSQL..."
make purge-postgresql

echo ""
echo "[4/6] Recreating PostgreSQL..."
docker compose \
  --env-file _shared/.env \
  -f postgresql/docker-compose.yml \
  up -d

echo "Waiting for PostgreSQL healthy..."
bash _shared/scripts/wait-healthy.sh postgresql 120
echo "PostgreSQL healthy"

echo ""
echo "[5/6] Restoring backup..."
bash _shared/scripts/backup/restore-postgresql.sh "${BACKUP_TS}"

echo ""
echo "[6/6] Verifying restored data..."
RESULT="$(
    docker exec postgresql psql \
      -U "${POSTGRES_USER}" \
      -d "${GITLAB_DB_NAME}" \
      -tAc "SELECT COUNT(*) FROM backup_validation WHERE id=${VERIFY_ID};" \
      | tr -d '[:space:]'
)"

if [ "${RESULT}" = "1" ]; then
    cat > "${BACKUP_DIR}/verification-report.json" <<EOF
{
  "status": "PASS",
  "backup_id": "${BACKUP_TS}",
  "verify_id": "${VERIFY_ID}",
  "verified_at": "$(date -Iseconds)"
}
EOF

    # Optional cleanup: hapus sentinel dari live DB setelah verification selesai
    docker exec postgresql psql \
      -U "${POSTGRES_USER}" \
      -d "${GITLAB_DB_NAME}" \
      -v ON_ERROR_STOP=1 \
      -c "DROP TABLE IF EXISTS backup_validation;"

    echo ""
    echo "========================================"
    echo "PASS"
    echo "Backup restore validation successful"
    echo "Backup ID       : ${BACKUP_TS}"
    echo "Verification ID : ${VERIFY_ID}"
    echo "========================================"
else
    cat > "${BACKUP_DIR}/verification-report.json" <<EOF
{
  "status": "FAIL",
  "backup_id": "${BACKUP_TS}",
  "verify_id": "${VERIFY_ID}",
  "verified_at": "$(date -Iseconds)"
}
EOF

    echo ""
    echo "========================================"
    echo "FAIL"
    echo "Verification record missing after restore"
    echo "Backup ID       : ${BACKUP_TS}"
    echo "Verification ID : ${VERIFY_ID}"
    echo "========================================"
    exit 1
fi
