#!/usr/bin/env bash
# Backup Traefik — acme.json (TLS certs) + config
set -euo pipefail

TIMESTAMP="${1:?ERROR: timestamp required}"
BACKUP_DIR="/data/backups/traefik/${TIMESTAMP}"
INFRA_ROOT="${INFRA_STACK_ROOT:-/data/infra-stack}"

mkdir -p "${BACKUP_DIR}"

echo "  [traefik] Backing up acme.json..."
if [ -f "${INFRA_ROOT}/traefik/data/acme.json" ]; then
    cp "${INFRA_ROOT}/traefik/data/acme.json" "${BACKUP_DIR}/acme.json"
    chmod 600 "${BACKUP_DIR}/acme.json"
else
    echo "  [traefik] WARNING: acme.json tidak ditemukan — mungkin Traefik belum pernah start"
fi

echo "  [traefik] Backing up config..."
rsync -az \
    --exclude="auth/htpasswd" \
    "${INFRA_ROOT}/traefik/config/" \
    "${BACKUP_DIR}/config/" 2>/dev/null || true

echo "  [traefik] Backup complete: ${BACKUP_DIR}/"
