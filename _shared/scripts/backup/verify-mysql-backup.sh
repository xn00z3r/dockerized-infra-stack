#!/usr/bin/env bash
# =============================================================================
# Verify MySQL Backup End-to-End
# =============================================================================

set -euo pipefail

INFRA_ROOT="${INFRA_STACK_ROOT:-$(pwd)}"

cd "${INFRA_ROOT}"

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
VERIFY_ID="$(date +%s)"

echo ""
echo "======================================================"
echo " MySQL Backup Verification"
echo "======================================================"
echo ""

echo "[1/6] Creating verification record..."

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    default_db \
    -e "
CREATE TABLE IF NOT EXISTS backup_validation (
    id BIGINT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO backup_validation(id)
VALUES (${VERIFY_ID});
"

echo "Verification ID = ${VERIFY_ID}"

echo ""
echo "[2/6] Running backup..."

bash _shared/scripts/backup/mysql.sh "${TIMESTAMP}"

BACKUP_DIR="/data/backups/mysql/${TIMESTAMP}"

jq \
    --arg verify_id "${VERIFY_ID}" \
    '. + {verify_id:$verify_id}' \
    "${BACKUP_DIR}/metadata.json" \
    > "${BACKUP_DIR}/metadata.tmp"

mv \
    "${BACKUP_DIR}/metadata.tmp" \
    "${BACKUP_DIR}/metadata.json"

echo ""
echo "[3/6] Purging MySQL..."

make purge-mysql

echo ""
echo "[4/6] Recreating MySQL..."

docker compose \
    --env-file _shared/.env \
    -f mysql/docker-compose.yml \
    up -d

echo "Waiting for MySQL healthy..."

until [ "$(docker inspect mysql --format '{{.State.Health.Status}}')" = "healthy" ]
do
    sleep 2
done

echo "MySQL healthy"

echo ""
echo "[5/6] Restoring backup..."

gunzip -c \
    "${BACKUP_DIR}/all-databases.sql.gz" \
    | docker exec -i mysql \
        mysql \
        -uroot \
        -p"${MYSQL_ROOT_PASSWORD}"

echo ""
echo "[6/6] Verifying restored data..."

RESULT=$(
docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "
SELECT COUNT(*)
FROM default_db.backup_validation
WHERE id=${VERIFY_ID};
"
)

REPORT="${BACKUP_DIR}/verification-report.json"

if [ "${RESULT}" = "1" ]; then

cat > "${REPORT}" <<EOF
{
  "status": "PASS",
  "verify_id": "${VERIFY_ID}",
  "verified_at": "$(date -Iseconds)"
}
EOF

    echo ""
    echo "========================================"
    echo "PASS"
    echo "Backup restore validation successful"
    echo "Verification ID : ${VERIFY_ID}"
    echo "========================================"

else

cat > "${REPORT}" <<EOF
{
  "status": "FAIL",
  "verify_id": "${VERIFY_ID}",
  "verified_at": "$(date -Iseconds)"
}
EOF

    echo ""
    echo "========================================"
    echo "FAIL"
    echo "Verification record missing"
    echo "========================================"

    exit 1

fi
