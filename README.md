# infra-stack

Infrastructure stack berbasis Docker untuk VM Ubuntu Server 26.04 LTS.

## Stack

| Service | Image | Domain |
|---|---|---|
| step-ca | smallstep/step-ca:0.30.2 | resolute-ca.dts.system |
| Traefik | traefik:v3.7.5 | resolute-traefik.dts.system |
| Vault | hashicorp/vault:2.0 | resolute-vault.dts.system |
| PostgreSQL | postgres:17.10 | internal |
| MySQL | mysql:9.7 | internal |
| SeaweedFS | chrislusf/seaweedfs:4.33_full | resolute-s3.dts.system |
| Postfix | boky/postfix:v5.1.0 | internal |
| GitLab CE | gitlab/gitlab-ce:19.0.1-ce.0 | resolute-gitlab.dts.system |
| GitLab Runner | gitlab/gitlab-runner:v19.0.1 | resolute-internal |

## Quick Start

```bash
# 1. Edit templates
nano _shared/.env.template
nano _shared/.secrets.template

# 2. Initialize stack
make init

# 3. First-time bootstrap
make up

# 4. Check status
make status
```

## Operational Notes
- make init akan merender _shared/.env dari _shared/.env.template dan _shared/.secrets.template.
- Jangan commit file _shared/.env.
- Secret runtime harus tetap berada di jalur secret management yang sah, bukan di template publik.
- Jika step-ca diregenerate, jalankan make up untuk menyinkronkan root_ca.crt ke Traefik.



## Documentation

Dokumentasi teknis dan runbook ada di:

- _shared/docs/PREREQUISITES.md
- _shared/docs/ADDING_SERVICE.md
- _shared/scripts/
