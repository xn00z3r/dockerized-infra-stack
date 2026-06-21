# MySQL — Database Server

Image: `mysql:9.7`

## Fungsi

Database MySQL untuk kebutuhan project development.
Tidak digunakan oleh service infra saat ini — tersedia untuk project Anda.

## Akses

Internal only via `infra-backend-net`:
- Host: `mysql` (container name)
- Port: `3306`
- Root user: `root` / nilai `MYSQL_ROOT_PASSWORD` dari `.env`

Dari luar VM:
```bash
ssh -L 3306:localhost:3306 dts@192.168.1.241
# Kemudian connect ke localhost:3306
```

## Menambah Database/User untuk Project

Buat file baru di `initdb/` (hanya dieksekusi saat data dir kosong):

```sql
-- initdb/02-myproject.sql
CREATE DATABASE IF NOT EXISTS myproject CHARACTER SET utf8mb4;
CREATE USER 'myuser'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON myproject.* TO 'myuser'@'%';
FLUSH PRIVILEGES;
```
