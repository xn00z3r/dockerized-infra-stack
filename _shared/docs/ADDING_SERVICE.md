# Menambahkan Service Baru ke Infra-Stack

Contract ini adalah panduan wajib untuk onboarding service baru.
Setiap service baru HARUS mengikuti semua ketentuan berikut.

## Cara Membuat Service Baru

```bash
make new-service NAME=myapp TIER=backend
```

`TIER` options:
- `proxy` → bergabung ke `infra-proxy-net` (di-expose via Traefik)
- `backend` → bergabung ke `infra-backend-net` (internal: DB, storage, messaging)
- `devops` → bergabung ke `infra-devops-net` (CI/CD related)

Service yang butuh UI/API publik DAN bergantung pada service backend bisa join dua network:
uncomment `infra-proxy-net` di `networks:` section compose file-nya.

## Checklist Wajib Sebelum Service Dianggap "Production-Ready"

### docker-compose.yml

- [ ] Image menggunakan **versi eksplisit** — TIDAK boleh `:latest`
- [ ] `container_name:` didefinisikan eksplisit (digunakan `wait-healthy.sh`)
- [ ] `restart: unless-stopped` (bukan `always` atau `on-failure`)
- [ ] `env_file:` mereferensi `../_shared/.env` DAN `.env` lokal
- [ ] `networks:` sesuai dengan tier yang dipilih (external: true)
- [ ] `mem_limit:` dan `cpus:` menggunakan variable dari env (bukan hardcode)
- [ ] `healthcheck:` di-implementasikan dengan **ultra-deep check**:
  - Bukan hanya cek port terbuka
  - Harus memverifikasi fungsionalitas aktual service
  - `start_period` disesuaikan dengan waktu startup service
- [ ] Observability labels ada dalam kondisi **di-comment** (siap uncomment)
- [ ] Volume `data/` menggunakan bind mount ke `./data/` (bukan named volume)

### .env.template

- [ ] Resource limit variables (`MYAPP_MEM_LIMIT`, `MYAPP_CPUS`) ada di `_shared/.env.template`
- [ ] Semua variabel service-spesifik ada di service `.env.template`
- [ ] Tidak ada credentials yang hardcode

### Makefile Integration

- [ ] Tambahkan step `docker compose -f myapp/docker-compose.yml up -d` di target `up`
  pada **posisi yang tepat** sesuai dependency chain
- [ ] Tambahkan `wait-healthy.sh myapp <timeout>` setelah `up -d` (jika service lain depend padanya)
- [ ] Tambahkan stop step di target `down` (dalam **reverse order**)

### Backup (jika service punya data persisten)

- [ ] Buat script `_shared/scripts/backup/myapp.sh`
- [ ] Tambahkan ke loop di `make backup` target

### Dokumentasi

- [ ] `README.md` di direktori service berisi:
  - Fungsi service
  - Port internal dan eksternal (jika ada)
  - Cara akses/konfigurasi
  - Variabel environment yang diperlukan
  - Catatan khusus

## Naming Convention

| Item | Convention | Contoh |
|---|---|---|
| Direktori service | kebab-case | `my-app/` |
| Container name | kebab-case | `my-app` |
| Subdomain | `${name}.${BASE_DOMAIN}` | `my-app.dts.system` |
| Traefik router | `${name}` | `traefik.http.routers.my-app` |
| Env var prefix | `UPPERCASE_` | `MY_APP_MEM_LIMIT` |
| Vault path | `secret/infra/${name}` | `secret/infra/my-app` |

## Network Selection Guide

```
Service hanya butuh akses ke DB/storage?     → backend
Service expose UI/API ke pengguna?           → proxy (+ backend jika butuh DB)
Service berinteraksi dengan GitLab?          → devops
Service adalah CI/CD tool?                   → devops
```
