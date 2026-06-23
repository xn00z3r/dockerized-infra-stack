# =============================================================================
# INFRA-STACK Makefile
# =============================================================================

.PHONY: init up up-continue down restart status backup backup-remote \
        purge-mysql verify-mysql \
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
	@echo "    make purge-mysql         Remove MySQL data and volumes"
	@echo "    make verify-mysql        Validate MySQL bootstrap"
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

restore-mysql:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore-mysql BACKUP=<timestamp>"; \
		exit 1; \
	fi
	@bash _shared/scripts/backup/restore-mysql.sh "$(BACKUP)"

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
