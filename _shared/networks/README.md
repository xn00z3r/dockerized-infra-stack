# Docker Networks

Networks dibuat via script, bukan via `docker compose up`.
Gunakan: `bash _shared/scripts/create-networks.sh`
atau melalui Makefile: `make init` (otomatis) / `make up` (via `_check_networks`).

| Network | Subnet | Anggota |
|---|---|---|
| `infra-proxy-net` | 172.20.0.0/24 | Traefik, step-ca, Vault, SeaweedFS, GitLab |
| `infra-backend-net` | 172.20.1.0/24 | Vault, PostgreSQL, MySQL, SeaweedFS, Postfix, GitLab |
| `infra-devops-net` | 172.20.2.0/24 | GitLab, GitLab Runner |
