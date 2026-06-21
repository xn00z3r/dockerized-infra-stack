# GitLab Runner — CI/CD Job Executor

Image: `gitlab/gitlab-runner:v19.0.1`

## Fungsi

Mengeksekusi CI/CD pipeline job GitLab sebagai Docker container yang terisolasi.
Executor: Docker via Docker socket (`/var/run/docker.sock`).

## Registrasi (Post-Deploy — WAJIB dilakukan setelah GitLab healthy)

GitLab 17.0+ menggunakan **Authentication Token** (bukan Registration Token lama).

### Langkah Registrasi

**1. Buat runner token di GitLab UI:**
```
https://gitlab.dts.system → Admin → CI/CD → Runners → New instance runner
```
- Pilih "Run untagged jobs": ✓
- Tags: `docker,linux,self-hosted`
- Copy token (format: `glrt-xxxxxxxxxxxxxxxxxx`)

**2. Register runner:**
```bash
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.dts.system" \
  --token "glrt-AUTHENTICATION_TOKEN_DARI_STEP_1" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-network-mode "infra-devops-net" \
  --description "infra-runner-docker" \
  --tag-list "docker,linux,self-hosted" \
  --run-untagged="true"
```

**3. Verifikasi:**
```
https://gitlab.dts.system → Admin → CI/CD → Runners → status "Online" ✓
```

## `config.toml` (Generated setelah registrasi)

File ini di-generate otomatis oleh `gitlab-runner register`. Contoh isi:
```toml
concurrent = 4
check_interval = 0

[[runners]]
  name = "infra-runner-docker"
  url = "https://gitlab.dts.system"
  token = "RUNNER_TOKEN"
  executor = "docker"
  [runners.docker]
    image = "alpine:latest"
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
    network_mode = "infra-devops-net"
    pull_policy = ["if-not-present"]
```

**CATATAN:** `config/` direktori di-gitignore karena berisi runner token sensitif.

## Contoh `.gitlab-ci.yml` untuk Testing

```yaml
test-pipeline:
  stage: test
  image: alpine:latest
  script:
    - echo "Pipeline berjalan di infra-runner-docker"
    - docker --version
  tags:
    - docker
```

## Keamanan

Runner memiliki akses Docker socket = akses setara root ke Docker daemon host.
Acceptable untuk private local infra. Jangan gunakan di environment shared/multi-tenant.
