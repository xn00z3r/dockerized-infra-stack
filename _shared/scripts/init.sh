#!/usr/bin/env bash
# =============================================================================
# INFRA-STACK init.sh — dipanggil oleh: make init
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

echo "==> [init] Working directory: ${ROOT_DIR}"

# -----------------------------------------------------------------------------
# STEP 1: Validasi & render .env.template
# -----------------------------------------------------------------------------
echo "==> [init] Step 1/6: Validating and rendering .env.template..."

[ ! -f "_shared/.env.template" ] && { echo "ERROR: _shared/.env.template tidak ditemukan."; exit 1; }

# B02 FIX: Beberapa variabel di .env.template mereferensi variabel lain
# (contoh: STEPCA_DNS=ca.${BASE_DOMAIN},localhost)
# envsubst menggunakan SHELL environment — kita harus export vars dari template DULU
# sebelum envsubst dijalankan, agar self-referential vars ter-substitusi dengan benar.
#
# Ekstrak semua KEY=VALUE sederhana (baris tanpa ${...} sebagai nilai):
while IFS='=' read -r key value; do
    # Skip komentar dan baris kosong
    [[ "${key}" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${key}" ]] && continue
    # Skip baris yang nilainya mengandung ${...} (referensi ke var lain)
    [[ "${value}" =~ \$\{ ]] && continue
    # Export var ke shell environment
    key=$(echo "${key}" | tr -d '[:space:]')
    value=$(echo "${value}" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
    export "${key}=${value}" 2>/dev/null || true
done < _shared/.env.template

# Sekarang envsubst bisa substitusi ${BASE_DOMAIN} dll dengan benar
envsubst < _shared/.env.template > _shared/.env.tmp

# Validasi: tidak ada GANTI_* yang tersisa
if grep -E 'GANTI_' _shared/.env.tmp > /dev/null 2>&1; then
    echo "ERROR: Masih ada placeholder 'GANTI_*' yang belum diisi di _shared/.env.template:"
    grep -E 'GANTI_' _shared/.env.tmp | sed 's/^/         /'
    rm -f _shared/.env.tmp
    exit 1
fi

mv _shared/.env.tmp _shared/.env
echo "    _shared/.env rendered OK"

# Load full environment dari rendered .env
set -a; source _shared/.env; set +a

# -----------------------------------------------------------------------------
# STEP 2: Render semua config templates
# -----------------------------------------------------------------------------
echo "==> [init] Step 2/6: Rendering config templates..."

if [ -f "traefik/config/traefik.yml.template" ]; then
    envsubst < traefik/config/traefik.yml.template > traefik/config/traefik.yml
    echo "    traefik/config/traefik.yml rendered OK"
fi

if [ -f "seaweedfs/config/s3.json.template" ]; then
    envsubst < seaweedfs/config/s3.json.template > seaweedfs/config/s3.json
    echo "    seaweedfs/config/s3.json rendered OK"
fi

if [ -f "postgresql/initdb/01-gitlab.sql.template" ]; then
    envsubst < postgresql/initdb/01-gitlab.sql.template > postgresql/initdb/01-gitlab.sql
    echo "    postgresql/initdb/01-gitlab.sql rendered OK"
fi

# -----------------------------------------------------------------------------
# STEP 3: Generate Traefik htpasswd
# -----------------------------------------------------------------------------
echo "==> [init] Step 3/6: Generating Traefik basic auth credentials..."
mkdir -p traefik/config/auth
HTPASSWD_ENTRY=$(openssl passwd -apr1 "${TRAEFIK_ADMIN_PASSWORD}")
echo "${TRAEFIK_ADMIN_USER}:${HTPASSWD_ENTRY}" > traefik/config/auth/htpasswd
echo "    traefik/config/auth/htpasswd generated OK"

# -----------------------------------------------------------------------------
# STEP 4: Setup acme.json (WAJIB chmod 600)
# -----------------------------------------------------------------------------
echo "==> [init] Step 4/6: Setting up acme.json..."
mkdir -p traefik/data
touch traefik/data/acme.json
chmod 600 traefik/data/acme.json
touch traefik/data/access.log
echo "    traefik/data/acme.json: chmod 600 OK"

# -----------------------------------------------------------------------------
# STEP 5: Buat semua direktori data
# -----------------------------------------------------------------------------
echo "==> [init] Step 5/6: Creating data directories..."
mkdir -p step-ca/data step-ca/config
mkdir -p traefik/config/certs
mkdir -p vault/data
mkdir -p postgresql/data mysql/data seaweedfs/data postfix/data
mkdir -p gitlab/config gitlab/data gitlab/logs
mkdir -p gitlab-runner/config gitlab-runner/data
echo "    All data directories created"

# -----------------------------------------------------------------------------
# STEP 6: Git init
# -----------------------------------------------------------------------------
echo "==> [init] Step 6/6: Setting up git repository..."
if [ ! -d ".git" ]; then
    git init

    # B10 FIX: Set git identity jika belum dikonfigurasi secara global
    if ! git config user.email > /dev/null 2>&1; then
        git config user.email "infra-stack@${BASE_DOMAIN}"
        git config user.name "Infra Stack"
        echo "    Git user configured: infra-stack@${BASE_DOMAIN}"
    fi

    # Add hanya file yang tidak di-gitignore
    git add \
        .gitignore README.md Makefile \
        _shared/.env.template \
        _shared/networks/README.md \
        _shared/scripts/ \
        _shared/docs/ \
        step-ca/docker-compose.yml step-ca/.env.template step-ca/README.md \
        traefik/docker-compose.yml traefik/.env.template traefik/README.md \
        traefik/config/traefik.yml.template traefik/config/dynamic/ \
        vault/docker-compose.yml vault/.env.template vault/config/ vault/README.md \
        postgresql/docker-compose.yml postgresql/.env.template postgresql/README.md \
        postgresql/initdb/01-gitlab.sql.template postgresql/initdb/99-extensions.sql \
        mysql/docker-compose.yml mysql/.env.template mysql/config/ \
        mysql/initdb/ mysql/README.md \
        seaweedfs/docker-compose.yml seaweedfs/.env.template \
        seaweedfs/config/s3.json.template seaweedfs/README.md \
        postfix/docker-compose.yml postfix/.env.template postfix/README.md \
        gitlab/docker-compose.yml gitlab/.env.template gitlab/README.md \
        gitlab-runner/docker-compose.yml gitlab-runner/.env.template gitlab-runner/README.md \
        2>/dev/null || true

    git commit -m "chore: initial infra-stack scaffold" 2>/dev/null || \
        echo "    WARNING: git commit failed — configure git user.email/name manually if needed"
    echo "    Git repository initialized."
else
    echo "    Git repository already exists. Skipping init."
fi

echo ""
echo "==> [init] Initialization complete!"
echo "    Next: ikuti Bootstrap Sequence Section 8 (INFRA-STACK-MASTER-REFERENCE.md)"
echo "    Or for normal ops: make up"
