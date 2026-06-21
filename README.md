# infra-stack

Infrastructure stack berbasis Docker untuk VM Ubuntu Server 26.04 LTS.

## Stack

| Service | Image | Domain |
|---|---|---|
| step-ca | smallstep/step-ca:0.30.2 | ca.dts.system |
| Traefik | traefik:v3.7.5 | traefik.dts.system |
| Vault | hashicorp/vault:2.0 | vault.dts.system |
| PostgreSQL | postgres:17.10 | internal |
| MySQL | mysql:9.7 | internal |
| SeaweedFS | chrislusf/seaweedfs:4.33_full | s3.dts.system |
| Postfix | boky/postfix:v5.1.0 | internal |
| GitLab CE | gitlab/gitlab-ce:19.0.1-ce.0 | gitlab.dts.system |
| GitLab Runner | gitlab/gitlab-runner:v19.0.1 | internal |

## Quick Start

```bash
# 1. Edit environment template
cp _shared/.env.template _shared/.env
nano _shared/.env.template   # Isi semua nilai GANTI_*

# 2. Initialize
make init

# 3. Bootstrap (first-time only) — lihat INFRA-STACK-MASTER-REFERENCE.md Section 8
# 4. Normal operations
make up
make status
```

## Documentation

Lihat `INFRA-STACK-MASTER-REFERENCE.md` untuk dokumentasi lengkap.
