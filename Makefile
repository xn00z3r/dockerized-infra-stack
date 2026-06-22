# =============================================================================
# INFRA-STACK Makefile
# =============================================================================

.PHONY: init up up-continue down restart status backup backup-remote \
        new-service git-remote-setup logs shell help _check_networks

-include _shared/.env
export

# Resolve absolute path ke root direktori infra-stack (lokasi Makefile ini)
# Digunakan oleh backup scripts — tidak hardcode path
INFRA_STACK_ROOT := $(shell pwd)
export INFRA_STACK_ROOT

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
	@echo "Next: make up 'make up'"

up: _check_networks
	@echo "==> [up] Starting step-ca..."
	docker compose -f step-ca/docker-compose.yml up -d
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
	docker compose -f traefik/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh traefik 60

	@echo "==> [up] Starting Vault..."
	docker compose -f vault/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh vault 60
	@echo "    NOTE: Jika Vault sealed, jalankan: bash _shared/scripts/vault-unseal.sh"

	@echo "==> [up] Starting PostgreSQL dan MySQL..."
	docker compose -f postgresql/docker-compose.yml up -d
	docker compose -f mysql/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh postgresql 120
	@bash _shared/scripts/wait-healthy.sh mysql 120

	@echo "==> [up] Starting SeaweedFS..."
	docker compose -f seaweedfs/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh seaweedfs 90

	@echo "==> [up] Starting Postfix..."
	docker compose -f postfix/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh postfix 60

	@echo "==> [up] Starting GitLab CE..."
	docker compose -f gitlab/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh gitlab 600

	@echo "==> [up] Starting GitLab Runner..."
	docker compose -f gitlab-runner/docker-compose.yml up -d
	@echo "    NOTE: Runner healthy setelah registrasi selesai."

	@echo ""
	@$(MAKE) status
	@echo ""
	@echo "==> [up] All services started."

down:
	@echo "==> [down] Stopping services in reverse order..."
	@for service in gitlab-runner gitlab postfix seaweedfs mysql postgresql vault traefik step-ca; do \
		echo "    Stopping $$service..."; \
		docker compose -f $$service/docker-compose.yml down 2>/dev/null || true; \
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
	docker compose -f $(SERVICE)/docker-compose.yml logs -f --tail=100

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
