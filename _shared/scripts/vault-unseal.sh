#!/usr/bin/env bash
# =============================================================================
# vault-unseal.sh — Auto-unseal Vault setelah VM restart
# Dipanggil via cron @reboot:
#   @reboot sleep 30 && bash /data/infra-stack/_shared/scripts/vault-unseal.sh
# =============================================================================
set -euo pipefail

VAULT_UNSEAL_KEY_FILE="/etc/vault-unseal/unseal.key"
LOG_PREFIX="[vault-unseal] $(date '+%Y-%m-%d %H:%M:%S')"

echo "${LOG_PREFIX} Starting Vault unseal check..."

if [ ! -f "${VAULT_UNSEAL_KEY_FILE}" ]; then
    echo "${LOG_PREFIX} ERROR: Unseal key tidak ditemukan: ${VAULT_UNSEAL_KEY_FILE}"
    exit 1
fi

# Tunggu Vault container running (max 60 detik)
echo "${LOG_PREFIX} Waiting for Vault container..."
for i in $(seq 1 12); do
    if docker inspect vault > /dev/null 2>&1; then
        echo "${LOG_PREFIX} Vault container found."
        break
    fi
    [ "${i}" -eq 12 ] && { echo "${LOG_PREFIX} ERROR: container tidak ditemukan."; exit 1; }
    echo "${LOG_PREFIX} Attempt ${i}/12 — waiting 5s..."
    sleep 5
done

# B01 FIX: vault status exit code:
#   0 = initialized + unsealed (API responding)
#   1 = error (API not responding)
#   2 = initialized + sealed (API responding but sealed)
# Kita terima exit 0 DAN exit 2 sebagai "API sudah berjalan"
echo "${LOG_PREFIX} Waiting for Vault API to respond..."
API_READY=0
for i in $(seq 1 12); do
    EXIT_CODE=0
    docker exec vault vault status > /dev/null 2>&1 || EXIT_CODE=$?
    # Exit 0 (unsealed) atau exit 2 (sealed) = API ready
    if [ "${EXIT_CODE}" -eq 0 ] || [ "${EXIT_CODE}" -eq 2 ]; then
        echo "${LOG_PREFIX} Vault API is responding (exit code: ${EXIT_CODE})."
        API_READY=1
        break
    fi
    # Exit 1 = error, API belum ready
    echo "${LOG_PREFIX} Attempt ${i}/12 — API not ready yet (exit: ${EXIT_CODE}), waiting 5s..."
    sleep 5
done

[ "${API_READY}" -eq 0 ] && { echo "${LOG_PREFIX} ERROR: Vault API tidak merespons setelah 60 detik."; exit 1; }

# Cek sealed status — JANGAN pakai pipefail di sini karena vault status exit 2 saat sealed
SEALED_JSON=$(docker exec vault vault status -format=json 2>/dev/null || true)

if echo "${SEALED_JSON}" | grep -q '"sealed":true'; then
    echo "${LOG_PREFIX} Vault is sealed. Unsealing..."
    UNSEAL_KEY=$(cat "${VAULT_UNSEAL_KEY_FILE}")
    docker exec vault vault operator unseal "${UNSEAL_KEY}"
    echo "${LOG_PREFIX} Vault unsealed successfully."
elif echo "${SEALED_JSON}" | grep -q '"sealed":false'; then
    echo "${LOG_PREFIX} Vault is already unsealed. No action needed."
else
    echo "${LOG_PREFIX} WARNING: Cannot determine sealed status. JSON: ${SEALED_JSON}"
fi
