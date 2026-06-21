#!/usr/bin/env bash
# Backup Vault — raft snapshot (consistent point-in-time, no downtime)
# VAULT_TOKEN diperlukan untuk auth.
# Setup: simpan token di /etc/vault-unseal/vault-backup-token (chmod 400)
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/vault/${TIMESTAMP}"
VAULT_TOKEN_FILE="/etc/vault-unseal/vault-backup-token"

mkdir -p "${BACKUP_DIR}"

# Resolve VAULT_TOKEN
if [ -z "${VAULT_TOKEN:-}" ]; then
    if [ -f "${VAULT_TOKEN_FILE}" ]; then
        export VAULT_TOKEN=$(cat "${VAULT_TOKEN_FILE}")
        echo "  [vault] Using token from ${VAULT_TOKEN_FILE}"
    else
        echo "  [vault] WARNING: VAULT_TOKEN tidak tersedia."
        echo "  [vault] Setup: vault token create -policy=default -display-name=backup"
        echo "  [vault]        echo TOKEN | sudo tee ${VAULT_TOKEN_FILE} > /dev/null"
        echo "  [vault]        sudo chmod 400 ${VAULT_TOKEN_FILE}"
        echo "  [vault] Vault backup DILEWATI."
        exit 0
    fi
fi

# Verifikasi Vault tidak sealed sebelum snapshot
SEALED=$(docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault \
    vault status -format=json 2>/dev/null | grep -o '"sealed":[^,}]*' | cut -d: -f2 | tr -d ' ' || echo "true")

if [ "${SEALED}" = "true" ]; then
    echo "  [vault] WARNING: Vault is sealed — cannot take snapshot. Skipping."
    exit 0
fi

echo "  [vault] Taking Vault raft snapshot..."
SNAPSHOT_FILE="/tmp/vault-backup-${TIMESTAMP}.snap"

docker exec \
    -e VAULT_TOKEN="${VAULT_TOKEN}" \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    vault vault operator raft snapshot save "${SNAPSHOT_FILE}"

docker cp "vault:${SNAPSHOT_FILE}" "${BACKUP_DIR}/vault-${TIMESTAMP}.snap"
docker exec vault rm -f "${SNAPSHOT_FILE}" 2>/dev/null || true

echo "  [vault] Backup complete: ${BACKUP_DIR}/vault-${TIMESTAMP}.snap"
echo "  [vault] Size: $(du -sh "${BACKUP_DIR}/vault-${TIMESTAMP}.snap" | cut -f1)"
