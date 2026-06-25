#!/usr/bin/env bash
# =============================================================================
# Ultra Deep Verify — PostgreSQL
# =============================================================================

set -euo pipefail

ROOT_DIR="${INFRA_STACK_ROOT:-$(pwd)}"
cd "${ROOT_DIR}"

if [ ! -f "_shared/.env" ]; then
    echo "ERROR: _shared/.env tidak ditemukan. Jalankan make init dulu."
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "_shared/.env"
set +a

echo "==> [verify-postgresql] Ultra deep validation..."

cfg="$(docker compose --env-file _shared/.env -f postgresql/docker-compose.yml config)"

cfg_mem="$(printf '%s\n' "$cfg" | awk '/^[[:space:]]+mem_limit:/ {gsub(/"/,"",$2); print $2; exit}')"
cfg_cpu="$(printf '%s\n' "$cfg" | awk '/^[[:space:]]+cpus:/ {print $2; exit}')"

if [ -z "${cfg_mem}" ] || [ -z "${cfg_cpu}" ]; then
    echo "ERROR: gagal membaca mem_limit/cpus dari compose config."
    exit 1
fi

echo "$cfg" | grep -q 'image: postgres:17.10'
echo "$cfg" | grep -q 'container_name: postgresql'
echo "$cfg" | grep -q 'POSTGRES_DB: postgres'
echo "$cfg" | grep -q 'PGDATA: /var/lib/postgresql/data/pgdata'
echo "$cfg" | grep -q 'infra-backend-net'
echo "$cfg" | grep -q 'docker-entrypoint-initdb.d'
echo "    Compose contract: PASS"

runtime_mem="$(docker inspect postgresql --format '{{.HostConfig.Memory}}')"
runtime_cpu="$(docker inspect postgresql --format '{{.HostConfig.NanoCpus}}')"
expected_cpu_nano="$(awk -v c="${cfg_cpu}" 'BEGIN { printf "%.0f", c * 1000000000 }')"

if [ "${runtime_mem}" != "${cfg_mem}" ]; then
    echo "ERROR: memory mismatch. compose=${cfg_mem}, runtime=${runtime_mem}"
    exit 1
fi

if [ "${runtime_cpu}" != "${expected_cpu_nano}" ]; then
    echo "ERROR: cpu mismatch. compose=${cfg_cpu}, runtime_nano=${runtime_cpu}, expected_nano=${expected_cpu_nano}"
    exit 1
fi

restart_policy="$(docker inspect postgresql --format '{{.HostConfig.RestartPolicy.Name}}')"
if [ "${restart_policy}" != "unless-stopped" ]; then
    echo "ERROR: restart policy mismatch. expected=unless-stopped, got=${restart_policy}"
    exit 1
fi

networks_json="$(docker inspect postgresql --format '{{json .NetworkSettings.Networks}}')"
echo "${networks_json}" | grep -q '"infra-backend-net"'
if echo "${networks_json}" | grep -q 'infra-proxy-net'; then
    echo "ERROR: postgresql unexpectedly joined infra-proxy-net"
    exit 1
fi

echo "    Runtime contract: PASS"

health_status="$(docker inspect postgresql --format '{{.State.Health.Status}}')"
if [ "${health_status}" != "healthy" ]; then
    echo "ERROR: postgresql health is ${health_status}"
    exit 1
fi

echo "    Healthcheck: PASS"

docker exec postgresql getent hosts "${GITLAB_FQDN}" >/dev/null
echo "    DNS contract: PASS"

docker exec postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    -tAc "SELECT 1 FROM pg_database WHERE datname='${GITLAB_DB_NAME}';" | grep -q '^1$'
echo "    Bootstrap database: PASS"

docker exec postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    -tAc "
CREATE TEMP TABLE verify_tmp (id INT PRIMARY KEY);
INSERT INTO verify_tmp (id) VALUES (1);
SELECT COUNT(*) FROM verify_tmp;
" | grep -q '^1$'
echo "    Writable DDL/DML: PASS"

docker exec postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    -tAc "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('pg_trgm','btree_gist','plpgsql');" | grep -q '^3$'
echo "    Extension baseline: PASS"

docker exec postgresql psql \
    -U "${POSTGRES_USER}" \
    -d "${GITLAB_DB_NAME}" \
    -tAc "SELECT pg_encoding_to_char(encoding) || '|' || datcollate || '|' || datctype FROM pg_database WHERE datname='${GITLAB_DB_NAME}';" \
    | grep -q '^UTF8|en_US.UTF-8|en_US.UTF-8$'
echo "    Charset & collation: PASS"

host_tz="$(date +%Z)"
container_tz="$(docker exec postgresql date +%Z)"
if [ "${host_tz}" != "${container_tz}" ]; then
    echo "ERROR: timezone mismatch. host=${host_tz}, container=${container_tz}"
    exit 1
fi
echo "    Timezone contract: PASS"

test -f postgresql/initdb/01-gitlab.sql
test -f postgresql/initdb/99-extensions.sql
! grep -R '\${' postgresql/initdb/01-gitlab.sql postgresql/initdb/99-extensions.sql >/dev/null 2>&1
echo "    Rendered init artifacts: PASS"

echo "==> [verify-postgresql] SUCCESS"
