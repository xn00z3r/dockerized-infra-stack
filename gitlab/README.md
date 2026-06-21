# GitLab CE — SCM Server

Image: `gitlab/gitlab-ce:19.0.1-ce.0`

## Akses

| Endpoint | URL |
|---|---|
| Web UI | `https://gitlab.dts.system` |
| Container Registry | `https://registry.dts.system` |
| SSH | `ssh://git@192.168.1.241:2222` |

## Konfigurasi

Seluruh konfigurasi GitLab via `GITLAB_OMNIBUS_CONFIG` environment variable (Ruby code).
Untuk mengubah konfigurasi: edit `docker-compose.yml`, lalu `docker compose restart gitlab`.

### Integrasi Stack

| Komponen | Service | Protokol |
|---|---|---|
| Database | `postgresql:5432` | PostgreSQL |
| Object Storage | `seaweedfs:8333` | S3-compatible API |
| Email | `postfix:587` | SMTP (no auth) |
| TLS | Traefik | HTTPS termination |

## Volume Penting

```
./config/  → /etc/gitlab   (gitlab.rb, gitlab-secrets.json)
./data/    → /var/opt/gitlab (repositories, uploads)
./logs/    → /var/log/gitlab
```

**PENTING:** `./config/gitlab-secrets.json` WAJIB di-backup bersamaan dengan `./data/`.
Tanpa `gitlab-secrets.json` yang matching, backup tidak bisa di-restore.

## SSH Clone Config

Tambahkan ke `~/.ssh/config` di client:
```
Host gitlab.dts.system
    HostName 192.168.1.241
    Port 2222
    User git
```

Kemudian: `git clone git@gitlab.dts.system:namespace/repo.git`

## Post-Deploy (First Time)

1. Login: `https://gitlab.dts.system` → user `root` + password dari `GITLAB_ROOT_PASSWORD`
2. Ganti password root ke password permanent
3. Buat GitLab Runner token: Admin → CI/CD → Runners → New instance runner
4. Register runner: `make shell SERVICE=gitlab-runner` → ikuti instruksi di gitlab-runner/README.md
5. Test Container Registry: `docker login registry.dts.system`

## Backup & Restore

### Backup
```bash
make backup   # Atau manual: docker exec gitlab gitlab-backup create
```

### Restore (PENTING: urutan ini wajib diikuti)
1. Restore `gitlab-secrets.json` terlebih dahulu
2. Stop puma dan sidekiq
3. `docker exec gitlab gitlab-backup restore BACKUP=TIMESTAMP`
4. Restart gitlab
