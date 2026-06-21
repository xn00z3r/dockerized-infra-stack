#!/usr/bin/env bash
# Backup SeaweedFS — rsync data directory
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/seaweedfs/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

echo "  [seaweedfs] Syncing SeaweedFS data..."
rsync -az --delete \
    "${INFRA_ROOT}/seaweedfs/data/" \
    "${BACKUP_DIR}/"

echo "  [seaweedfs] Backup complete: ${BACKUP_DIR}/"
echo "  [seaweedfs] Size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
