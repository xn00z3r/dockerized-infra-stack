#!/usr/bin/env bash
# Backup step-ca — rsync CA data (private keys, certs, config, db)
# PENTING: CA private keys ada di sini — backup ini sangat sensitif
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/step-ca/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

echo "  [step-ca] Syncing step-ca data (CA keys & certs)..."
rsync -az \
    "${INFRA_ROOT}/step-ca/data/" \
    "${BACKUP_DIR}/data/"

# Backup config (root_ca.crt)
if [ -d "${INFRA_ROOT}/step-ca/config" ]; then
    rsync -az \
        "${INFRA_ROOT}/step-ca/config/" \
        "${BACKUP_DIR}/config/"
fi

# Set restrictive permissions — backup berisi private keys
chmod -R 600 "${BACKUP_DIR}" 2>/dev/null || true
chmod 700 "${BACKUP_DIR}" 2>/dev/null || true

echo "  [step-ca] Backup complete: ${BACKUP_DIR}/"
echo "  [step-ca] PENTING: Backup ini berisi CA private keys — simpan di tempat aman"
