# Pre-requisites — WAJIB dipenuhi sebelum `make init`

Semua item berikut harus terpenuhi sebelum menjalankan `make init`.

## 1. Infrastruktur VM

- [ ] VM Ubuntu Server 26.04 LTS running, accessible via SSH ke `192.168.1.241`
- [ ] User `dts` tersedia, memiliki akses sudo
- [ ] Docker 29.5.3 terinstall, berjalan sebagai non-root user `dts`
  - `docker ps` (tanpa sudo) harus berhasil
  - User `dts` harus ada di group `docker`: `groups dts | grep docker`
- [ ] Docker data root: `/data/docker`
- [ ] Direktori `/data/infra-stack/` ada dan dimiliki user `dts`:
  ```bash
  sudo mkdir -p /data/infra-stack && sudo chown dts:dts /data/infra-stack
  ```
- [ ] Direktori `/data/backups/` ada dan dimiliki user `dts`:
  ```bash
  sudo mkdir -p /data/backups && sudo chown dts:dts /data/backups
  ```

## 2. DNS

- [ ] Technitium DNS Server berjalan di `192.168.1.252`
- [ ] Wildcard record: `*.dts.system → 192.168.1.241` sudah dikonfigurasi
- [ ] A record: `dts.system → 192.168.1.241` sudah dikonfigurasi
- [ ] Verifikasi dari VM:
  ```bash
  nslookup test.dts.system 192.168.1.252
  # Expected: Address: 192.168.1.241
  nslookup gitlab.dts.system 192.168.1.252
  # Expected: Address: 192.168.1.241
  ```

## 3. Tools di VM

```bash
sudo apt-get update && sudo apt-get install -y \
    git make gettext-base openssl jq curl \
    netcat-openbsd awscli
```

- [ ] `git` — version control
- [ ] `make` — Makefile runner
- [ ] `envsubst` (dari `gettext-base`) — template rendering
- [ ] `openssl` — generate htpasswd untuk Traefik basic auth
- [ ] `jq` — parse JSON (Vault init output, dll)
- [ ] `curl` — health check scripts
- [ ] `nc` / `netcat` — port check di health scripts
- [ ] `aws` — buat S3 buckets di SeaweedFS (post-deploy)

## 4. Port yang Tersedia di Host

```bash
ss -tlnp | grep -E ':80 |:443 |:2222 '
# Output harus kosong — tidak ada proses lain yang listen di port tersebut
```

- [ ] Port 80: tidak ada proses lain
- [ ] Port 443: tidak ada proses lain
- [ ] Port 2222: tidak ada proses lain (GitLab SSH)

## 5. Persiapan Secrets di `.env.template`

- [ ] Buat salinan kerja: `cp _shared/.env.template _shared/.env.template.bak`
- [ ] Edit `_shared/.env.template`, ganti **semua** nilai `GANTI_*`:
  - `TRAEFIK_ADMIN_PASSWORD` — password kuat untuk Traefik dashboard
  - `POSTGRES_PASSWORD` — password PostgreSQL superuser
  - `GITLAB_DB_PASSWORD` — password user GitLab di PostgreSQL
  - `MYSQL_ROOT_PASSWORD` — password MySQL root
  - `SEAWEEDFS_S3_ACCESS_KEY` — min 16 karakter alphanum
  - `SEAWEEDFS_S3_SECRET_KEY` — min 32 karakter alphanum
  - `GMAIL_USER` — alamat Gmail Anda
  - `GMAIL_APP_PASSWORD` — App Password 16 karakter dari Google
  - `GITLAB_ROOT_PASSWORD` — min 8 karakter
- [ ] Gmail App Password: Google Account → Security → 2-Step Verification → App passwords
- [ ] Semua password min 12 karakter, kombinasi uppercase + lowercase + angka + simbol

## 6. Setelah Prerequisites Terpenuhi

```bash
cd /data/infra-stack
make init
```

Kemudian ikuti **Bootstrap Sequence** di `INFRA-STACK-MASTER-REFERENCE.md` Section 8.
