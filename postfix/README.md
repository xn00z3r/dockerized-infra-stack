# Postfix — SMTP Relay via Gmail

Image: `boky/postfix:v5.1.0`

## Fungsi

Single mail gateway untuk seluruh infra stack.
Merelay email dari service internal ke Internet via Gmail SMTP.

## Arsitektur

```
GitLab / Vault / service lain
    ↓ SMTP ke postfix:587 (no auth, internal network)
Postfix
    ↓ SMTP ke smtp.gmail.com:587 (SASL + STARTTLS via Gmail App Password)
Gmail
    ↓
Recipient email
```

## Konfigurasi Service yang Menggunakan Postfix

Semua service yang perlu kirim email dikonfigurasi ke:
- **SMTP Host:** `postfix` (container name, resolved via infra-backend-net)
- **SMTP Port:** `587`
- **Auth:** TIDAK diperlukan (internal relay)

Contoh konfigurasi GitLab:
```ruby
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = 'postfix'
gitlab_rails['smtp_port'] = 587
gitlab_rails['smtp_authentication'] = false
```

## Gmail App Password

Buat di: Google Account → Security → 2-Step Verification → App passwords
- Pilih "Other (custom name)"
- Masukkan nama: "infra-stack postfix"
- Copy 16-character password ke `GMAIL_APP_PASSWORD` di `.env.template`

## Relay Networks

Hanya container di `infra-backend-net` yang diizinkan relay.
Nilai di `POSTFIX_MYNETWORKS`: `127.0.0.0/8,172.20.1.0/24`
