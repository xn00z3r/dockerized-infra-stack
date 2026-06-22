#!/usr/bin/env bash
# =============================================================================
# INFRA-STACK init.sh — dipanggil oleh: make init
#
# Tujuan:
# - Render _shared/.env dari gabungan _shared/.env.template + _shared/.secrets.template
# - Validasi placeholder GANTI_* sudah tidak tersisa
# - Render template config lain
# - Generate Traefik basic auth
# - Siapkan acme.json dan data directories
# - Scaffold git init pertama kali secara deterministik
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

ENV_TEMPLATE="_shared/.env.template"
SECRETS_TEMPLATE="_shared/.secrets.template"
ENV_FILE="_shared/.env"
ENV_TMP="_shared/.env.tmp"

log() {
  printf '%s\n' "==> [init] $*"
}

info() {
  printf '%s\n' "    $*"
}

die() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

require_file() {
  local file="$1"
  [[ -f "$file" ]] || die "${file} tidak ditemukan."
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Command '${cmd}' tidak ditemukan. Install prerequisite terlebih dahulu."
}

validate_template_file() {
  local file="$1"
  local label="$2"

  # Hanya validasi baris assignment, abaikan komentar.
  # Jika masih ada GANTI_* di baris assignment, bootstrap harus gagal.
  if grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=.*GANTI_' "$file" >/dev/null 2>&1; then
    echo
    echo "ERROR: ${label} masih memiliki placeholder GANTI_* yang belum diisi:"
    grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=.*GANTI_' "$file" | sed 's/^/  /'
    echo
    die "${label} wajib dilengkapi sebelum menjalankan bootstrap."
  fi
}

render_env_template() {
  # Render hanya template config non-secret.
  # Secrets akan di-append apa adanya dari .secrets.template.
  envsubst < "$ENV_TEMPLATE" > "$ENV_TMP"
}

append_secrets_template() {
  printf '\n' >> "$ENV_TMP"
  cat "$SECRETS_TEMPLATE" >> "$ENV_TMP"
  printf '\n' >> "$ENV_TMP"
}

validate_final_env() {
  if grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=.*GANTI_' "$ENV_TMP" >/dev/null 2>&1; then
    echo
    echo "ERROR: Hasil render _shared/.env masih mengandung placeholder GANTI_*:"
    grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=.*GANTI_' "$ENV_TMP" | sed 's/^/  /'
    echo
    die "Lengkapi seluruh placeholder sebelum bootstrap."
  fi
}

log "Working directory: ${ROOT_DIR}"

# -----------------------------------------------------------------------------
# STEP 0: Prerequisite checks
# -----------------------------------------------------------------------------
log "Step 0/6: Checking prerequisites..."
require_command envsubst
require_command openssl
require_command git
require_file "$ENV_TEMPLATE"
require_file "$SECRETS_TEMPLATE"

validate_template_file "$ENV_TEMPLATE" "_shared/.env.template"
validate_template_file "$SECRETS_TEMPLATE" "_shared/.secrets.template"

# -----------------------------------------------------------------------------
# STEP 1: Render _shared/.env
# -----------------------------------------------------------------------------
log "Step 1/6: Rendering _shared/.env from templates..."

rm -f "$ENV_TMP"

render_env_template
append_secrets_template
validate_final_env

mv "$ENV_TMP" "$ENV_FILE"
info "_shared/.env rendered OK"

# Load merged environment for subsequent steps
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# -----------------------------------------------------------------------------
# STEP 2: Render config templates
# -----------------------------------------------------------------------------
log "Step 2/6: Rendering config templates..."

if [ -f "traefik/config/traefik.yml.template" ]; then
  envsubst < traefik/config/traefik.yml.template > traefik/config/traefik.yml
  info "traefik/config/traefik.yml rendered OK"
fi

if [ -f "seaweedfs/config/s3.json.template" ]; then
  envsubst < seaweedfs/config/s3.json.template > seaweedfs/config/s3.json
  info "seaweedfs/config/s3.json rendered OK"
fi

if [ -f "postgresql/initdb/01-gitlab.sql.template" ]; then
  envsubst < postgresql/initdb/01-gitlab.sql.template > postgresql/initdb/01-gitlab.sql
  info "postgresql/initdb/01-gitlab.sql rendered OK"
fi

# -----------------------------------------------------------------------------
# STEP 3: Generate Traefik htpasswd
# -----------------------------------------------------------------------------
log "Step 3/6: Generating Traefik basic auth credentials..."

[[ -n "${TRAEFIK_ADMIN_USER:-}" ]] || die "TRAEFIK_ADMIN_USER kosong."
[[ -n "${TRAEFIK_ADMIN_PASSWORD:-}" ]] || die "TRAEFIK_ADMIN_PASSWORD kosong."

mkdir -p traefik/config/auth
HTPASSWD_ENTRY="$(openssl passwd -apr1 "${TRAEFIK_ADMIN_PASSWORD}")"
printf '%s:%s\n' "${TRAEFIK_ADMIN_USER}" "${HTPASSWD_ENTRY}" > traefik/config/auth/htpasswd
info "traefik/config/auth/htpasswd generated OK"

# -----------------------------------------------------------------------------
# STEP 4: Setup acme.json
# -----------------------------------------------------------------------------
log "Step 4/6: Setting up acme.json..."

mkdir -p traefik/data
touch traefik/data/acme.json
chmod 600 traefik/data/acme.json
touch traefik/data/access.log
info "traefik/data/acme.json: chmod 600 OK"

# -----------------------------------------------------------------------------
# STEP 5: Create data directories
# -----------------------------------------------------------------------------
log "Step 5/6: Creating data directories..."

mkdir -p step-ca/data step-ca/config
mkdir -p traefik/config/certs
mkdir -p vault/data
mkdir -p postgresql/data mysql/data
mkdir -p seaweedfs/data
mkdir -p postfix/data
mkdir -p gitlab/config gitlab/data gitlab/logs
mkdir -p gitlab-runner/config gitlab-runner/data

info "All data directories created"

# -----------------------------------------------------------------------------
# STEP 6: Git init
# -----------------------------------------------------------------------------
log "Step 6/6: Setting up git repository..."

if [ ! -d ".git" ]; then
  git init

  if ! git config user.email >/dev/null 2>&1; then
    git config user.email "infra-stack@${BASE_DOMAIN}"
    git config user.name "Infra Stack"
    info "Git user configured: infra-stack@${BASE_DOMAIN}"
  fi

  git add \
    .gitignore README.md Makefile \
    _shared/.env.template _shared/.secrets.template \
    _shared/networks/README.md \
    _shared/scripts/ \
    _shared/docs/ \
    step-ca/docker-compose.yml step-ca/.env.template step-ca/README.md \
    traefik/docker-compose.yml traefik/.env.template traefik/README.md \
    traefik/config/traefik.yml.template traefik/config/dynamic/ \
    vault/docker-compose.yml vault/.env.template vault/config/ vault/README.md \
    postgresql/docker-compose.yml postgresql/.env.template postgresql/README.md \
    postgresql/initdb/01-gitlab.sql.template postgresql/initdb/99-extensions.sql \
    mysql/docker-compose.yml mysql/.env.template mysql/config/ mysql/README.md \
    mysql/initdb/ \
    seaweedfs/docker-compose.yml seaweedfs/.env.template \
    seaweedfs/config/s3.json.template seaweedfs/README.md \
    postfix/docker-compose.yml postfix/.env.template postfix/README.md \
    gitlab/docker-compose.yml gitlab/.env.template gitlab/README.md \
    gitlab-runner/docker-compose.yml gitlab-runner/.env.template gitlab-runner/README.md \
    2>/dev/null || true

  git commit -m "chore: initial infra-stack scaffold" 2>/dev/null || \
    echo "WARNING: git commit failed — configure git user.email/name manually if needed"

  info "Git repository initialized."
else
  info "Git repository already exists."
  info "Skipping init."
fi

echo
log "Initialization complete!"
echo "Setting up git repository Done"
