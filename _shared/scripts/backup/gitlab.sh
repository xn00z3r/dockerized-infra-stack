#!/usr/bin/env bash
# Backup GitLab — gitlab-backup create (built-in, no downtime)
# PENTING: gitlab-secrets.json di-backup bersamaan — WAJIB untuk restore
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/gitlab/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

echo "  [gitlab] Running gitlab-backup create (BACKUP=${TIMESTAMP})..."
# Suppress verbose output, hanya tampilkan error
docker exec gitlab gitlab-backup create BACKUP="${TIMESTAMP}" 2>&1 | \
    grep -E "^(Creating|Warning|Error|done)" || true

# Cari file backup yang dibuat
# Format: TIMESTAMP_EPOCHTIME_gitlab_backup.tar
BACKUP_FILE=$(docker exec gitlab ls /var/opt/gitlab/backups/ 2>/dev/null | \
    grep "${TIMESTAMP}" | head -1)

if [ -z "${BACKUP_FILE}" ]; then
    echo "  [gitlab] ERROR: Backup file tidak ditemukan setelah gitlab-backup create"
    exit 1
fi

echo "  [gitlab] Copying backup: ${BACKUP_FILE}..."
docker cp "gitlab:/var/opt/gitlab/backups/${BACKUP_FILE}" "${BACKUP_DIR}/"

# WAJIB: backup gitlab-secrets.json bersamaan
# Tanpa file ini, backup TAR tidak bisa di-restore
if docker cp "gitlab:/etc/gitlab/gitlab-secrets.json" "${BACKUP_DIR}/" 2>/dev/null; then
    echo "  [gitlab] gitlab-secrets.json backed up OK"
else
    echo "  [gitlab] WARNING: gitlab-secrets.json tidak bisa di-copy."
    echo "  [gitlab] Manual backup: docker cp gitlab:/etc/gitlab/gitlab-secrets.json ${BACKUP_DIR}/"
fi

# Cleanup backup dari container (sudah ada di host)
docker exec gitlab rm -f "/var/opt/gitlab/backups/${BACKUP_FILE}" 2>/dev/null || true

echo "  [gitlab] Backup complete: ${BACKUP_DIR}/"
echo "  [gitlab] Size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
