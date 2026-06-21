#!/usr/bin/env bash
# =============================================================================
# create-networks.sh
# Membuat semua Docker networks yang dibutuhkan infra-stack
# Idempotent: aman dijalankan berkali-kali (skip jika sudah ada)
# =============================================================================
set -euo pipefail

create_network() {
    local name="$1"
    local subnet="$2"
    if docker network inspect "${name}" > /dev/null 2>&1; then
        echo "    Network '${name}' already exists — skip."
    else
        docker network create \
            --driver bridge \
            --subnet "${subnet}" \
            "${name}"
        echo "    Network '${name}' created (subnet: ${subnet})."
    fi
}

echo "==> Creating Docker networks..."
create_network "infra-proxy-net"   "172.20.0.0/24"
create_network "infra-backend-net" "172.20.1.0/24"
create_network "infra-devops-net"  "172.20.2.0/24"
echo "==> All networks ready."
