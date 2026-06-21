#!/usr/bin/env bash
# =============================================================================
# wait-healthy.sh
# Polling Docker container health status sampai healthy atau timeout
#
# Usage: wait-healthy.sh <container_name> [timeout_seconds]
# Exit: 0 = healthy, 1 = timeout atau error
# =============================================================================
set -euo pipefail

SERVICE="${1:?ERROR: container_name required. Usage: wait-healthy.sh <name> [timeout]}"
TIMEOUT="${2:-300}"
INTERVAL=5

echo "==> Waiting for '${SERVICE}' to be healthy (timeout: ${TIMEOUT}s)..."
ELAPSED=0

while [ "${ELAPSED}" -lt "${TIMEOUT}" ]; do
    # Guard: container mungkin belum exist (docker inspect return non-zero)
    if ! docker inspect "${SERVICE}" > /dev/null 2>&1; then
        echo "    [${ELAPSED}s] Container '${SERVICE}' not found yet. Waiting..."
        sleep "${INTERVAL}"
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi

    # Ambil health status
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${SERVICE}" 2>/dev/null || echo "none")

    case "${STATUS}" in
        healthy)
            echo "==> '${SERVICE}' is healthy. (${ELAPSED}s elapsed)"
            exit 0
            ;;
        unhealthy)
            echo "ERROR: '${SERVICE}' is UNHEALTHY after ${ELAPSED}s"
            echo "--- Container State ---"
            docker inspect --format='{{json .State}}' "${SERVICE}" 2>/dev/null | \
                python3 -m json.tool 2>/dev/null || true
            exit 1
            ;;
        starting|none)
            echo "    [${ELAPSED}s] Status: ${STATUS}. Retrying in ${INTERVAL}s..."
            ;;
        *)
            echo "    [${ELAPSED}s] Unknown status: '${STATUS}'. Retrying..."
            ;;
    esac

    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: '${SERVICE}' did not become healthy within ${TIMEOUT}s"
echo "--- Last known state ---"
docker inspect --format='{{json .State}}' "${SERVICE}" 2>/dev/null || true
exit 1
