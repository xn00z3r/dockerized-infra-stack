#!/usr/bin/env bash
# =============================================================================
# git-remote-setup.sh
# Setup GitLab sebagai remote repository untuk infra-stack
# Dipanggil setelah GitLab online dan healthy
#
# Usage: make git-remote-setup
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

# Load environment
if [ ! -f "_shared/.env" ]; then
    echo "ERROR: _shared/.env tidak ditemukan. Jalankan make init dulu."
    exit 1
fi
set -a; source _shared/.env; set +a

GITLAB_URL="https://gitlab.${BASE_DOMAIN}"
PROJECT_NAME="infra-stack"
API_TOKEN=""

echo "==> [git-remote-setup] GitLab URL: ${GITLAB_URL}"
echo ""
echo "Untuk setup remote, Anda membutuhkan GitLab Personal Access Token."
echo "Buat di: ${GITLAB_URL}/-/user_settings/personal_access_tokens"
echo "Scope yang diperlukan: api, write_repository"
echo ""
read -r -s -p "Masukkan GitLab Personal Access Token: " API_TOKEN
echo ""

if [ -z "${API_TOKEN}" ]; then
    echo "ERROR: Token tidak boleh kosong."
    exit 1
fi

# Verifikasi token valid
echo "==> Verifying token..."
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "PRIVATE-TOKEN: ${API_TOKEN}" \
    "${GITLAB_URL}/api/v4/user" 2>/dev/null || echo "000")

if [ "${HTTP_STATUS}" != "200" ]; then
    echo "ERROR: Token tidak valid atau GitLab tidak reachable (HTTP ${HTTP_STATUS})"
    exit 1
fi

echo "    Token valid."

# Cek apakah project sudah ada
echo "==> Checking if project '${PROJECT_NAME}' exists..."
EXISTING=$(curl -sf \
    -H "PRIVATE-TOKEN: ${API_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects?search=${PROJECT_NAME}" 2>/dev/null | \
    python3 -c "import sys,json; projects=json.load(sys.stdin); \
        found=[p for p in projects if p['path']=='"${PROJECT_NAME}"']; \
        print(found[0]['http_url_to_repo'] if found else '')" 2>/dev/null || echo "")

if [ -n "${EXISTING}" ]; then
    REMOTE_URL="${EXISTING}"
    echo "    Project already exists: ${REMOTE_URL}"
else
    # Buat project baru
    echo "==> Creating project '${PROJECT_NAME}' in GitLab..."
    REMOTE_URL=$(curl -sf \
        -X POST \
        -H "PRIVATE-TOKEN: ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${PROJECT_NAME}\",\"path\":\"${PROJECT_NAME}\",\"visibility\":\"private\",\"description\":\"Infrastructure stack configuration\"}" \
        "${GITLAB_URL}/api/v4/projects" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['http_url_to_repo'])" 2>/dev/null || echo "")

    if [ -z "${REMOTE_URL}" ]; then
        echo "ERROR: Gagal membuat project di GitLab."
        exit 1
    fi
    echo "    Project created: ${REMOTE_URL}"
fi

# Setup git remote
if git remote get-url origin > /dev/null 2>&1; then
    echo "==> Remote 'origin' already exists. Updating..."
    git remote set-url origin "${REMOTE_URL}"
else
    echo "==> Adding remote 'origin'..."
    git remote add origin "${REMOTE_URL}"
fi

# Commit any pending changes
git add -A 2>/dev/null || true
git diff --staged --quiet || git commit -m "chore: update infra-stack before push to GitLab" 2>/dev/null || true

# Push ke GitLab
echo "==> Pushing to GitLab..."
# Inject credentials ke URL untuk non-interactive push
CRED_URL=$(echo "${REMOTE_URL}" | sed "s|https://|https://root:${API_TOKEN}@|")
git push "${CRED_URL}" HEAD:main --set-upstream 2>/dev/null || \
git push "${CRED_URL}" HEAD:main 2>/dev/null

echo ""
echo "==> [git-remote-setup] DONE!"
echo "    Repository: ${REMOTE_URL}"
echo "    Branch: main"
echo ""
