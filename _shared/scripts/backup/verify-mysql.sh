#!/usr/bin/env bash
# =============================================================================
# Ultra Deep Verify — MySQL
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

echo "==> [verify-mysql] Ultra deep validation..."

cfg="$(docker compose --env-file _shared/.env -f mysql/docker-compose.yml config)"

cfg_mem="$(printf '%s\n' "$cfg" | awk '/^[[:space:]]+mem_limit:/ {gsub(/"/,"",$2); print $2; exit}')"
cfg_cpu="$(printf '%s\n' "$cfg" | awk '/^[[:space:]]+cpus:/ {print $2; exit}')"

if [ -z "${cfg_mem}" ] || [ -z "${cfg_cpu}" ]; then
    echo "ERROR: gagal membaca mem_limit/cpus dari compose config."
    exit 1
fi

echo "$cfg" | grep -q 'image: mysql:9.7'
echo "$cfg" | grep -q 'container_name: mysql'
echo "$cfg" | grep -q 'MYSQL_DATABASE: default_db'
echo "$cfg" | grep -q 'infra-backend-net'
echo "$cfg" | grep -q 'docker-entrypoint-initdb.d'
echo "$cfg" | grep -q 'mem_limit: '
echo "$cfg" | grep -q 'cpus: '
echo "    Compose contract: PASS"

runtime_mem="$(docker inspect mysql --format '{{.HostConfig.Memory}}')"
runtime_cpu="$(docker inspect mysql --format '{{.HostConfig.NanoCpus}}')"
expected_cpu_nano="$(awk -v c="${cfg_cpu}" 'BEGIN { printf "%.0f", c * 1000000000 }')"

if [ "${runtime_mem}" != "${cfg_mem}" ]; then
    echo "ERROR: memory mismatch. compose=${cfg_mem}, runtime=${runtime_mem}"
    exit 1
fi

if [ "${runtime_cpu}" != "${expected_cpu_nano}" ]; then
    echo "ERROR: cpu mismatch. compose=${cfg_cpu}, runtime_nano=${runtime_cpu}, expected_nano=${expected_cpu_nano}"
    exit 1
fi

restart_policy="$(docker inspect mysql --format '{{.HostConfig.RestartPolicy.Name}}')"
if [ "${restart_policy}" != "unless-stopped" ]; then
    echo "ERROR: restart policy mismatch. expected=unless-stopped, got=${restart_policy}"
    exit 1
fi

networks_json="$(docker inspect mysql --format '{{json .NetworkSettings.Networks}}')"
echo "${networks_json}" | grep -q '"infra-backend-net"'
if echo "${networks_json}" | grep -q 'infra-proxy-net'; then
    echo "ERROR: mysql unexpectedly joined infra-proxy-net"
    exit 1
fi

echo "    Runtime contract: PASS"

health_status="$(docker inspect mysql --format '{{.State.Health.Status}}')"
if [ "${health_status}" != "healthy" ]; then
    echo "ERROR: mysql health is ${health_status}"
    exit 1
fi

echo "    Healthcheck: PASS"

docker exec mysql getent hosts "${GITLAB_FQDN}" >/dev/null
echo "    DNS contract: PASS"

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW DATABASES" | grep -q '^default_db$'
echo "    Bootstrap database: PASS"

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -D default_db \
    -Nse "
CREATE TEMPORARY TABLE IF NOT EXISTS verify_tmp (
    id INT PRIMARY KEY
);
INSERT INTO verify_tmp (id) VALUES (1) ON DUPLICATE KEY UPDATE id=id;
SELECT COUNT(*) FROM verify_tmp;
" | grep -q '^1$'
echo "    Writable DDL/DML: PASS"

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW VARIABLES LIKE 'character_set_server';" | grep -q 'utf8mb4'
docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW VARIABLES LIKE 'collation_server';" | grep -q 'utf8mb4_unicode_ci'
echo "    Charset & collation: PASS"

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW VARIABLES LIKE 'ssl_ca';" | grep -q 'ca.pem'
docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW VARIABLES LIKE 'ssl_cert';" | grep -q 'server-cert.pem'
docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SHOW VARIABLES LIKE 'ssl_key';" | grep -q 'server-key.pem'
echo "    TLS readiness: PASS"

host_tz="$(date +%Z)"
container_tz="$(docker exec mysql date +%Z)"
if [ "${host_tz}" != "${container_tz}" ]; then
    echo "ERROR: timezone mismatch. host=${host_tz}, container=${container_tz}"
    exit 1
fi

docker exec mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    -Nse "SELECT @@global.time_zone;" | grep -q '^SYSTEM$'
echo "    Timezone contract: PASS"

test -f mysql/rendered/initdb/01-init.sql
! grep -R '\${' mysql/rendered/initdb/01-init.sql >/dev/null 2>&1
echo "    Rendered init artifact: PASS"

echo "==> [verify-mysql] SUCCESS"
