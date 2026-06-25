# =============================================================================
# INFRA-STACK Makefile
# =============================================================================

.PHONY: init up up-continue down restart status backup backup-remote \
        purge-mysql verify-mysql verify-mysql-backup restore-mysql \
        purge-postgresql verify-postgresql restore-postgresql verify-postgresql-backup \
        new-service git-remote-setup logs shell help _check_networks

-include _shared/.env
export

# Resolve absolute path ke root direktori infra-stack (lokasi Makefile ini)
# Digunakan oleh backup scripts — tidak hardcode path
INFRA_STACK_ROOT := $(shell pwd)
export INFRA_STACK_ROOT

COMPOSE := docker compose
COMPOSE_ENV := --env-file _shared/.env

COMPOSE_DOWN = docker compose --env-file _shared/.env

MYSQL_COMPOSE      := $(COMPOSE) $(COMPOSE_ENV) -f mysql/docker-compose.yml
POSTGRES_COMPOSE   := $(COMPOSE) $(COMPOSE_ENV) -f postgresql/docker-compose.yml
TRAEFIK_COMPOSE    := $(COMPOSE) $(COMPOSE_ENV) -f traefik/docker-compose.yml
VAULT_COMPOSE      := $(COMPOSE) $(COMPOSE_ENV) -f vault/docker-compose.yml
STEPCA_COMPOSE     := $(COMPOSE) $(COMPOSE_ENV) -f step-ca/docker-compose.yml
SEAWEED_COMPOSE    := $(COMPOSE) $(COMPOSE_ENV) -f seaweedfs/docker-compose.yml
POSTFIX_COMPOSE    := $(COMPOSE) $(COMPOSE_ENV) -f postfix/docker-compose.yml
GITLAB_COMPOSE     := $(COMPOSE) $(COMPOSE_ENV) -f gitlab/docker-compose.yml
RUNNER_COMPOSE     := $(COMPOSE) $(COMPOSE_ENV) -f gitlab-runner/docker-compose.yml

# =============================================================================
# HELP
# =============================================================================

help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║              INFRA-STACK — Make Targets                      ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "  LIFECYCLE:"
	@echo "    make init                 Render templates, buat direktori, buat networks, init git"
	@echo "    make up                   Start semua service (normal ops)"
	@echo "    make up-continue          Start semua service KECUALI step-ca"
	@echo "    make down                 Stop semua service (reverse order)"
	@echo "    make restart              Stop then start semua service"
	@echo ""
	@echo "  MAINTENANCE:"
	@echo "    make purge-mysql          Remove MySQL data and volumes"
	@echo "    make verify-mysql         Validate MySQL bootstrap"
	@echo "    make verify-mysql-backup  End-to-end MySQL backup drill"
	@echo "    make restore-mysql BACKUP=xxx  Restore MySQL backup"
	@echo "    make purge-postgresql     Remove PostgreSQL data and volumes"
	@echo "    make verify-postgresql    Validate PostgreSQL bootstrap/contracts"
	@echo "    make verify-postgresql-backup  End-to-end PostgreSQL backup drill"
	@echo "    make restore-postgresql BACKUP=xxx  Restore PostgreSQL backup"
	@echo "    make status               Tampilkan health status semua container"
	@echo "    make backup               Jalankan backup semua service"
	@echo "    make backup-remote        Push backup lokal ke remote storage"
	@echo "    make logs SERVICE=xxx     View logs service tertentu"
	@echo "    make shell SERVICE=xxx    Buka shell di container service tertentu"
	@echo ""
	@echo "  DEVELOPMENT:"
	@echo "    make new-service NAME=xxx TIER=xxx    Scaffold service baru"
	@echo "    make git-remote-setup                 Setup GitLab sebagai git remote"
	@echo ""
	@echo "  TIER options: proxy | backend | devops"
	@echo ""

# =============================================================================
# LIFECYCLE
# =============================================================================

init:
	@echo "==> [init] Starting initialization..."
	@bash _shared/scripts/init.sh
	@echo "==> [init] Creating Docker networks..."
	@bash _shared/scripts/create-networks.sh
	@echo ""
	@echo "==> [init] Initialization complete!"
	@echo "    Next: make up"

up: _check_networks
	@echo "==> [up] Starting step-ca..."
	$(STEPCA_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh step-ca 120

	@echo "==> [up] Synchronizing root_ca.crt..."
	@mkdir -p traefik/config/certs || { \
		echo "ERROR: unable to create traefik/config/certs"; \
		exit 1; }
	@docker cp \
		step-ca:/home/step/certs/root_ca.crt \
		traefik/config/certs/root_ca.crt || { \
			echo "ERROR: failed to retrieve root_ca.crt from step-ca"; \
			exit 1; }
	@test -f traefik/config/certs/root_ca.crt || { \
			echo "ERROR: root_ca.crt not found after synchronization"; \
			exit 1; }
	@echo "    root_ca.crt synchronized."

	@$(MAKE) up-continue

up-continue: _check_networks
	@echo "==> [up] Starting Traefik..."
	$(TRAEFIK_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh traefik 60

	@echo "==> [up] Starting Vault..."
	$(VAULT_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh vault 60
	@echo "    NOTE: Jika Vault sealed, jalankan: bash _shared/scripts/vault-unseal.sh"

	@echo "==> [up] Starting PostgreSQL dan MySQL..."
	$(POSTGRES_COMPOSE) up -d
	$(MYSQL_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh postgresql 120
	@bash _shared/scripts/wait-healthy.sh mysql 120

	@echo "==> [up] Starting SeaweedFS..."
	$(SEAWEED_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh seaweedfs 90

	@echo "==> [up] Starting Postfix..."
	$(POSTFIX_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh postfix 60

	@echo "==> [up] Starting GitLab CE..."
	$(GITLAB_COMPOSE) up -d
	@bash _shared/scripts/wait-healthy.sh gitlab 600

	@echo "==> [up] Starting GitLab Runner..."
	$(RUNNER_COMPOSE) up -d
	@echo "    NOTE: Runner healthy setelah registrasi selesai."

	@echo ""
	@$(MAKE) status
	@echo ""
	@echo "==> [up] All services started."

down:
	@echo "==> [down] Stopping services in reverse order..."
	@for service in gitlab-runner gitlab postfix seaweedfs mysql postgresql vault traefik step-ca; do \
		if [ -f "$$service/docker-compose.yml" ]; then \
			echo "    Stopping $$service..."; \
			$(COMPOSE_DOWN) -f $$service/docker-compose.yml down --remove-orphans || true; \
		fi; \
	done
	@echo "==> [down] All services stopped. Networks preserved."
	@echo "    To remove networks: docker network rm infra-proxy-net infra-backend-net infra-devops-net"

restart:
	@$(MAKE) down
	@sleep 3
	@$(MAKE) up

# =============================================================================
# MAINTENANCE
# =============================================================================

purge-mysql:
	@echo "==> [purge-mysql] Stopping MySQL..."
	@$(MYSQL_COMPOSE) down -v --remove-orphans || true
	@echo "==> [purge-mysql] Removing mysql/data contents..."
	@sudo rm -rf mysql/data/*
	@echo "==> [purge-mysql] Recreating mysql/data..."
	@mkdir -p mysql/data
	@echo "==> [purge-mysql] Done."

verify-mysql:
	@echo "==> [verify-mysql] Verifying compose rendering..."
	@docker compose \
		--env-file _shared/.env \
		-f mysql/docker-compose.yml \
		config | grep -q "MYSQL_DATABASE: default_db"
	@echo "    Compose env rendering: PASS"
	@docker inspect mysql \
		--format='{{.State.Health.Status}}' \
		| grep -q '^healthy$$'
	@echo "    Healthcheck: PASS"
	@docker exec mysql \
		mysql \
		-uroot \
		-p"$$MYSQL_ROOT_PASSWORD" \
		-Nse "SHOW DATABASES" \
		| grep -q "^default_db$$"
	@echo "    Database bootstrap: PASS"
	@echo "==> [verify-mysql] SUCCESS"

verify-mysql-backup:
	@bash _shared/scripts/backup/verify-mysql-backup.sh

restore-mysql:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore-mysql BACKUP=<timestamp>"; \
		exit 1; \
	fi
	@bash _shared/scripts/backup/restore-mysql.sh "$(BACKUP)"

purge-postgresql:
	@echo "==> [purge-postgresql] Stopping PostgreSQL..."
	@$(POSTGRES_COMPOSE) down -v --remove-orphans || true
	@echo "==> [purge-postgresql] Removing postgresql/data contents..."
	@sudo rm -rf postgresql/data/*
	@echo "==> [purge-postgresql] Recreating postgresql/data..."
	@mkdir -p postgresql/data
	@echo "==> [purge-postgresql] Done."

verify-postgresql:
	@echo "==> [verify-postgresql] Verifying compose rendering..."
	@docker compose \
		--env-file _shared/.env \
		-f postgresql/docker-compose.yml \
		config | grep -q "POSTGRES_DB: postgres"
	@docker compose \
		--env-file _shared/.env \
		-f postgresql/docker-compose.yml \
		config | grep -q "PGDATA: /var/lib/postgresql/data/pgdata"
	@echo "    Compose env rendering: PASS"

	@docker inspect postgresql \
		--format='{{.HostConfig.Memory}}' \
		| grep -q '^2147483648$$'
	@docker inspect postgresql \
		--format='{{.HostConfig.NanoCpus}}' \
		| grep -q '^1000000000$$'
	@echo "    Resource contract: PASS"

	@docker inspect postgresql \
		--format='{{json .NetworkSettings.Networks}}' \
		| grep -q '"infra-backend-net"'
	@! docker inspect postgresql \
		--format='{{json .NetworkSettings.Networks}}' \
		| grep -q 'infra-proxy-net'
	@echo "    Network contract: PASS"

	@docker inspect postgresql \
		--format='{{.HostConfig.RestartPolicy.Name}}' \
		| grep -q '^unless-stopped$$'
	@echo "    Cold reboot policy: PASS"

	@docker exec postgresql getent hosts "$(GITLAB_FQDN)" >/dev/null
	@echo "    DNS contract: PASS"

	@docker inspect postgresql \
		--format='{{.State.Health.Status}}' \
		| grep -q '^healthy$$'
	@echo "    Healthcheck: PASS"

	@docker exec postgresql \
		psql -U "$(POSTGRES_USER)" -d "$(GITLAB_DB_NAME)" \
		-tAc "SELECT 1 FROM pg_database WHERE datname='$(GITLAB_DB_NAME)';" \
		| grep -q '^1$$'
	@echo "    Bootstrap database: PASS"

	@docker exec postgresql \
		psql -U "$(POSTGRES_USER)" -d "$(GITLAB_DB_NAME)" \
		-tAc "SELECT pg_encoding_to_char(encoding) || '|' || datcollate || '|' || datctype FROM pg_database WHERE datname='$(GITLAB_DB_NAME)';" \
		| grep -q '^UTF8|en_US.UTF-8|en_US.UTF-8$$'
	@echo "    Charset & collation: PASS"

	@docker compose \
		--env-file _shared/.env \
		-f postgresql/docker-compose.yml \
		config | grep -q "TZ: Asia/Jakarta"
	@echo "    Timezone contract: PASS"

	@echo "    TLS readiness: SKIPPED (no explicit PostgreSQL TLS contract in repo yet)"
	@echo "==> [verify-postgresql] SUCCESS"

verify-postgresql-backup:
	@bash _shared/scripts/backup/verify-postgresql-backup.sh

restore-postgresql:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore-postgresql BACKUP=<timestamp>"; \
		exit 1; \
	fi
	@bash _shared/scripts/backup/restore-postgresql.sh "$(BACKUP)"

status:
	@echo ""
	@echo "==> Container Health Status:"
	@echo "-------------------------------------------------------------------"
	@echo "NAMES                STATUS                      RUNNING FOR"
	@echo "-------------------------------------------------------------------"
	@for name in step-ca traefik vault postgresql mysql seaweedfs postfix gitlab gitlab-runner; do \
		info=$$(docker inspect --format='{{.Name}} {{.State.Status}} {{.State.Health.Status}}' \
			"$$name" 2>/dev/null | sed 's|^/||'); \
		if [ -n "$$info" ]; then echo "  $$info"; else echo "  $$name (not found)"; fi; \
	done
	@echo "-------------------------------------------------------------------"
	@echo ""
	@echo "==> Docker Networks:"
	@docker network ls --filter "name=infra-" --format "  {{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null || true

backup:
	$(eval TIMESTAMP := $(shell date +%Y-%m-%d_%H-%M-%S))
	@echo "==> [backup] Starting backup at $(TIMESTAMP)..."
	@mkdir -p /data/backups
	@for service in postgresql mysql gitlab seaweedfs vault step-ca traefik; do \
		echo "    Backing up $$service..."; \
		bash _shared/scripts/backup/$$service.sh "$(TIMESTAMP)" || \
			echo "    WARNING: $$service backup failed, continuing..."; \
	done
	@echo "==> [backup] Cleaning backups older than 7 days..."
	@find /data/backups -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
	@echo "==> [backup] Done. Location: /data/backups/"

backup-remote:
	@echo "==> [backup-remote] Not yet implemented."
	@echo "    Manual: rclone sync /data/backups remote:infra-backups"

logs:
	@if [ -z "$(SERVICE)" ]; then \
		echo "ERROR: SERVICE required."; \
		echo "Usage  : make logs SERVICE=gitlab"; \
		echo "Options: step-ca traefik vault postgresql mysql seaweedfs postfix gitlab gitlab-runner"; \
		exit 1; \
	fi
	docker compose \
		--env-file _shared/.env \
		-f $(SERVICE)/docker-compose.yml \
		logs -f --tail=100

shell:
	@if [ -z "$(SERVICE)" ]; then \
		echo "ERROR: SERVICE required."; \
		echo "Usage  : make shell SERVICE=postgresql"; \
		echo "Options: step-ca traefik vault postgresql mysql seaweedfs postfix gitlab gitlab-runner"; \
		exit 1; \
	fi
	docker exec -it $(SERVICE) sh

# =============================================================================
# DEVELOPMENT
# =============================================================================

new-service:
	@if [ -z "$(NAME)" ]; then \
		echo "ERROR: NAME required. Usage: make new-service NAME=myapp TIER=backend"; \
		exit 1; \
	fi
	@if [ -z "$(TIER)" ]; then \
		echo "ERROR: TIER required. Options: proxy | backend | devops"; \
		exit 1; \
	fi
	@bash _shared/scripts/new-service.sh "$(NAME)" "$(TIER)"

git-remote-setup:
	@bash _shared/scripts/git-remote-setup.sh

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_check_networks:
	@bash _shared/scripts/create-networks.sh
