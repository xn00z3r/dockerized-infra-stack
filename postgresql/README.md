# PostgreSQL — Database Server

Image: `postgres:17.10`

## Fungsi

Database relasional. Melayani GitLab (database `gitlabdb`).
Tersedia untuk service lain yang membutuhkan PostgreSQL.

## Akses

Internal only via `infra-backend-net`:
- Host: `postgresql` (container name)
- Port: `5432`
- Superuser: nilai `POSTGRES_USER` dari `.env`

Dari luar VM (development):
```bash
ssh -L 5432:localhost:5432 dts@192.168.1.241
# Kemudian connect ke localhost:5432
```

## Init Scripts

Dieksekusi SEKALI saat data directory kosong:

| File | Status | Fungsi |
|---|---|---|
| `initdb/01-gitlab.sql.template` | Committed | Template (berisi ${VAR}) |
| `initdb/01-gitlab.sql` | Gitignored | Hasil render (berisi password) |
| `initdb/99-extensions.sql` | Committed | PostgreSQL extensions GitLab |

## Catatan PGDATA

`PGDATA=/var/lib/postgresql/data/pgdata` — subdirectory dalam bind mount.
Data aktual berada di `./data/pgdata/`, bukan langsung di `./data/`.
Ini mencegah error permission `lost+found`.
