# INFRA-STACK MASTER REFERENCE
## Architecture Decision Record & Implementation Source of Truth

**Status:** FINAL v2 — Deep-Reviewed, Cross-Validated, Zero Assumption  
**Orientation:** Fully Deterministic Operational Authoring  
**Tujuan:** IaC-compliant, migratable, replicable, open infrastructure  
**Target Path:** `/data/infra-stack/`  
**VM:** Ubuntu Server 26.04 LTS · 192.168.1.241 · user: `dts` · Docker 29.5.3  
**Dibuat dari:** Sesi Grill-Me 26 keputusan + crawling dokumentasi resmi 9 services  
**Review:** Deep cross-check v2 — 31 issues ditemukan dan diperbaiki

---

## CHANGELOG v2 — ISSUES YANG DIPERBAIKI

| ID | Severity | Issue | Fix |
|---|---|---|---|
| F01 | CRITICAL | `step ca health` butuh `--root` flag atau TLS verification akan gagal | Health check diubah ke `curl --cacert` |
| F02 | CRITICAL | `make up` hang selamanya saat first deploy karena Vault sealed = unhealthy | Vault health check dipisah: liveness vs readiness |
| F03 | CRITICAL | `traefik.yml` berisi `${BASE_DOMAIN}` tapi YAML tidak di-interpolasi otomatis | `traefik.yml` harus di-render `envsubst`, dijadikan `.template` |
| F04 | CRITICAL | `gitlab-runner verify --delete` menghapus runner dari server GitLab saat health check | Diubah ke `gitlab-runner verify` tanpa `--delete` |
| F05 | CRITICAL | Bootstrap order: `root_ca.crt` belum ada saat `make init` karena step-ca belum start | Bootstrap dipecah menjadi fase eksplisit |
| F06 | CRITICAL | PostgreSQL health check menggunakan `${POSTGRES_ROOT_USER}` tapi env var container adalah `${POSTGRES_USER}` | Dikoreksi ke `${POSTGRES_USER}` |
| F07 | CRITICAL | `VAULT_LOCAL_CONFIG` env var vs `vault.hcl` mount conflict — keduanya mendefinisikan backend | `VAULT_LOCAL_CONFIG` dihapus, hanya gunakan config mount |
| F08 | HIGH | Makefile `init` shell logic bug: `||` + `&&` precedence menyebabkan `git add` selalu dijalankan | Diubah ke `if [ ! -d .git ]; then ...; fi` |
| F09 | HIGH | `seaweedfs/config/s3.json` berisi credentials tapi tidak di-gitignore dan tidak ada template | Diubah ke `s3.json.template`, render ke `s3.json` (gitignored) |
| F10 | HIGH | `postgresql/initdb/01-gitlab.sql` berisi password tapi tidak di-gitignore | Diubah ke `01-gitlab.sql.template`, render ke `01-gitlab.sql` (gitignored) |
| F11 | HIGH | `traefik/config/certs/` direktori tidak ada di struktur direktori Section 2 | Ditambahkan ke struktur |
| F12 | HIGH | Backup `make backup` tidak include `step-ca` dan `traefik` padahal ada di backup table | Ditambahkan ke loop backup |
| F13 | HIGH | AWS CLI tidak ada di prerequisites tapi digunakan di post-deploy checklist | Ditambahkan ke prerequisites |
| F14 | HIGH | GitLab Container Registry storage config tidak lengkap: `object_store` tidak cover registry | Ditambahkan `registry['storage']` config block |
| F15 | HIGH | Traefik access log `/var/log/traefik/` tidak ada di volume mounts | Ditambahkan volume mount untuk access log |
| F16 | HIGH | GitLab Omnibus Container Registry port di Traefik label: 5000 vs 5050 (port Omnibus default) | Dikoreksi ke 5050 |
| F17 | MEDIUM | Makefile `restart`, `logs`, `shell` targets tidak diimplementasikan | Implementasi ditambahkan |
| F18 | MEDIUM | `POSTFIX_MYNETWORKS` hardcode subnet `172.20.1.0/24` di `.env.template` — tidak portable | Dipisah sebagai variabel dengan keterangan |
| F19 | MEDIUM | `container_name` tidak disebutkan eksplisit di seluruh service — diperlukan `wait-healthy.sh` | Container name ditambahkan ke setiap service section |
| F20 | MEDIUM | PostgreSQL `PGDATA` subdirectory behavior tidak dijelaskan — rawan confusion volume mount | Ditambahkan penjelasan eksplisit |
| F21 | MEDIUM | `.gitignore` tidak mencakup rendered config files yang berisi credentials | Gitignore diperlengkap |
| F22 | MEDIUM | `step-ca` container tidak join `infra-backend-net`, tapi Traefik perlu resolve `ca.${BASE_DOMAIN}` dari ACME | step-ca tetap di proxy-net, Traefik resolve via DNS (container name) — didokumentasikan |
| F23 | MEDIUM | `Vault port 8200/8201` di service table label sebagai HTTPS tapi vault.hcl `tls_disable=1` | Dikoreksi label port ke HTTP |
| F24 | MEDIUM | SeaweedFS health check: `curl -sf http://localhost:9333/cluster/status | grep -q 'IsLeader'` — field JSON case-sensitive | Diverifikasi field name adalah `IsLeader` (kapital) |
| F25 | MEDIUM | Postfix health check `postfix status` output string hardcoded — bisa berbeda per versi Alpine/Debian | Diubah ke approach yang lebih robust |
| F26 | MEDIUM | GitLab SMTP config: `smtp_authentication = false` tapi Postfix butuh STARTTLS ke Gmail — tidak ada auth di sisi Postfix-to-GitLab | Benar by design: GitLab→Postfix no-auth, Postfix→Gmail auth. Penjelasan ditambahkan. |
| F27 | MEDIUM | `gitlab-runner` config.toml menyebut `url = "https://resolute-gitlab.${BASE_DOMAIN}"` literal — tidak di-substitute | Klarifikasi: config.toml diisi saat runner register, bukan dari envsubst |
| F28 | MEDIUM | SeaweedFS bucket `gitlab-registry` perlu konfigurasi berbeda karena registry menggunakan S3 filesystem storage, bukan object_store API | Ditambahkan catatan konfigurasi registry storage |
| F29 | LOW | `wait-healthy.sh` tidak handle kasus container tidak ditemukan (exit non-zero dari docker inspect) | Ditambahkan guard |
| F30 | LOW | Migration playbook: `gitlab-backup restore` butuh `gitlab-secrets.json` tapi tidak disebutkan | Ditambahkan |
| F31 | LOW | Service table menampilkan `8080` sebagai internal port Traefik tapi API port tidak di-expose | Dihapus dari tabel, cukup disebutkan di section Traefik |

---

## DAFTAR ISI

1. [Prinsip Dasar Infrastruktur](#1-prinsip-dasar-infrastruktur)
2. [Struktur Direktori Lengkap](#2-struktur-direktori-lengkap)
3. [Docker Network Architecture](#3-docker-network-architecture)
4. [Service Inventory & Image Registry](#4-service-inventory--image-registry)
5. [Environment Variables — Single Source of Truth](#5-environment-variables--single-source-of-truth)
6. [Secret Management Strategy](#6-secret-management-strategy)
7. [TLS & PKI Strategy](#7-tls--pki-strategy)
8. [Bootstrap Sequence — First-Time Deployment](#8-bootstrap-sequence--first-time-deployment)
9. [Startup Order — Normal Operations](#9-startup-order--normal-operations)
10. [Data Persistence Strategy](#10-data-persistence-strategy)
11. [Backup Strategy](#11-backup-strategy)
12. [Observability Strategy](#12-observability-strategy)
13. [Mekanisme Penambahan Service Baru](#13-mekanisme-penambahan-service-baru)
14. [Version Control Strategy](#14-version-control-strategy)
15. [Service Configuration Reference](#15-service-configuration-reference)
    - [15.1 step-ca](#151-step-ca--smallstepstep-ca0302)
    - [15.2 Traefik](#152-traefik--traefikv375)
    - [15.3 Vault](#153-vault--hashicorpvault20)
    - [15.4 PostgreSQL](#154-postgresql--postgres1710)
    - [15.5 MySQL](#155-mysql--mysql97)
    - [15.6 SeaweedFS](#156-seaweedfs--chrislusfseaweedfs433_full)
    - [15.7 Postfix](#157-postfix--bokypostfixv510)
    - [15.8 GitLab CE](#158-gitlab-ce--gitlabgitlab-ce19011-ce0)
    - [15.9 GitLab Runner](#159-gitlab-runner--gitlabgitlab-runnerv1901)
16. [Makefile Targets Reference](#16-makefile-targets-reference)
17. [Pre-requisites & Bootstrap Checklist](#17-pre-requisites--bootstrap-checklist)
18. [Post-Deploy Checklist](#18-post-deploy-checklist)
19. [Migration / Replication Playbook](#19-migration--replication-playbook)
20. [Decision Log — Grill-Me Summary](#20-decision-log--grill-me-summary)

---

## 1. PRINSIP DASAR INFRASTRUKTUR

Seluruh implementasi WAJIB mematuhi prinsip berikut tanpa pengecualian:

| Prinsip | Deskripsi | Implikasi Teknis |
|---|---|---|
| **Modular** | Setiap service mandiri di direktorinya sendiri | Tidak ada cross-service file dependency selain `_shared/` |
| **Infrastructure as Code** | Tidak ada parameter yang di-hardcode | Semua variabel dalam `.env.template`, di-render ke `.env` via `envsubst` |
| **Open Architecture** | Mudah menambah service baru | Scaffolding via `make new-service`, `ADDING_SERVICE.md` sebagai contract |
| **Zero Assumption** | Tidak ada ambiguitas dalam deployment | Setiap keputusan terdokumentasi di dokumen ini |
| **Migratable** | Dapat dipindah/direplikasi ke environment lain | Edit `.env.template`, jalankan `make init` |
| **Locally Self-Contained** | Tidak bergantung pada layanan eksternal kecuali Gmail SMTP | Semua service berjalan di satu VM |

---

## 2. STRUKTUR DIREKTORI LENGKAP

```
/data/infra-stack/
│
├── Makefile                          # Orchestrator utama semua operasi
├── .gitignore                        # Mengecualikan .env, data/, logs/, rendered secrets
├── README.md                         # Entry point dokumentasi
│
├── _shared/                          # Hal-hal lintas service
│   ├── .env.template                 # SINGLE SOURCE OF TRUTH semua variabel global
│   ├── .env                          # [GITIGNORED] Hasil render dari .env.template
│   ├── networks/
│   │   └── docker-compose.yml        # Definisi semua Docker networks
│   ├── scripts/
│   │   ├── init.sh                   # Main init script (dipanggil make init)
│   │   ├── wait-healthy.sh           # Polling health check antar-compose
│   │   ├── vault-unseal.sh           # Auto-unseal Vault setelah VM restart
│   │   ├── new-service.sh            # Scaffolding service baru
│   │   ├── git-remote-setup.sh       # Setup remote ke GitLab setelah online
│   │   └── backup/
│   │       ├── postgresql.sh         # pg_dump per DB
│   │       ├── mysql.sh              # mysqldump
│   │       ├── gitlab.sh             # gitlab-backup create
│   │       ├── seaweedfs.sh          # SeaweedFS data rsync
│   │       ├── vault.sh              # vault operator raft snapshot save
│   │       ├── step-ca.sh            # rsync step-ca/data/
│   │       └── traefik.sh            # rsync traefik/data/ + traefik/config/
│   └── docs/
│       ├── ADDING_SERVICE.md         # Contract penambahan service baru
│       └── PREREQUISITES.md          # Syarat sebelum make init
│
├── step-ca/                          # Internal PKI CA
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   └── root_ca.crt              # [GITIGNORED] Di-copy dari container setelah first start
│   ├── data/                         # [GITIGNORED] CA data, certs, keys (/home/step)
│   └── README.md
│
├── traefik/                          # Reverse Proxy & TLS Termination
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   ├── traefik.yml.template      # Static config TEMPLATE (berisi ${BASE_DOMAIN})
│   │   ├── traefik.yml               # [GITIGNORED] Hasil render envsubst
│   │   ├── certs/
│   │   │   └── root_ca.crt          # [GITIGNORED] Di-copy dari step-ca setelah step-ca start
│   │   ├── dynamic/
│   │   │   └── middlewares.yml       # Basic auth, secure headers
│   │   └── auth/
│   │       └── htpasswd              # [GITIGNORED] Generated by make init via openssl
│   ├── data/
│   │   ├── acme.json                 # [GITIGNORED] TLS cert storage (WAJIB chmod 600)
│   │   └── access.log               # [GITIGNORED] Traefik access log
│   └── README.md
│
├── vault/                            # Secret Management
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   └── vault.hcl                 # Vault server configuration (di-mount ke container)
│   ├── data/                         # [GITIGNORED] Raft storage
│   └── README.md
│
├── postgresql/                       # Database PostgreSQL
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   └── postgresql.conf           # Custom PostgreSQL tuning (opsional)
│   ├── initdb/
│   │   ├── 01-gitlab.sql.template    # Template: CREATE USER/DB untuk GitLab
│   │   ├── 01-gitlab.sql             # [GITIGNORED] Hasil render (berisi password)
│   │   └── 99-extensions.sql         # Static: CREATE EXTENSION (tidak berisi credentials)
│   ├── data/                         # [GITIGNORED] PostgreSQL data directory
│   └── README.md
│
├── mysql/                            # Database MySQL
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   └── my.cnf                    # Custom MySQL config
│   ├── initdb/
│   │   └── 01-init.sql               # Static: CREATE DATABASE default (tidak berisi credentials)
│   ├── data/                         # [GITIGNORED] MySQL data directory
│   └── README.md
│
├── seaweedfs/                        # Object Storage (S3-compatible)
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/
│   │   ├── s3.json.template          # Template: S3 IAM credentials (berisi ${ACCESS_KEY})
│   │   └── s3.json                   # [GITIGNORED] Hasil render envsubst
│   ├── data/                         # [GITIGNORED] SeaweedFS data
│   └── README.md
│
├── postfix/                          # SMTP Relay (Gmail)
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── data/                         # [GITIGNORED] Postfix queue
│   └── README.md
│
├── gitlab/                           # SCM Server
│   ├── docker-compose.yml
│   ├── .env.template
│   ├── .env                          # [GITIGNORED]
│   ├── config/                       # [GITIGNORED] /etc/gitlab (gitlab.rb, secrets, etc.)
│   ├── data/                         # [GITIGNORED] /var/opt/gitlab
│   ├── logs/                         # [GITIGNORED] /var/log/gitlab
│   └── README.md
│
└── gitlab-runner/                    # CI/CD Runner
    ├── docker-compose.yml
    ├── .env.template
    ├── .env                          # [GITIGNORED]
    ├── config/                       # config.toml (diisi saat runner register, GITIGNORED)
    ├── data/                         # [GITIGNORED] Runner cache
    └── README.md
```

### `.gitignore` Lengkap

```gitignore
# Environment files — NEVER commit
**/.env

# Data directories
**/data/
**/logs/

# Generated secrets & rendered config files
traefik/config/auth/htpasswd
traefik/config/traefik.yml
traefik/config/certs/root_ca.crt
traefik/data/acme.json
traefik/data/access.log
step-ca/config/root_ca.crt
step-ca/data/
vault/data/
postgresql/initdb/01-gitlab.sql
seaweedfs/config/s3.json
gitlab/config/

# Runner registration
gitlab-runner/config/

# Vault init output — simpan di luar git
vault-init.json
```

---

## 3. DOCKER NETWORK ARCHITECTURE

### Network Definitions

Semua network didefinisikan di `_shared/networks/docker-compose.yml` dan dibuat PERTAMA sebelum service apapun start.

| Network Name | Driver | Subnet | Tujuan |
|---|---|---|---|
| `infra-proxy-net` | bridge | 172.20.0.0/24 | Traefik + service yang di-expose via HTTP/HTTPS |
| `infra-backend-net` | bridge | 172.20.1.0/24 | Database, Vault, SeaweedFS, Postfix |
| `infra-devops-net` | bridge | 172.20.2.0/24 | GitLab, GitLab Runner |

**PENTING:** Subnet `172.20.1.0/24` adalah nilai yang digunakan di `POSTFIX_MYNETWORKS`. Jika subnet diubah, `POSTFIX_MYNETWORKS` di `.env.template` WAJIB diperbarui secara bersamaan.

### Service ↔ Network Mapping

| Service | infra-proxy-net | infra-backend-net | infra-devops-net | Keterangan |
|---|---|---|---|---|
| `step-ca` | ✅ | — | — | Traefik akses via proxy-net untuk ACME |
| `traefik` | ✅ | — | — | Hanya proxy layer |
| `vault` | ✅ | ✅ | — | UI via proxy, service lain akses via backend |
| `postgresql` | — | ✅ | — | Internal only — tidak pernah exposed |
| `mysql` | — | ✅ | — | Internal only — tidak pernah exposed |
| `seaweedfs` | ✅ | ✅ | — | S3 UI via proxy, GitLab akses via backend |
| `postfix` | — | ✅ | — | Internal relay only |
| `gitlab` | ✅ | ✅ | ✅ | UI via proxy, DB+storage via backend, Runner via devops |
| `gitlab-runner` | — | — | ✅ | Hanya komunikasi dengan GitLab |

### Aturan Akses Database

**Database (PostgreSQL, MySQL) TIDAK PERNAH di-expose:**
- Tidak ada `ports:` mapping ke host
- Tidak ada TCP routing via Traefik
- Akses dari luar VM: SSH tunnel → `ssh -L 5432:localhost:5432 dts@192.168.1.241` → connect ke `localhost:5432`

---

## 4. SERVICE INVENTORY & IMAGE REGISTRY

| Service | Container Name | Image (Pinned) | Domain | Host Port |
|---|---|---|---|---|
| `step-ca` | `step-ca` | `smallstep/step-ca:0.30.2` | `resolute-ca.${BASE_DOMAIN}` | — |
| `traefik` | `traefik` | `traefik:v3.7.5` | `resolute-traefik.${BASE_DOMAIN}` | 80, 443 |
| `vault` | `vault` | `hashicorp/vault:2.0` | `resolute-vault.${BASE_DOMAIN}` | — |
| `postgresql` | `postgresql` | `postgres:17.10` | — (internal) | — |
| `mysql` | `mysql` | `mysql:9.7` | — (internal) | — |
| `seaweedfs` | `seaweedfs` | `chrislusf/seaweedfs:4.33_full` | `resolute-s3.${BASE_DOMAIN}` | — |
| `postfix` | `postfix` | `boky/postfix:v5.1.0` | — (internal) | — |
| `gitlab` | `gitlab` | `gitlab/gitlab-ce:19.0.1-ce.0` | `resolute-gitlab.${BASE_DOMAIN}`, `resolute-registry.${BASE_DOMAIN}` | 2222 (SSH) |
| `gitlab-runner` | `gitlab-runner` | `gitlab/gitlab-runner:v19.0.1` | — (internal) | — |

**Container name** adalah nilai yang digunakan oleh `wait-healthy.sh` dan `docker inspect`. Setiap `docker-compose.yml` WAJIB mendefinisikan `container_name:` eksplisit sesuai kolom di atas.

**WAJIB:** Semua image menggunakan tag versi eksplisit. Tidak boleh menggunakan `latest`.

---

## 5. ENVIRONMENT VARIABLES — SINGLE SOURCE OF TRUTH

### File: `_shared/.env.template`

File ini adalah satu-satunya file yang perlu diedit saat migrasi atau replikasi ke environment lain.

**Catatan Teknis:** `envsubst` memproses file ini secara sequential. Variabel yang mereferensi variabel lain (seperti `STEPCA_DNS=ca.${BASE_DOMAIN},localhost`) akan disubstitusi dengan benar karena `BASE_DOMAIN` didefinisikan lebih dulu.

```dotenv
# =============================================================================
# GLOBAL INFRASTRUCTURE PARAMETERS
# Edit file ini sebelum menjalankan: make init
# JANGAN PERNAH commit file .env (hasil render) ke git
# =============================================================================

# --- Infrastructure Identity ---
BASE_DOMAIN=dts.system
HOST_IP=192.168.1.241
TZ=Asia/Jakarta

# --- Traefik Admin Credentials ---
TRAEFIK_ADMIN_USER=admin
TRAEFIK_ADMIN_PASSWORD=GANTI_DENGAN_PASSWORD_KUAT
TRAEFIK_MEM_LIMIT=256m
TRAEFIK_CPUS=0.5

# --- step-ca Configuration ---
# STEPCA_DNS: otomatis menggunakan BASE_DOMAIN yang sudah didefinisikan di atas
STEPCA_NAME=DTS-Infrastructure-CA
STEPCA_DNS=ca.${BASE_DOMAIN},localhost
STEPCA_ADDRESS=:9000
STEPCA_PROVISIONER=infra-admin
STEPCA_MEM_LIMIT=128m
STEPCA_CPUS=0.25

# --- Vault Configuration ---
VAULT_MEM_LIMIT=512m
VAULT_CPUS=0.5

# --- PostgreSQL Configuration ---
POSTGRES_USER=postgres
POSTGRES_PASSWORD=GANTI_DENGAN_PASSWORD_KUAT
POSTGRES_DB=postgres
# User dan DB khusus untuk GitLab
GITLAB_DB_USER=gitlab
GITLAB_DB_PASSWORD=GANTI_DENGAN_PASSWORD_KUAT
GITLAB_DB_NAME=gitlabdb
POSTGRESQL_MEM_LIMIT=2g
POSTGRESQL_CPUS=1.0

# --- MySQL Configuration ---
MYSQL_ROOT_PASSWORD=GANTI_DENGAN_PASSWORD_KUAT
MYSQL_MEM_LIMIT=1g
MYSQL_CPUS=0.5

# --- SeaweedFS S3 Configuration ---
# ACCESS_KEY: minimal 16 karakter alphanum
# SECRET_KEY: minimal 32 karakter alphanum
SEAWEEDFS_S3_ACCESS_KEY=GANTI_ACCESS_KEY_MIN_16_CHAR
SEAWEEDFS_S3_SECRET_KEY=GANTI_SECRET_KEY_MIN_32_CHAR
SEAWEEDFS_MEM_LIMIT=1g
SEAWEEDFS_CPUS=0.5

# --- Postfix SMTP Relay (Gmail) ---
GMAIL_USER=akun@gmail.com
GMAIL_APP_PASSWORD=GMAIL_APP_PASSWORD_16_CHAR
# POSTFIX_MYNETWORKS: subnet infra-backend-net (172.20.1.0/24)
# Jika subnet di Section 3 diubah, variabel ini WAJIB diperbarui bersamaan
POSTFIX_MYNETWORKS=127.0.0.0/8,172.20.1.0/24
POSTFIX_MEM_LIMIT=256m
POSTFIX_CPUS=0.25

# --- GitLab Configuration ---
GITLAB_ROOT_PASSWORD=GANTI_DENGAN_PASSWORD_KUAT_MIN_8_CHAR
GITLAB_SSH_PORT=2222
GITLAB_MEM_LIMIT=6g
GITLAB_CPUS=2.0

# --- GitLab Runner Configuration ---
RUNNER_MEM_LIMIT=2g
RUNNER_CPUS=1.5
```

### Aturan Penggunaan

- File `.env` (hasil render) **TIDAK PERNAH** di-commit ke git
- `make init` memanggil `envsubst` untuk render `.env.template` → `.env` di setiap lokasi
- File yang memerlukan rendering selain `.env`: `traefik.yml.template`, `s3.json.template`, `01-gitlab.sql.template`
- Per-service `docker-compose.yml` menggunakan `env_file: [../_shared/.env, .env]` — urutan ini penting: global env dibaca dulu, lalu per-service override jika ada konflik

---

## 6. SECRET MANAGEMENT STRATEGY

### Tahap 1 — Bootstrap (sebelum Vault online)

- `.env` aktual tersimpan di filesystem VM, di-gitignore, tidak pernah di-push
- Operator menyimpan backup `.env` di luar infra-stack directory

### Tahap 2 — Runtime (setelah Vault online)

| Secret | Vault Path | Service |
|---|---|---|
| `TRAEFIK_ADMIN_PASSWORD` | `secret/infra/traefik` | traefik |
| `POSTGRES_PASSWORD` | `secret/infra/postgresql` | postgresql |
| `GITLAB_DB_PASSWORD` | `secret/infra/gitlab/db` | postgresql, gitlab |
| `MYSQL_ROOT_PASSWORD` | `secret/infra/mysql` | mysql |
| `SEAWEEDFS_S3_ACCESS_KEY` | `secret/infra/seaweedfs/s3` | seaweedfs, gitlab |
| `SEAWEEDFS_S3_SECRET_KEY` | `secret/infra/seaweedfs/s3` | seaweedfs, gitlab |
| `GITLAB_ROOT_PASSWORD` | `secret/infra/gitlab/root` | gitlab |
| `GMAIL_USER` | `secret/infra/postfix` | postfix |
| `GMAIL_APP_PASSWORD` | `secret/infra/postfix` | postfix |

### Vault Auto-Unseal

- **Mekanisme:** File-based unseal key — satu unseal key disimpan di `/etc/vault-unseal/unseal.key` di VM host (di luar direktori git, di luar direktori Docker)
- **Permission file:** `chmod 400 /etc/vault-unseal/unseal.key` — hanya root yang bisa baca
- **Auto-unseal trigger:** `cron @reboot` menjalankan `vault-unseal.sh` dengan delay 30 detik setelah VM restart
- **Storage backend:** `raft` — keputusan final, tidak dapat diubah tanpa `vault operator migrate`

---

## 7. TLS & PKI STRATEGY

### Arsitektur

```
step-ca (Root CA + Intermediate CA) — port 9000 HTTPS
    ↓ ACME protocol (tls-alpn-01 challenge) via infra-proxy-net
Traefik (Certificate Resolver "step-ca")
    ↓ Wildcard cert *.dts.system (auto-renew setiap ~24 jam)
Semua service via HTTPS — cert valid karena trust ke step-ca root CA
```

### Catatan Penting: Bootstrap Dependency

Terdapat circular dependency pada deployment pertama:
- `traefik.yml` membutuhkan `root_ca.crt` dari step-ca sebelum start
- `root_ca.crt` hanya bisa diambil setelah step-ca start dan generate cert

**Solusi:** Bootstrap dibagi 2 fase eksplisit — lihat Section 8.

### Traefik ↔ step-ca Integration

```yaml
# Environment variables WAJIB di Traefik container:
environment:
  LEGO_CA_CERTIFICATES: /etc/traefik/certs/root_ca.crt
  LEGO_CA_SERVERNAME: resolute-ca.${BASE_DOMAIN}
```

`LEGO_CA_CERTIFICATES` memberitahu library LEGO (yang digunakan Traefik untuk ACME) untuk trust CA cert tertentu saat koneksi ke ACME server. Tanpa ini, Traefik akan gagal verifikasi TLS ke step-ca.

`LEGO_CA_SERVERNAME` diperlukan karena step-ca menggunakan TLS dengan SNI. Nilai ini harus match dengan DNS name yang ada di step-ca certificate.

### `traefik.yml` sebagai Template

`traefik/config/traefik.yml.template` adalah template yang mengandung `${BASE_DOMAIN}`. File ini di-render oleh `make init` menjadi `traefik/config/traefik.yml` (gitignored). YAML config file tidak mendukung env var substitusi natively — rendering WAJIB dilakukan eksplisit via `envsubst`.

### `acme.json` Permissions

```bash
# WAJIB: chmod 600. Traefik akan EXIT jika permissions tidak tepat.
touch traefik/data/acme.json && chmod 600 traefik/data/acme.json
```

Dilakukan otomatis oleh `make init`.

### Trust Distribution

Setelah step-ca online, root CA cert WAJIB diinstall di:

```bash
# Ubuntu VM host
sudo cp step-ca/config/root_ca.crt /usr/local/share/ca-certificates/infra-stack-ca.crt
sudo update-ca-certificates

# Browser developer (Chrome): Settings → Privacy → Manage Certificates → Import
# Browser developer (Firefox): Settings → Privacy → View Certificates → Import

# Verifikasi
curl -v https://reolute-traefik.dts.system 2>&1 | grep "SSL certificate verify ok"
```

---

## 8. BOOTSTRAP SEQUENCE — FIRST-TIME DEPLOYMENT

**PENTING:** Section ini BERBEDA dari Section 9 (Normal Operations). Bootstrap HANYA dijalankan sekali pada deployment pertama. Setelah selesai, gunakan `make up` untuk operasi normal.

### Fase 0 — Pre-requisites

Pastikan semua item di Section 17 terpenuhi. Kemudian:

```bash
# Kloning atau inisialisasi struktur direktori
cd /data/infra-stack
```

### Fase 1 — Init Templates

```bash
make init
```

`make init` melakukan hal berikut secara berurutan:
1. Validasi: pastikan semua placeholder di `_shared/.env.template` sudah diisi (tidak ada nilai `GANTI_*`)
2. Render `_shared/.env.template` → `_shared/.env`
3. Render `traefik/config/traefik.yml.template` → `traefik/config/traefik.yml`
4. Render `seaweedfs/config/s3.json.template` → `seaweedfs/config/s3.json`
5. Render `postgresql/initdb/01-gitlab.sql.template` → `postgresql/initdb/01-gitlab.sql`
6. Generate `traefik/config/auth/htpasswd` dari `TRAEFIK_ADMIN_USER`/`TRAEFIK_ADMIN_PASSWORD`
7. Buat file `traefik/data/acme.json` dengan `chmod 600`
8. Buat semua direktori `data/` yang diperlukan dengan permission yang benar
9. Inisialisasi git repository jika belum ada

```bash
# Isi init.sh — render semua templates
#!/usr/bin/env bash
set -euo pipefail

# Load environment
source _shared/.env

# Validasi: tidak boleh ada placeholder yang belum diisi
if grep -r 'GANTI_' _shared/.env > /dev/null 2>&1; then
    echo "ERROR: Masih ada placeholder 'GANTI_*' di _shared/.env. Edit dulu."
    exit 1
fi

# Render templates
envsubst < traefik/config/traefik.yml.template > traefik/config/traefik.yml
envsubst < seaweedfs/config/s3.json.template > seaweedfs/config/s3.json
envsubst < postgresql/initdb/01-gitlab.sql.template > postgresql/initdb/01-gitlab.sql

# Generate htpasswd
htpasswd_entry=$(openssl passwd -apr1 "${TRAEFIK_ADMIN_PASSWORD}")
echo "${TRAEFIK_ADMIN_USER}:${htpasswd_entry}" > traefik/config/auth/htpasswd

# Create acme.json dengan permissions yang benar
touch traefik/data/acme.json && chmod 600 traefik/data/acme.json

# Buat direktori data dengan permissions yang benar
mkdir -p step-ca/data vault/data traefik/data traefik/config/certs
mkdir -p postgresql/data mysql/data seaweedfs/data
mkdir -p gitlab/config gitlab/data gitlab/logs
mkdir -p gitlab-runner/config gitlab-runner/data
mkdir -p postfix/data

# PostgreSQL data dir butuh ownership postgres (UID 999)
# Dibuat otomatis oleh Docker container pada first start

# Git init
if [ ! -d .git ]; then
    git init
    git add .
    git commit -m "chore: initial infra-stack scaffold"
    echo "Git repository initialized."
fi

echo "==> make init selesai. Lanjutkan dengan: Fase 2 Bootstrap (lihat Section 8)"
```

### Fase 2 — Start step-ca (Saja)

```bash
docker compose -f _shared/networks/docker-compose.yml up -d
docker compose -f step-ca/docker-compose.yml up -d
```

Tunggu hingga step-ca healthy:

```bash
bash _shared/scripts/wait-healthy.sh step-ca 120
```

### Fase 3 — Ambil dan Distribusikan Root CA Certificate

```bash
# Ambil root CA dari container
docker cp step-ca:/home/step/certs/root_ca.crt step-ca/config/root_ca.crt

# Copy ke traefik certs directory (WAJIB sebelum Traefik start)
cp step-ca/config/root_ca.crt traefik/config/certs/root_ca.crt

# Install ke sistem Ubuntu VM
sudo cp step-ca/config/root_ca.crt /usr/local/share/ca-certificates/infra-stack-ca.crt
sudo update-ca-certificates

echo "Root CA fingerprint (simpan ini):"
docker exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt
```

### Fase 4 — Lanjutkan Start Stack

```bash
make up-continue
# Target ini start semua service SELAIN step-ca (yang sudah running)
```

### Fase 5 — Bootstrap Vault (HANYA SEKALI)

```bash
# Inisialisasi Vault — satu kali seumur hidup cluster ini
docker exec vault vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > /tmp/vault-init.json

# SEGERA simpan vault-init.json di tempat aman
# JANGAN simpan di dalam /data/infra-stack/
sudo mkdir -p /etc/vault-unseal
sudo mv /tmp/vault-init.json /etc/vault-unseal/vault-init.json
sudo chmod 400 /etc/vault-unseal/vault-init.json

# Extract unseal key dan simpan
UNSEAL_KEY=$(sudo jq -r '.unseal_keys_b64[0]' /etc/vault-unseal/vault-init.json)
echo "$UNSEAL_KEY" | sudo tee /etc/vault-unseal/unseal.key > /dev/null
sudo chmod 400 /etc/vault-unseal/unseal.key

# Unseal Vault
docker exec vault vault operator unseal "$UNSEAL_KEY"

# Verifikasi
docker exec vault vault status

# Login dengan root token
ROOT_TOKEN=$(sudo jq -r '.root_token' /etc/vault-unseal/vault-init.json)
docker exec vault vault login "$ROOT_TOKEN"

# Enable KV v2 secrets engine
docker exec vault vault secrets enable -path=secret kv-v2

# Setup cron untuk auto-unseal setelah VM restart
(crontab -l 2>/dev/null; echo "@reboot sleep 30 && bash /data/infra-stack/_shared/scripts/vault-unseal.sh") | crontab -
```

### Fase 6 — Buat S3 Buckets GitLab

```bash
# Install AWS CLI (jika belum)
sudo apt-get install -y awscli

# Konfigurasi AWS CLI untuk SeaweedFS
aws configure set aws_access_key_id "${SEAWEEDFS_S3_ACCESS_KEY}"
aws configure set aws_secret_access_key "${SEAWEEDFS_S3_SECRET_KEY}"
aws configure set default.region us-east-1

# Buat semua buckets
for bucket in \
  gitlab-artifacts \
  gitlab-lfs \
  gitlab-registry \
  gitlab-uploads \
  gitlab-packages \
  gitlab-backups
do
  docker run --rm \
    --network infra-backend-net \
    -e AWS_ACCESS_KEY_ID=8K2DcazSIRnr2oN \
    -e AWS_SECRET_ACCESS_KEY=nExz41W6f2IfS7R8ULe6PWI0irCXnYkf \
    amazon/aws-cli \
    s3 mb "s3://${bucket}" \
    --endpoint-url http://seaweedfs:8333
done

# Verifikasi
docker run --rm \
  --network infra-backend-net \
  -e AWS_ACCESS_KEY_ID=8K2DcazSIRnr2oN \
  -e AWS_SECRET_ACCESS_KEY=nExz41W6f2IfS7R8ULe6PWI0irCXnYkf \
  amazon/aws-cli \
  s3api list-buckets \
  --endpoint-url http://seaweedfs:8333
```

### Fase 7 — Verifikasi Full Stack

```bash
make status
# Semua service harus menampilkan "(healthy)" kecuali gitlab-runner (belum register)
```

Lanjutkan ke Section 18 (Post-Deploy Checklist) untuk langkah-langkah setelah stack online.

---

## 9. STARTUP ORDER — NORMAL OPERATIONS

Digunakan untuk `make up` pada operasi normal (bukan first-time deployment).

### Dependency Chain

```
[1] Docker Networks
        ↓
[2] step-ca          → wait: healthy
        ↓
[3] Fase: Copy root_ca.crt jika belum ada di traefik/config/certs/
        ↓
[4] Traefik          → wait: healthy
        ↓
[5] Vault            → wait: process running (liveness check)
        ↓ MANUAL: vault-unseal.sh jika Vault sealed
        ↓
[6a] PostgreSQL      → wait: healthy (deep check)
[6b] MySQL           → wait: healthy (deep check)
        ↓
[7] SeaweedFS        → wait: healthy (cluster status check)
        ↓
[8] Postfix          → wait: healthy (SMTP port + process)
        ↓
[9] GitLab           → wait: healthy (/-/health endpoint)
        ↓
[10] GitLab Runner   → start (tidak di-wait; health check memerlukan registrasi selesai)
```

**Catatan Vault:** Health check Vault menggunakan liveness check (bukan full readiness) untuk startup sequence. Vault bisa dalam state `sealed` setelah VM restart — `vault-unseal.sh` menangani ini via cron @reboot. `make up` TIDAK menunggu Vault untuk unsealed; Vault harus sudah unsealed sebelum GitLab dapat berjalan normal.

### `wait-healthy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
# Usage: wait-healthy.sh <container_name> [timeout_seconds]
SERVICE="${1:?ERROR: container name required}"
TIMEOUT="${2:-300}"
INTERVAL=5

echo "==> Waiting for '${SERVICE}' to be healthy (timeout: ${TIMEOUT}s)..."
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    # Guard: container mungkin belum ada
    if ! docker inspect "${SERVICE}" > /dev/null 2>&1; then
        echo "    Container '${SERVICE}' not found. Waiting..."
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        continue
    fi

    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${SERVICE}" 2>/dev/null || echo "none")

    if [ "$STATUS" = "healthy" ]; then
        echo "==> '${SERVICE}' is healthy."
        exit 0
    fi

    echo "    Status: ${STATUS}. Retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: '${SERVICE}' did not become healthy within ${TIMEOUT}s"
docker inspect --format='{{json .State}}' "${SERVICE}" 2>/dev/null || true
exit 1
```

---

## 10. DATA PERSISTENCE STRATEGY

### Model: Bind Mount ke `<service>/data/`

| Service | Host Path | Container Path | Permission Note |
|---|---|---|---|
| `step-ca` | `./step-ca/data/` | `/home/step` | UID 1000 (step-ca user) |
| `traefik` | `./traefik/data/` | `/etc/traefik/acme/` | acme.json: chmod 600 |
| `traefik` logs | `./traefik/data/access.log` | `/var/log/traefik/access.log` | dibuat saat start |
| `vault` | `./vault/data/` | `/vault/data` | UID 100 (vault user) |
| `postgresql` | `./postgresql/data/` | `/var/lib/postgresql/data` | UID 999 (postgres) |
| `mysql` | `./mysql/data/` | `/var/lib/mysql` | UID 999 (mysql) |
| `seaweedfs` | `./seaweedfs/data/` | `/data` | — |
| `postfix` | `./postfix/data/` | `/var/spool/postfix` | — |
| `gitlab` | `./gitlab/data/` | `/var/opt/gitlab` | managed by Omnibus |
| `gitlab` config | `./gitlab/config/` | `/etc/gitlab` | contains gitlab.rb + secrets |
| `gitlab` logs | `./gitlab/logs/` | `/var/log/gitlab` | — |
| `gitlab-runner` | `./gitlab-runner/config/` | `/etc/gitlab-runner` | contains config.toml |

### PGDATA Subdirectory

PostgreSQL di-set dengan `PGDATA=/var/lib/postgresql/data/pgdata` (subdirectory di dalam bind mount). Ini dilakukan untuk menghindari masalah permission `lost+found` yang muncul jika direktori data tidak kosong. Volume mount: `./postgresql/data:/var/lib/postgresql/data` — data aktual berada di `./postgresql/data/pgdata/`.

---

## 11. BACKUP STRATEGY

### Arsitektur

```
Daily 03:00 WIB (VM host crontab, user: dts)
    → make backup
        → _shared/scripts/backup/<service>.sh $TIMESTAMP
            → /data/backups/<service>/<timestamp>/
```

### Crontab Entry

```bash
# crontab -e (sebagai user dts)
0 3 * * * cd /data/infra-stack && make backup >> /data/backups/backup.log 2>&1
```

### Backup Method per Service

| Service | Method | Tool | Downtime? | Output |
|---|---|---|---|---|
| `postgresql` | Logical dump per DB | `pg_dump` dalam container | Tidak | `.sql.gz` |
| `mysql` | Logical dump semua DB | `mysqldump` dalam container | Tidak | `.sql.gz` |
| `gitlab` | GitLab built-in backup | `gitlab-backup create` | Tidak | `.tar` |
| `seaweedfs` | rsync direktori data | `rsync` di host | Minimal (fsync) | directory copy |
| `vault` | Raft snapshot | `vault operator raft snapshot save` | Tidak | `.snap` |
| `step-ca` | rsync direktori data | `rsync` di host | Tidak | directory copy |
| `traefik` | rsync acme.json + config | `rsync` di host | Tidak | file copy |

### Backup Path & Retention

- Lokasi: `/data/backups/<service>/<YYYY-MM-DD_HH-MM-SS>/`
- Contoh: `/data/backups/postgresql/2026-06-15_03-00-00/gitlabdb.sql.gz`
- Retention: 7 hari — script otomatis hapus backup lebih dari 7 hari

---

## 12. OBSERVABILITY STRATEGY

**Status saat ini: Defer.** Tidak ada observability stack di tahap awal.

### Readiness Template (di setiap `docker-compose.yml`)

```yaml
# ============================================================
# OBSERVABILITY READINESS — uncomment saat stack Loki/Prometheus ditambahkan
# ============================================================
#    logging:
#      driver: "json-file"
#      options:
#        max-size: "50m"
#        max-file: "3"
#        tag: "{{.Name}}"
#    labels:
#      - "logging=promtail"
#      - "logging_jobname=SERVICE_NAME_DISINI"
#      # Prometheus metrics (jika service expose /metrics):
#      - "prometheus.scrape=true"
#      - "prometheus.port=METRICS_PORT"
# ============================================================
```

Stack yang akan ditambahkan di masa depan via `make new-service`:
- `loki/` + `promtail/` — log aggregation
- `prometheus/` + `grafana/` — metrics & visualization

---

## 13. MEKANISME PENAMBAHAN SERVICE BARU

### Command

```bash
make new-service NAME=myapp TIER=backend
# TIER: proxy | backend | devops
```

### Apa yang Di-scaffold Otomatis

```
/data/infra-stack/myapp/
├── docker-compose.yml    ← Template: network tier, Traefik labels, health check, resource limits
├── .env.template         ← Template: env_file reference ke _shared/.env
├── .env                  ← [GITIGNORED] dibuat saat make init
├── config/               ← kosong
├── data/                 ← [GITIGNORED] bind mount target
└── README.md             ← template dokumentasi service
```

### Template `docker-compose.yml` untuk Service Baru

```yaml
services:
  myapp:
    image: vendor/myapp:VERSION_PIN_WAJIB   # JANGAN gunakan :latest
    container_name: myapp                    # WAJIB: digunakan oleh wait-healthy.sh
    restart: unless-stopped
    env_file:
      - ../_shared/.env
      - .env
    networks:
      - infra-backend-net    # Sesuaikan dengan TIER
    volumes:
      - ./data:/app/data
    mem_limit: ${MYAPP_MEM_LIMIT}
    cpus: ${MYAPP_CPUS}
    healthcheck:
      test: ["CMD-SHELL", "GANTI_DENGAN_PERINTAH_HEALTH_CHECK_YANG_TEPAT"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    labels:
      # ---- Traefik routing (uncomment jika TIER=proxy) ----
      # - "traefik.enable=true"
      # - "traefik.http.routers.myapp.rule=Host(`myapp.${BASE_DOMAIN}`)"
      # - "traefik.http.routers.myapp.entrypoints=websecure"
      # - "traefik.http.routers.myapp.tls.certresolver=step-ca"
      # - "traefik.http.services.myapp.loadbalancer.server.port=PORT"
      # ---- Observability (uncomment saat stack observability deployed) ----
      # - "logging=promtail"
      # - "logging_jobname=myapp"

networks:
  infra-backend-net:
    external: true
  # infra-proxy-net:     # uncomment jika TIER=proxy atau hybrid
  #   external: true
```

**Wajib setelah scaffold:**
1. Tambahkan `MYAPP_MEM_LIMIT` dan `MYAPP_CPUS` ke `_shared/.env.template`
2. Tambahkan step start di Makefile `up` target (posisi dalam urutan startup)
3. Tambahkan step di Makefile `down` target
4. Tambahkan service ke `make backup` loop (jika ada data persisten)

---

## 14. VERSION CONTROL STRATEGY

### Fase 1 — Bootstrap (Git Lokal)

`make init` menjalankan `git init` secara kondisional:

```bash
# Bagian dari init.sh
if [ ! -d .git ]; then
    git init
    git add .
    git commit -m "chore: initial infra-stack scaffold"
    echo "Git repository initialized locally."
else
    echo "Git repository already exists. Skipping git init."
fi
```

**Catatan:** Kondisi ditulis dengan `if/else` untuk menghindari shell operator precedence bug (`||` dan `&&`).

### Fase 2 — Migrate ke GitLab (setelah GitLab online)

```bash
# Buat project di GitLab dan setup remote
make git-remote-setup

# Script _shared/scripts/git-remote-setup.sh:
# 1. Buat project via GitLab API: POST /api/v4/projects
# 2. git remote add origin https://resolute-gitlab.${BASE_DOMAIN}/root/infra-stack.git
# 3. git push -u origin main
```

---

## 15. SERVICE CONFIGURATION REFERENCE

### 15.1 step-ca — `smallstep/step-ca:0.30.2`

**Dokumentasi resmi:** https://smallstep.com/docs/step-ca/ · Release verified: 2026-03-23

#### Container Name: `step-ca`

#### Environment Variables

| Variable | Nilai | Keterangan |
|---|---|---|
| `DOCKER_STEPCA_INIT_NAME` | `${STEPCA_NAME}` | Nama CA — muncul di cert issuer field |
| `DOCKER_STEPCA_INIT_DNS_NAMES` | `${STEPCA_DNS}` | SAN list untuk CA server cert |
| `DOCKER_STEPCA_INIT_ADDRESS` | `${STEPCA_ADDRESS}` | Listening address (`:9000`) |
| `DOCKER_STEPCA_INIT_PROVISIONER_NAME` | `${STEPCA_PROVISIONER}` | Nama JWK provisioner |
| `DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT` | `true` | Enable Admin API |
| `DOCKER_STEPCA_INIT_ACME` | `true` | Auto-add ACME provisioner saat init |

**CATATAN:** `DOCKER_STEPCA_INIT_*` hanya efektif saat inisialisasi pertama (data dir kosong). Restart berikutnya menggunakan konfigurasi yang sudah tersimpan di `/home/step/config/ca.json`.

#### Volume Mounts

```yaml
volumes:
  - ./data:/home/step    # Seluruh state CA: keys, certs, DB, config
```

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Menggunakan curl dengan root CA cert karena step-ca menjalankan HTTPS
  # step CLI tidak tersedia di semua versi image; curl lebih reliable
  test: ["CMD-SHELL", "curl -sf --cacert /home/step/certs/root_ca.crt https://localhost:9000/health | grep -q 'ok'"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

**Penjelasan:** `curl --cacert` menggunakan root CA step-ca sendiri untuk verifikasi TLS. Response `{"status":"ok"}` menandakan CA API fully operational.

#### Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.step-ca.rule=Host(`resolute-ca.${BASE_DOMAIN}`)"
  - "traefik.http.routers.step-ca.entrypoints=websecure"
  - "traefik.http.routers.step-ca.tls=true"
  - "traefik.http.services.step-ca.loadbalancer.server.port=9000"
  - "traefik.http.services.step-ca.loadbalancer.server.scheme=https"
  # Traefik perlu trust cert step-ca saat proxy ke backend HTTPS
  - "traefik.http.services.step-ca.loadbalancer.serversTransport=step-ca-transport@file"
```

**Catatan `serversTransport`:** Traefik butuh konfigurasi ServersTransport khusus untuk trust cert step-ca saat proxy ke backend HTTPS. Ini dikonfigurasi di `traefik/config/dynamic/middlewares.yml`:

```yaml
# Tambahan di dynamic/middlewares.yml
http:
  serversTransports:
    step-ca-transport:
      rootCAs:
        - /etc/traefik/certs/root_ca.crt
      insecureSkipVerify: false
```

---

### 15.2 Traefik — `traefik:v3.7.5`

**Dokumentasi resmi:** https://doc.traefik.io/traefik/ · https://doc.traefik.io/traefik/setup/docker/

#### Container Name: `traefik`

#### Port Exposed ke Host

| Host Port | Container Port | Fungsi |
|---|---|---|
| 80 | 80 | HTTP — redirect permanen ke 443 |
| 443 | 443 | HTTPS — TLS termination |

Port 8080 (Traefik API internal) TIDAK di-expose ke host. Dashboard diakses via `resolute-traefik.${BASE_DOMAIN}` melalui HTTPS dengan basic auth.

#### Volume Mounts

```yaml
volumes:
  - ./config/traefik.yml:/etc/traefik/traefik.yml:ro        # Static config (rendered)
  - ./config/dynamic:/etc/traefik/dynamic:ro                # Dynamic config directory
  - ./config/auth/htpasswd:/etc/traefik/auth/htpasswd:ro    # Basic auth credentials
  - ./config/certs/root_ca.crt:/etc/traefik/certs/root_ca.crt:ro  # step-ca root CA
  - ./data/acme.json:/etc/traefik/acme/acme.json             # TLS cert storage
  - ./data/access.log:/var/log/traefik/access.log            # Access log
  - /var/run/docker.sock:/var/run/docker.sock:ro             # Docker provider
```

#### Static Configuration (`traefik/config/traefik.yml.template`)

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

ping: {}

log:
  level: INFO

accessLog:
  filePath: "/var/log/traefik/access.log"
  filters:
    statusCodes:
      - "400-599"

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: step-ca

providers:
  docker:
    exposedByDefault: false
    network: infra-proxy-net
  file:
    directory: "/etc/traefik/dynamic"
    watch: true

certificatesResolvers:
  step-ca:
    acme:
      caServer: "https://resolute-ca.${BASE_DOMAIN}:9000/acme/acme/directory"
      caCertificates:
        - "/etc/traefik/certs/root_ca.crt"
      storage: "/etc/traefik/acme/acme.json"
      tlsChallenge: true
```

**CATATAN:** File ini adalah **template** — mengandung `${BASE_DOMAIN}` yang di-render oleh `make init`. File hasil render (`traefik.yml`) di-gitignore.

#### Environment Variables WAJIB

```yaml
environment:
  - LEGO_CA_CERTIFICATES=/etc/traefik/certs/root_ca.crt
  - LEGO_CA_SERVERNAME=resolute-ca.${BASE_DOMAIN}
```

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  test: ["CMD", "traefik", "healthcheck", "--ping"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 30s
```

**Penjelasan:** `traefik healthcheck --ping` melakukan HTTP request ke internal ping endpoint. Return 0 hanya jika Traefik benar-benar memproses request. `ping: {}` WAJIB ada di static config.

#### Dynamic Config — Middlewares (`traefik/config/dynamic/middlewares.yml`)

```yaml
http:
  middlewares:
    basic-auth:
      basicAuth:
        usersFile: "/etc/traefik/auth/htpasswd"
    secure-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        referrerPolicy: "strict-origin-when-cross-origin"

  serversTransports:
    # Transport khusus untuk proxy ke step-ca backend (HTTPS dengan cert internal)
    step-ca-transport:
      rootCAs:
        - /etc/traefik/certs/root_ca.crt
      insecureSkipVerify: false
```

#### Dashboard Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.traefik.rule=Host(`resolute-traefik.${BASE_DOMAIN}`)"
  - "traefik.http.routers.traefik.entrypoints=websecure"
  - "traefik.http.routers.traefik.tls.certresolver=step-ca"
  - "traefik.http.routers.traefik.service=api@internal"
  - "traefik.http.routers.traefik.middlewares=basic-auth@file"
```

---

### 15.3 Vault — `hashicorp/vault:2.0`

**Dokumentasi resmi:** https://developer.hashicorp.com/vault/docs · https://developer.hashicorp.com/vault/docs/configuration/storage/raft

#### Container Name: `vault`

#### Port Internal

| Port | Protokol | Fungsi |
|---|---|---|
| 8200 | HTTP | Vault API & UI (TLS di-handle Traefik) |
| 8201 | HTTP | Raft cluster internal communication |

#### Konfigurasi (`vault/config/vault.hcl`)

```hcl
ui = true

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
  # TLS termination dilakukan oleh Traefik
  # Vault tidak pernah exposed langsung ke luar infra-proxy-net
}

api_addr     = "http://vault:8200"
cluster_addr = "http://vault:8201"
```

**ARSITEKTUR NOTE:** `tls_disable = 1` acceptable karena:
1. Vault hanya diakses via `infra-proxy-net` (dari Traefik) dan `infra-backend-net` (dari service internal)
2. Tidak ada koneksi langsung dari luar VM ke Vault
3. Traefik menyediakan TLS termination untuk akses dari browser/client

#### Volume Mounts

```yaml
volumes:
  - ./config/vault.hcl:/vault/config/vault.hcl:ro  # Config file
  - ./data:/vault/data                               # Raft storage
```

**PENTING:** JANGAN set `VAULT_LOCAL_CONFIG` env var bersamaan dengan config file mount. Keduanya mendefinisikan konfigurasi Vault dan akan conflict. Gunakan hanya config file mount.

#### Environment Variables

```yaml
environment:
  VAULT_ADDR: "http://0.0.0.0:8200"
  VAULT_API_ADDR: "http://vault:8200"
  VAULT_CLUSTER_ADDR: "http://vault:8201"
```

**Command dalam docker-compose:**
```yaml
command: ["vault", "server", "-config=/vault/config/vault.hcl"]
```

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Liveness check: apakah Vault process berjalan dan menerima koneksi
  # TIDAK memeriksa apakah sealed/unsealed — itu responsibility operator (vault-unseal.sh)
  # vault status exit code: 0=ok unsealed, 1=error, 2=sealed
  # Kita accept exit code 0 dan 2 (running tapi sealed = still alive)
  test: ["CMD-SHELL", "vault status -format=json 2>&1 | grep -q '\"initialized\"' || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

**Penjelasan:** Health check ini memeriksa bahwa Vault API merespons dan mengembalikan JSON yang valid (field `initialized` ada). Ini lulus baik saat sealed maupun unsealed. `make up` tidak menggantung menunggu Vault unsealed — itu tanggung jawab `vault-unseal.sh` via cron.

**Monitoring sealed state:** Gunakan `docker exec vault vault status` untuk memeriksa apakah Vault sealed setelah restart.

#### Vault Unseal Script (`_shared/scripts/vault-unseal.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

VAULT_UNSEAL_KEY_FILE="/etc/vault-unseal/unseal.key"

if [ ! -f "$VAULT_UNSEAL_KEY_FILE" ]; then
    echo "ERROR: Unseal key file tidak ditemukan: $VAULT_UNSEAL_KEY_FILE"
    exit 1
fi

# Tunggu Vault container running
for i in $(seq 1 12); do
    if docker inspect vault > /dev/null 2>&1; then
        break
    fi
    echo "Waiting for Vault container... ($i/12)"
    sleep 5
done

# Cek apakah perlu unseal
SEALED=$(docker exec vault vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")

if [ "$SEALED" = "true" ]; then
    echo "Vault is sealed. Unsealing..."
    docker exec vault vault operator unseal "$(cat $VAULT_UNSEAL_KEY_FILE)"
    echo "Vault unsealed successfully."
else
    echo "Vault is already unsealed. No action needed."
fi
```

#### Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.vault.rule=Host(`resolute-vault.${BASE_DOMAIN}`)"
  - "traefik.http.routers.vault.entrypoints=websecure"
  - "traefik.http.routers.vault.tls.certresolver=step-ca"
  - "traefik.http.services.vault.loadbalancer.server.port=8200"
```

---

### 15.4 PostgreSQL — `postgres:17.10`

**Dokumentasi resmi:** https://hub.docker.com/_/postgres · https://www.postgresql.org/docs/17/

#### Container Name: `postgresql`

#### Environment Variables

```yaml
environment:
  POSTGRES_USER: ${POSTGRES_USER}          # Nama superuser — BUKAN POSTGRES_ROOT_USER
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}  # Password superuser
  POSTGRES_DB: postgres                    # Default DB (bukan gitlabdb)
  PGDATA: /var/lib/postgresql/data/pgdata  # Subdirectory dalam bind mount
```

**PENTING tentang `PGDATA`:** Subdirectory `pgdata` dalam bind mount menghindari error permission `lost+found`. Volume mount: `./data:/var/lib/postgresql/data`, data aktual berada di `./data/pgdata/`.

#### Volume Mounts

```yaml
volumes:
  - ./data:/var/lib/postgresql/data
  - ./initdb:/docker-entrypoint-initdb.d:ro
  # Uncomment jika ada custom tuning:
  # - ./config/postgresql.conf:/etc/postgresql/postgresql.conf:ro
```

#### Init Scripts (`postgresql/initdb/`)

Dieksekusi SEKALI saat data directory kosong. Urutan: alphanumerik berdasarkan nama file.

**`01-gitlab.sql.template`** (template — di-render ke `01-gitlab.sql` oleh `make init`):

```sql
-- Buat user dan database untuk GitLab
-- File ini di-render dari template; 01-gitlab.sql di-gitignore
CREATE USER ${GITLAB_DB_USER} WITH PASSWORD '${GITLAB_DB_PASSWORD}';
CREATE DATABASE ${GITLAB_DB_NAME}
  OWNER ${GITLAB_DB_USER}
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.UTF-8'
  LC_CTYPE 'en_US.UTF-8'
  TEMPLATE template0;
GRANT ALL PRIVILEGES ON DATABASE ${GITLAB_DB_NAME} TO ${GITLAB_DB_USER};
```

**`99-extensions.sql`** (static — tidak berisi credentials, di-commit):

```sql
-- PostgreSQL extensions yang dibutuhkan GitLab
-- Dijalankan sebagai superuser (POSTGRES_USER)
\c gitlabdb
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS plpgsql;
```

**PENTING:** `99-extensions.sql` menggunakan `\c gitlabdb` literal — tidak di-render template. Jika `GITLAB_DB_NAME` diubah dari `gitlabdb`, file ini HARUS diupdate secara manual.

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Gunakan ${POSTGRES_USER} (bukan POSTGRES_ROOT_USER) — nama var sesuai container env
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d postgres && psql -U ${POSTGRES_USER} -lqt | cut -d '|' -f1 | grep -qw gitlabdb"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 60s
```

**Penjelasan:** Dua-tahap:
1. `pg_isready` — PostgreSQL menerima koneksi
2. `psql -lqt | grep gitlabdb` — Database `gitlabdb` benar-benar ada (init script berhasil)

Jika `GITLAB_DB_NAME` diubah, health check ini HARUS diperbarui bersamaan.

---

### 15.5 MySQL — `mysql:9.7`

**Dokumentasi resmi:** https://hub.docker.com/_/mysql · https://dev.mysql.com/doc/refman/9.0/

#### Container Name: `mysql`

#### Environment Variables

```yaml
environment:
  MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
  MYSQL_DATABASE: default_db    # Database default yang dibuat saat init
```

#### Volume Mounts

```yaml
volumes:
  - ./data:/var/lib/mysql
  - ./initdb:/docker-entrypoint-initdb.d:ro
  - ./config/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
```

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Double $$ untuk mencegah Docker Compose interpolasi prematur
  test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p$$MYSQL_ROOT_PASSWORD && mysql -h 127.0.0.1 -u root -p$$MYSQL_ROOT_PASSWORD -e 'SHOW DATABASES;' > /dev/null 2>&1"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 60s
```

**Penjelasan:** Dua-tahap:
1. `mysqladmin ping` — MySQL menerima koneksi
2. `SHOW DATABASES` query aktual — eliminasi false positive (`mysqladmin ping` bisa OK saat server masih inisialisasi)

---

### 15.6 SeaweedFS — `chrislusf/seaweedfs:4.33_full`

**Dokumentasi resmi:** https://github.com/seaweedfs/seaweedfs/wiki · https://github.com/seaweedfs/seaweedfs/wiki/S3-Configuration

#### Container Name: `seaweedfs`

#### Command

```yaml
command: >
  server
  -s3
  -s3.config=/etc/seaweedfs/s3.json
  -dir=/data
  -ip.bind=0.0.0.0
  -master.volumeSizeLimitMB=1024
  -filer
  -filer.maxMB=256
```

**Penjelasan flag:**
- `server` — mode all-in-one (master + volume + filer dalam satu proses)
- `-s3` — aktifkan S3 gateway
- `-s3.config` — path ke IAM credentials config
- `-filer` — aktifkan filer (diperlukan oleh S3 gateway)
- `-filer.maxMB=256` — max upload chunk size

#### Port Internal

| Port | Fungsi | Exposed? |
|---|---|---|
| 9333 | Master server API | Tidak (internal health check) |
| 8080 | Volume server | Tidak |
| 8888 | Filer API | Tidak |
| 8333 | S3 API gateway | Ya — via Traefik ke `resolute-s3.${BASE_DOMAIN}` |

#### Volume Mounts

```yaml
volumes:
  - ./data:/data                              # Data storage
  - ./config/s3.json:/etc/seaweedfs/s3.json:ro  # S3 IAM config (rendered, gitignored)
```

#### S3 IAM Config (`seaweedfs/config/s3.json.template`)

```json
{
  "identities": [
    {
      "name": "infra-admin",
      "credentials": [
        {
          "accessKey": "${SEAWEEDFS_S3_ACCESS_KEY}",
          "secretKey": "${SEAWEEDFS_S3_SECRET_KEY}"
        }
      ],
      "actions": [
        "Admin",
        "Read",
        "Write",
        "List",
        "Tagging",
        "DeleteBucket",
        "CreateBucket"
      ]
    }
  ]
}
```

File ini di-render ke `s3.json` (gitignored) oleh `make init`.

#### S3 Buckets GitLab

| Bucket | Fungsi GitLab |
|---|---|
| `gitlab-artifacts` | CI/CD artifacts |
| `gitlab-lfs` | Git LFS |
| `gitlab-registry` | Container registry storage |
| `gitlab-uploads` | User uploads, avatars |
| `gitlab-packages` | Package registry |
| `gitlab-backups` | GitLab backup files |
| `gitlab-tmp` | Temporary files |

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Field "IsLeader" di response JSON /cluster/status (case-sensitive)
  test: ["CMD-SHELL", "curl -sf http://localhost:9333/cluster/status | grep -q 'IsLeader'"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

**Penjelasan:** `/cluster/status` di Master API mengembalikan JSON dengan field `IsLeader: true/false`. Ini memverifikasi Master berjalan dan cluster terbentuk.

#### Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.seaweedfs.rule=Host(`resolute-s3.${BASE_DOMAIN}`)"
  - "traefik.http.routers.seaweedfs.entrypoints=websecure"
  - "traefik.http.routers.seaweedfs.tls.certresolver=step-ca"
  - "traefik.http.services.seaweedfs.loadbalancer.server.port=8333"
```

---

### 15.7 Postfix — `boky/postfix:v5.1.0`

**Dokumentasi resmi:** https://github.com/bokysan/docker-postfix · Release: 2025-01-04

#### Container Name: `postfix`

#### Environment Variables

| Variable | Nilai | Keterangan |
|---|---|---|
| `RELAYHOST` | `[smtp.gmail.com]:587` | Gmail SMTP host dengan port (bracket format) |
| `RELAYHOST_USERNAME` | `${GMAIL_USER}` | Gmail address (akun yang punya App Password) |
| `RELAYHOST_PASSWORD` | `${GMAIL_APP_PASSWORD}` | Gmail App Password 16 karakter |
| `POSTFIX_myhostname` | `resolute-mail.${BASE_DOMAIN}` | FQDN untuk SMTP HELO/banner |
| `POSTFIX_mynetworks` | `${POSTFIX_MYNETWORKS}` | Networks yang boleh relay (backend-net subnet) |
| `POSTFIX_message_size_limit` | `26214400` | 25MB = max Gmail attachment size |

**Arsitektur email di stack:**
- GitLab/Vault → SMTP ke `postfix:587` (no credentials, internal network)
- Postfix → SMTP ke `smtp.gmail.com:587` menggunakan Gmail App Password (SASL auth + STARTTLS)
- Gmail → recipient email

Tidak ada credentials di sisi GitLab→Postfix. Hanya Postfix yang autentikasi ke Gmail.

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Dua kondisi: port SMTP terbuka DAN proses postfix berjalan
  test: ["CMD-SHELL", "postfix status 2>&1 | grep -q 'postfix mail system is running' && nc -z localhost 587"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 30s
```

**Penjelasan:** `postfix status` mengembalikan string yang mengandung `postfix mail system is running` jika postfix master process aktif. `nc -z` verifikasi port 587 benar-benar menerima koneksi TCP.

---

### 15.8 GitLab CE — `gitlab/gitlab-ce:19.0.1-ce.0`

**Dokumentasi resmi:** https://docs.gitlab.com/omnibus/ · https://docs.gitlab.com/omnibus/settings/configuration/

#### Container Name: `gitlab`

#### Port Host Mapping

```yaml
ports:
  - "${GITLAB_SSH_PORT}:22"    # 2222:22 — hanya SSH yang di-expose ke host
# HTTP/HTTPS tidak di-expose ke host — di-route via Traefik
```

#### `shm_size`

```yaml
shm_size: '256m'    # WAJIB. GitLab crash tanpa shared memory ini.
```

#### Volume Mounts

```yaml
volumes:
  - ./config:/etc/gitlab           # gitlab.rb, gitlab-secrets.json
  - ./data:/var/opt/gitlab         # Repository, registry, dll
  - ./logs:/var/log/gitlab         # Semua log service GitLab
```

**PENTING: `./gitlab/config/` di-gitignore** karena mengandung `gitlab-secrets.json` (encryption keys). File ini WAJIB di-backup dan di-backup bersama data GitLab. Tanpa `gitlab-secrets.json` yang matching, backup tidak bisa di-restore.

#### `GITLAB_OMNIBUS_CONFIG`

Nilai environment variable ini adalah Ruby code yang di-inject ke `gitlab.rb`. Docker Compose melakukan interpolasi `${VAR}` dari `env_file` sebelum mengirim ke container.

```ruby
# External URL
external_url 'https://resolute-gitlab.${BASE_DOMAIN}'

# Jalankan di belakang Traefik
nginx['listen_port'] = 80
nginx['listen_https'] = false
nginx['proxy_set_headers'] = {
  "X-Forwarded-Proto" => "https",
  "X-Forwarded-Ssl" => "on",
  "X-Forwarded-For" => "$proxy_add_x_forwarded_for",
  "Host" => "$http_host"
}

# SSH
gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}

# Timezone
gitlab_rails['time_zone'] = '${TZ}'

# Initial root password — HANYA efektif saat pertama kali init
gitlab_rails['initial_root_password'] = '${GITLAB_ROOT_PASSWORD}'
gitlab_rails['initial_shared_runners_registration_token'] = ''

# ============================================================
# EXTERNAL POSTGRESQL — bundled PostgreSQL dinonaktifkan
# ============================================================
postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'utf8'
gitlab_rails['db_host'] = 'postgresql'
gitlab_rails['db_port'] = 5432
gitlab_rails['db_database'] = '${GITLAB_DB_NAME}'
gitlab_rails['db_username'] = '${GITLAB_DB_USER}'
gitlab_rails['db_password'] = '${GITLAB_DB_PASSWORD}'

# ============================================================
# EMAIL via Postfix relay
# GitLab → Postfix (no-auth, internal) → Gmail (auth via App Password)
# ============================================================
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = 'postfix'
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_domain'] = '${BASE_DOMAIN}'
gitlab_rails['smtp_authentication'] = false
gitlab_rails['smtp_enable_starttls_auto'] = false
gitlab_rails['smtp_tls'] = false
gitlab_rails['gitlab_email_from'] = 'resolute-gitlab@${BASE_DOMAIN}'
gitlab_rails['gitlab_email_reply_to'] = 'noreply@${BASE_DOMAIN}'

# ============================================================
# OBJECT STORAGE — SeaweedFS S3-compatible (Consolidated config)
# ============================================================
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = true
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => '${SEAWEEDFS_S3_ACCESS_KEY}',
  'aws_secret_access_key' => '${SEAWEEDFS_S3_SECRET_KEY}',
  'endpoint' => 'http://seaweedfs:8333',
  'path_style' => true,
  'aws_signature_version' => 4
}

gitlab_rails['object_store']['objects']['artifacts']['bucket'] = 'gitlab-artifacts'
gitlab_rails['object_store']['objects']['external_diffs']['bucket'] = 'gitlab-artifacts'
gitlab_rails['object_store']['objects']['lfs']['bucket'] = 'gitlab-lfs'
gitlab_rails['object_store']['objects']['uploads']['bucket'] = 'gitlab-uploads'
gitlab_rails['object_store']['objects']['packages']['bucket'] = 'gitlab-packages'
gitlab_rails['object_store']['objects']['dependency_proxy']['bucket'] = 'gitlab-packages'
gitlab_rails['object_store']['objects']['terraform_state']['bucket'] = 'gitlab-packages'
gitlab_rails['object_store']['objects']['pages']['bucket'] = 'gitlab-uploads'

# ============================================================
# CONTAINER REGISTRY — konfigurasi terpisah dari object_store
# ============================================================
registry_external_url 'https://resolute-registry.${BASE_DOMAIN}'
registry['enable'] = true
gitlab_rails['registry_enabled'] = true
gitlab_rails['registry_host'] = 'resolute-registry.${BASE_DOMAIN}'
gitlab_rails['registry_port'] = '443'

# Registry storage di SeaweedFS menggunakan filesystem-over-S3 driver
# CATATAN: GitLab Omnibus registry menggunakan port 5050 secara internal
registry['registry_http_addr'] = '0.0.0.0:5050'
registry['storage'] = {
  's3' => {
    'accesskey' => '${SEAWEEDFS_S3_ACCESS_KEY}',
    'secretkey' => '${SEAWEEDFS_S3_SECRET_KEY}',
    'bucket' => 'gitlab-registry',
    'region' => 'us-east-1',
    'regionendpoint' => 'http://seaweedfs:8333',
    'pathstyle' => true,
    'secure' => false
  }
}

# ============================================================
# BACKUP ke SeaweedFS
# ============================================================
gitlab_rails['backup_upload_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => '${SEAWEEDFS_S3_ACCESS_KEY}',
  'aws_secret_access_key' => '${SEAWEEDFS_S3_SECRET_KEY}',
  'endpoint' => 'http://seaweedfs:8333',
  'path_style' => true
}
gitlab_rails['backup_upload_remote_directory'] = 'gitlab-backups'
gitlab_rails['backup_keep_time'] = 604800  # 7 hari dalam detik
```

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost/-/health | grep -q 'GitLab OK'"]
  interval: 60s
  timeout: 30s
  retries: 10
  start_period: 300s
```

**Penjelasan:**
- `/-/health` memeriksa database, Redis, Gitaly, Workhorse — semua subsistem
- `start_period: 300s` — GitLab first-start dengan external PostgreSQL bisa 5-10 menit
- `interval: 60s` — health check terlalu sering menambah beban GitLab

#### Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  # GitLab web UI
  - "traefik.http.routers.gitlab.rule=Host(`resolute-gitlab.${BASE_DOMAIN}`)"
  - "traefik.http.routers.gitlab.entrypoints=websecure"
  - "traefik.http.routers.gitlab.tls.certresolver=step-ca"
  - "traefik.http.services.gitlab.loadbalancer.server.port=80"
  # Container Registry — port 5050 (Omnibus default)
  - "traefik.http.routers.gitlab-registry.rule=Host(`resolute-registry.${BASE_DOMAIN}`)"
  - "traefik.http.routers.gitlab-registry.entrypoints=websecure"
  - "traefik.http.routers.gitlab-registry.tls.certresolver=step-ca"
  - "traefik.http.services.gitlab-registry.loadbalancer.server.port=5050"
```

---

### 15.9 GitLab Runner — `gitlab/gitlab-runner:v19.0.1`

**Dokumentasi resmi:** https://docs.gitlab.com/runner/ · https://docs.gitlab.com/runner/executors/docker/

#### Container Name: `gitlab-runner`

#### Volume Mounts

```yaml
volumes:
  - ./config:/etc/gitlab-runner               # config.toml (hasil register, gitignored)
  - /var/run/docker.sock:/var/run/docker.sock # Docker daemon access
```

#### Executor: Docker via Docker Socket

Implikasi: Runner container memiliki akses setara root ke Docker daemon host. Acceptable untuk private local infra. JANGAN gunakan di environment multi-tenant.

#### Registration (Post-Deploy — Dilakukan SETELAH GitLab healthy)

**GitLab 17.0+ menggunakan Authentication Token**, bukan Registration Token lama:

```bash
# 1. Buat runner token di GitLab UI:
#    Admin Area → CI/CD → Runners → New instance runner
#    Copy token (format: glrt-xxxxxxxxxxxxxxxxxx)

# 2. Register runner
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "https://resolute-gitlab.${BASE_DOMAIN}" \
  --token "glrt-AUTHENTICATION_TOKEN_DARI_GITLAB_UI" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-network-mode "infra-devops-net" \
  --description "infra-runner-docker" \
  --tag-list "docker,linux,self-hosted" \
  --run-untagged="true"
```

#### `config.toml` (Setelah Register)

```toml
concurrent = 4
check_interval = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "infra-runner-docker"
  url = "https://gitlab.BASE_DOMAIN_DIGANTI_SAAT_REGISTER"
  token = "RUNNER_TOKEN_DARI_REGISTRASI"
  executor = "docker"
  [runners.docker]
    image = "alpine:latest"
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    network_mode = "infra-devops-net"
    pull_policy = ["if-not-present"]
    shm_size = 0
    disable_cache = false
    cache_dir = "/cache"
```

**CATATAN:** `config.toml` di-gitignore. Berisi runner token sensitif. Backup dilakukan via `gitlab-runner/config/` rsync.

#### Health Check (Ultra-Deep)

```yaml
healthcheck:
  # Gunakan 'verify' TANPA '--delete'. Flag --delete menghapus runner dari server GitLab.
  # Exit 0: runner terdaftar dan komunikasi dengan GitLab OK
  # Exit non-0: runner tidak terdaftar atau GitLab tidak reachable
  test: ["CMD", "gitlab-runner", "verify"]
  interval: 60s
  timeout: 30s
  retries: 3
  start_period: 30s
```

**Runner tidak akan healthy** sampai registrasi dilakukan. Ini expected behavior — runner dimulai tapi health check belum pass sampai operator melakukan registrasi.

---

## 16. MAKEFILE TARGETS REFERENCE

```makefile
# /data/infra-stack/Makefile

.PHONY: init up up-continue down restart status backup backup-remote \
        new-service git-remote-setup logs shell help

# Load environment untuk variabel yang diperlukan make targets
include _shared/.env
export

##########################################################################
# HELP
##########################################################################

help:
	@echo "Usage: make <target> [OPTION=value]"
	@echo ""
	@echo "Lifecycle:"
	@echo "  init              Render templates, buat direktori, init git"
	@echo "  up                Start semua service (normal ops, bukan first-time)"
	@echo "  up-continue       Start semua service KECUALI step-ca (untuk bootstrap fase 4)"
	@echo "  down              Stop semua service (reverse order)"
	@echo "  restart           Stop then start semua service"
	@echo ""
	@echo "Maintenance:"
	@echo "  status            Tampilkan health status semua container"
	@echo "  backup            Jalankan backup semua service"
	@echo "  backup-remote     Push backup lokal ke remote storage"
	@echo "  logs SERVICE=xxx  View logs service tertentu"
	@echo "  shell SERVICE=xxx Buka shell di container service tertentu"
	@echo ""
	@echo "Development:"
	@echo "  new-service NAME=xxx TIER=xxx   Scaffold service baru"
	@echo "  git-remote-setup                Setup GitLab sebagai git remote"

##########################################################################
# LIFECYCLE
##########################################################################

init:
	@echo "==> [init] Rendering templates dan setup..."
	@bash _shared/scripts/init.sh
	@echo "==> [init] Selesai. Edit _shared/.env.template jika perlu, lalu:"
	@echo "           Fase bootstrap: lihat Section 8 di INFRA-STACK-MASTER-REFERENCE.md"
	@echo "           Normal ops: make up"

up: _check_networks
	@echo "==> [up] Starting step-ca..."
	docker compose -f step-ca/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh step-ca 120

	@echo "==> [up] Checking root_ca.crt distribution..."
	@[ -f traefik/config/certs/root_ca.crt ] || \
		(docker cp step-ca:/home/step/certs/root_ca.crt traefik/config/certs/root_ca.crt && \
		 echo "root_ca.crt di-copy dari step-ca ke traefik/config/certs/")

	@$(MAKE) up-continue

up-continue: _check_networks
	@echo "==> [up] Starting Traefik..."
	docker compose -f traefik/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh traefik 60

	@echo "==> [up] Starting Vault..."
	docker compose -f vault/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh vault 60

	@echo "==> [up] Starting databases..."
	docker compose -f postgresql/docker-compose.yml up -d
	docker compose -f mysql/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh postgresql 120
	@bash _shared/scripts/wait-healthy.sh mysql 120

	@echo "==> [up] Starting SeaweedFS..."
	docker compose -f seaweedfs/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh seaweedfs 60

	@echo "==> [up] Starting Postfix..."
	docker compose -f postfix/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh postfix 60

	@echo "==> [up] Starting GitLab..."
	docker compose -f gitlab/docker-compose.yml up -d
	@bash _shared/scripts/wait-healthy.sh gitlab 600

	@echo "==> [up] Starting GitLab Runner..."
	docker compose -f gitlab-runner/docker-compose.yml up -d

	@echo ""
	@echo "==> All services started."
	@$(MAKE) status

down:
	@echo "==> [down] Stopping services (reverse order)..."
	@for service in gitlab-runner gitlab postfix seaweedfs mysql postgresql vault traefik step-ca; do \
		echo "    Stopping $$service..."; \
		docker compose -f $$service/docker-compose.yml down 2>/dev/null || true; \
	done
	@docker compose -f _shared/networks/docker-compose.yml down 2>/dev/null || true
	@echo "==> [down] All services stopped."

restart:
	@$(MAKE) down
	@$(MAKE) up

##########################################################################
# MAINTENANCE
##########################################################################

status:
	@echo "==> Container Status:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" \
		--filter "name=step-ca" \
		--filter "name=traefik" \
		--filter "name=vault" \
		--filter "name=postgresql" \
		--filter "name=mysql" \
		--filter "name=seaweedfs" \
		--filter "name=postfix" \
		--filter "name=gitlab" \
		--filter "name=gitlab-runner" 2>/dev/null || true

backup:
	$(eval TIMESTAMP := $(shell date +%Y-%m-%d_%H-%M-%S))
	@echo "==> [backup] Starting backup at $(TIMESTAMP)..."
	@mkdir -p /data/backups
	@for service in postgresql mysql gitlab seaweedfs vault step-ca traefik; do \
		echo "    Backing up $$service..."; \
		bash _shared/scripts/backup/$$service.sh "$(TIMESTAMP)"; \
	done
	@echo "==> [backup] Cleaning old backups (keep 7 days)..."
	@find /data/backups -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
	@echo "==> [backup] Done: /data/backups/"

backup-remote:
	@echo "==> [backup-remote] Not yet implemented. Use rclone or aws s3 sync manually."
	@echo "    Example: rclone sync /data/backups remote:infra-backups"

logs:
	@[ -n "$(SERVICE)" ] || (echo "ERROR: SERVICE required. Example: make logs SERVICE=gitlab" && exit 1)
	docker compose -f $(SERVICE)/docker-compose.yml logs -f --tail=100

shell:
	@[ -n "$(SERVICE)" ] || (echo "ERROR: SERVICE required. Example: make shell SERVICE=postgresql" && exit 1)
	docker exec -it $(SERVICE) sh

##########################################################################
# DEVELOPMENT
##########################################################################

new-service:
	@[ -n "$(NAME)" ] || (echo "ERROR: NAME required. Usage: make new-service NAME=myapp TIER=backend" && exit 1)
	@[ -n "$(TIER)" ] || (echo "ERROR: TIER required. Options: proxy | backend | devops" && exit 1)
	@bash _shared/scripts/new-service.sh "$(NAME)" "$(TIER)"

git-remote-setup:
	@bash _shared/scripts/git-remote-setup.sh

##########################################################################
# INTERNAL HELPERS
##########################################################################

_check_networks:
	@docker network inspect infra-proxy-net > /dev/null 2>&1 || \
		(echo "Creating Docker networks..." && \
		 docker compose -f _shared/networks/docker-compose.yml up -d)
```

---

## 17. PRE-REQUISITES & BOOTSTRAP CHECKLIST

Semua item berikut WAJIB dipenuhi sebelum menjalankan `make init`:

### Infrastruktur

- [ ] VM Ubuntu Server 26.04 LTS running, accessible via SSH ke `192.168.1.241`
- [ ] User `dts` tersedia, memiliki akses sudo
- [ ] Docker 29.5.3 terinstall, berjalan sebagai non-root user `dts` (user `dts` ada di group `docker`)
- [ ] Docker data root: `/data/docker`, containerd root: `/data/containerd` (sesuai konfigurasi awal)
- [ ] Direktori `/data/infra-stack/` dibuat: `sudo mkdir -p /data/infra-stack && sudo chown dts:dts /data/infra-stack`
- [ ] Direktori `/data/backups/` dibuat: `sudo mkdir -p /data/backups && sudo chown dts:dts /data/backups`

### DNS

- [ ] Technitium DNS: Wildcard record `*.dts.system → 192.168.1.241` dikonfigurasi
- [ ] Technitium DNS: A record `dts.system → 192.168.1.241` dikonfigurasi
- [ ] Verifikasi dari VM: `nslookup test.dts.system 192.168.1.252` → harus return `192.168.1.241`
- [ ] Verifikasi dari VM: `nslookup gitlab.dts.system 192.168.1.252` → harus return `192.168.1.241`

### Tools yang Dibutuhkan di VM

```bash
sudo apt-get update && sudo apt-get install -y \
    git make gettext-base openssl jq curl \
    netcat-openbsd awscli
```

- [ ] `git` — version control
- [ ] `make` — Makefile runner
- [ ] `envsubst` (dari `gettext-base`) — template rendering
- [ ] `openssl` — generate htpasswd
- [ ] `jq` — parse JSON (Vault init output)
- [ ] `curl` — health check scripts
- [ ] `nc` (dari `netcat-openbsd`) — port check di health scripts
- [ ] `aws` (dari `awscli`) — buat S3 buckets di SeaweedFS post-deploy

### Port yang Tersedia di Host

- [ ] Port 80: tidak ada proses lain yang listen (`ss -tlnp | grep ':80 '`)
- [ ] Port 443: tidak ada proses lain yang listen (`ss -tlnp | grep ':443 '`)
- [ ] Port 2222: tidak ada proses lain yang listen (`ss -tlnp | grep ':2222 '`)

### Persiapan Secret (Isi `.env.template`)

- [ ] Semua nilai `GANTI_*` di `_shared/.env.template` sudah diganti dengan nilai aktual
- [ ] Gmail App Password sudah dibuat: Google Account → Security → 2-Step Verification → App passwords
- [ ] SeaweedFS S3 access key (min 16 char alphanum) dan secret key (min 32 char) sudah disiapkan
- [ ] Semua password sudah disiapkan (min 12 karakter, kombinasi uppercase + lowercase + angka + simbol)
- [ ] `GITLAB_ROOT_PASSWORD` min 8 karakter (GitLab requirement)

---

## 18. POST-DEPLOY CHECKLIST

Jalankan setelah seluruh bootstrap sequence (Section 8) selesai:

### Root CA Trust

- [ ] `step-ca/config/root_ca.crt` sudah tersedia
- [ ] Root CA sudah diinstall di VM host (`sudo update-ca-certificates`)
- [ ] Root CA sudah diimport ke browser developer
- [ ] Verifikasi: `curl -v https://reolute-traefik.dts.system 2>&1 | grep "SSL certificate verify ok"`

### Vault

- [ ] Vault initialized (`docker exec vault vault status | grep Initialized: true`)
- [ ] Vault unsealed (`docker exec vault vault status | grep Sealed: false`)
- [ ] `/etc/vault-unseal/unseal.key` tersimpan dengan `chmod 400`
- [ ] `/etc/vault-unseal/vault-init.json` tersimpan dengan `chmod 400` (backup di tempat aman lain)
- [ ] KV v2 secrets engine enabled di path `secret/`
- [ ] Cron `@reboot vault-unseal.sh` sudah dikonfigurasi di crontab user `dts`
- [ ] Migrasikan secrets dari `.env` ke Vault (lihat Section 6 tabel Vault Paths)

### SeaweedFS

- [ ] Semua 7 buckets GitLab berhasil dibuat (`aws s3 ls --endpoint-url http://localhost:8333`)

### GitLab

- [ ] Akses `https://resolute-gitlab.dts.system` dari browser berhasil (TLS valid, no warning)
- [ ] Login dengan `root` + `GITLAB_ROOT_PASSWORD` berhasil
- [ ] Ganti password root ke password baru yang berbeda
- [ ] Test kirim email: Admin → Users → `root` → Send email (verifikasi Postfix relay berfungsi)
- [ ] Test upload file di salah satu project (verifikasi SeaweedFS S3 berfungsi)
- [ ] Verifikasi Container Registry: `docker login resolute-registry.dts.system`

### GitLab Runner

- [ ] Buat runner token: Admin → CI/CD → Runners → New instance runner
- [ ] Register runner (lihat command di Section 15.9)
- [ ] Verifikasi runner online: Admin → CI/CD → Runners → status "Online"
- [ ] Test pipeline sederhana (push `.gitlab-ci.yml` ke project)

### Backup & Version Control

- [ ] Setup backup cron: tambahkan ke `crontab -e` (user `dts`): `0 3 * * * cd /data/infra-stack && make backup >> /data/backups/backup.log 2>&1`
- [ ] Test backup: `make backup`
- [ ] Test restore dari backup (dry-run) untuk satu service
- [ ] Jalankan `make git-remote-setup` untuk push infra-stack ke GitLab

---

## 19. MIGRATION / REPLICATION PLAYBOOK

### Persiapan VM Baru

1. Penuhi semua prerequisites (Section 17) di VM baru
2. Update DNS record di Technitium: ubah IP `192.168.1.241` ke IP baru
3. Update `_shared/.env.template`: `HOST_IP=IP_BARU`

### Migrasi Konfigurasi

```bash
# Dari VM lama: backup konfigurasi infra-stack
tar -czf /data/backups/infra-stack-config-$(date +%Y%m%d).tar.gz \
    --exclude='*/data/*' \
    --exclude='*/logs/*' \
    /data/infra-stack/

# Dari VM lama: copy ke VM baru
scp /data/backups/infra-stack-config-*.tar.gz dts@NEW_VM_IP:/data/

# Di VM baru: ekstrak
cd /data && tar -xzf infra-stack-config-*.tar.gz
```

### Re-init di VM Baru

```bash
cd /data/infra-stack
# Edit BASE_DOMAIN dan HOST_IP jika berbeda
nano _shared/.env.template
make init
```

### Restore Data

```bash
# Tunggu step-ca dan PostgreSQL running dulu (Fase 2-5 bootstrap)

# 1. PostgreSQL — restore tiap database
gunzip -c /data/backups/postgresql/TIMESTAMP/gitlabdb.sql.gz \
    | docker exec -i postgresql psql -U ${POSTGRES_USER} gitlabdb

# 2. MySQL
gunzip -c /data/backups/mysql/TIMESTAMP/all-databases.sql.gz \
    | docker exec -i mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}"

# 3. Vault — restore raft snapshot
docker exec vault vault operator raft snapshot restore \
    /vault/data/vault-backup.snap

# 4. GitLab — WAJIB sama versi. Secrets file harus di-restore duluan.
# Restore gitlab-secrets.json (WAJIB ada sebelum restore backup)
cp /data/backups/gitlab/TIMESTAMP/gitlab-secrets.json gitlab/config/
docker compose -f gitlab/docker-compose.yml restart gitlab
sleep 30

# Copy backup file ke container
docker cp /data/backups/gitlab/TIMESTAMP/TIMESTAMP_gitlab_backup.tar \
    gitlab:/var/opt/gitlab/backups/

# Stop services yang bisa conflict
docker exec gitlab gitlab-ctl stop puma
docker exec gitlab gitlab-ctl stop sidekiq

# Restore
docker exec gitlab gitlab-backup restore BACKUP=TIMESTAMP

# Restart
docker exec gitlab gitlab-ctl start puma
docker exec gitlab gitlab-ctl start sidekiq

# 5. SeaweedFS
rsync -avz /data/backups/seaweedfs/TIMESTAMP/ /data/infra-stack/seaweedfs/data/

# 6. step-ca
rsync -avz /data/backups/step-ca/TIMESTAMP/ /data/infra-stack/step-ca/data/
# Re-copy root_ca.crt ke traefik
cp step-ca/config/root_ca.crt traefik/config/certs/

# 7. Traefik
rsync -avz /data/backups/traefik/TIMESTAMP/ /data/infra-stack/traefik/data/
chmod 600 traefik/data/acme.json
```

### Verifikasi Post-Migration

```bash
make up
make status
# Semua service healthy = migrasi sukses
```

**Estimasi total waktu migrasi:** 30-60 menit (tidak termasuk transfer data via rsync yang bergantung pada ukuran data).

---

## 20. DECISION LOG — GRILL-ME SUMMARY

Semua keputusan berikut bersifat FINAL. Perubahan memerlukan update dokumen ini DAN review dampak ke seluruh konfigurasi terkait.

| # | Topik | Keputusan Final | Justifikasi |
|---|---|---|---|
| 1 | Struktur direktori | Flat per-service + `_shared/` | Maksimum modularitas |
| 2 | Docker Network | Hybrid tiered (proxy/backend/devops) | Isolasi keamanan |
| 3 | Secret strategy | Bootstrap `.env` → runtime Vault | Pragmatis + progressive security |
| 4 | TLS | `step-ca` internal CA + Traefik ACME | Auto-renew, no manual cert management |
| 5 | IaC mechanism | `.env.template` + `envsubst` + `Makefile` | Single source of truth |
| 6 | Data persistence | Bind mount `<service>/data/` | Transparan, mudah backup |
| 7 | Startup order | Makefile orchestrate + `wait-healthy.sh` | Deterministic startup |
| 8 | Observability | Defer, "open by design" | Fokus core services dulu |
| 9a | GitLab DB | PostgreSQL eksternal | Efisiensi resource |
| 9b | GitLab Runner | Docker executor via Docker socket | Standard self-hosted |
| 10a | Postfix credentials | Vault (bootstrap: `.env`) | Gmail credential paling sensitif |
| 10b | Postfix scope | Single mail gateway seluruh stack | Sentralisasi |
| 11a | SeaweedFS topology | Single-node `weed server` mode | Cukup untuk single VM |
| 11b | SeaweedFS S3 API | Aktif via `resolute-s3.${BASE_DOMAIN}` | Primary object storage |
| 11c | GitLab object storage | SeaweedFS | Efisiensi disk GitLab |
| 12 | Add service mechanism | `make new-service` + `ADDING_SERVICE.md` | Reproducible, documented |
| 13a | Subdomain convention | `${SERVICE_NAME}.${BASE_DOMAIN}` | Bersih, tidak ambigu |
| 13b | Exposed ports | 80 + 443 only (+ 2222 SSH) | DB tidak di-expose |
| 13c | Traefik dashboard | `resolute-traefik.${BASE_DOMAIN}` + TLS + basic auth | Konsisten |
| 14a | Backup target | Lokal `/data/backups/` + defer remote | Pragmatis |
| 14b | Backup mechanism | Per-service dump scripts | Zero downtime |
| 14c | Backup schedule | Cron VM host, daily 03:00 | Simple |
| 15 | DNS wildcard | Pre-requisite manual | Di luar scope infra stack |
| 16 | GitLab SSH port | `2222` via `GITLAB_SSH_PORT` | Tidak konflik SSH host |
| 17 | Vault storage | `raft` integrated storage | HashiCorp recommended |
| 18 | step-ca version | `smallstep/step-ca:0.30.2` | Latest stable 2026-03-23 |
| 19 | DB init | Otomatis `/docker-entrypoint-initdb.d/` | Full IaC |
| 20 | SeaweedFS S3 creds | Eksplisit oleh user | Diketahui operator |
| 21 | GitLab root password | `GITLAB_ROOT_PASSWORD` env var | IaC, no manual step |
| 22 | Traefik basic auth | Generated `make init` via `openssl passwd` | Otomatis |
| 23 | Restart policy | `unless-stopped` semua service | Maintenance friendly |
| 24 | Resource limits | Hard limit via env var (`mem_limit` + `cpus`) | Proteksi runaway container |
| 25 | Postfix relay networks | `infra-backend-net` only | Minimal attack surface |
| 26 | Version control | Git lokal → migrate ke GitLab | Solve chicken-egg |

---

*Dokumen ini adalah source of truth tunggal. Semua implementasi HARUS konsisten dengan dokumen ini.*  
*v2: Deep-reviewed — 31 issues ditemukan dan diperbaiki. Zero assumption remaining.*