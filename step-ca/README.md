# step-ca — Internal PKI Certificate Authority

Image: `smallstep/step-ca:0.30.2`

## Fungsi

Internal CA yang menerbitkan TLS certificate untuk semua service di infra-stack.
Traefik terintegrasi via ACME protocol untuk mendapatkan wildcard cert `*.dts.system`.

## Port Internal

| Port | Protokol | Fungsi |
|---|---|---|
| 9000 | HTTPS | CA API + ACME server |

## Data

Semua state CA (root key, intermediate key, certs, config, database) tersimpan di `./data/`
yang di-mount ke `/home/step` di dalam container.

## Bootstrap (First-Time Only)

Setelah container healthy:

```bash
# Ambil root CA certificate
docker cp step-ca:/home/step/certs/root_ca.crt step-ca/config/root_ca.crt

# Copy ke Traefik
cp step-ca/config/root_ca.crt traefik/config/certs/root_ca.crt

# Install ke sistem Ubuntu
sudo cp step-ca/config/root_ca.crt /usr/local/share/ca-certificates/infra-stack-ca.crt
sudo update-ca-certificates

# Ambil fingerprint (simpan ini)
docker exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt
```

## ACME Directory

`https://ca.dts.system:9000/acme/acme/directory`

Digunakan oleh Traefik sebagai `caServer` untuk request TLS certificates.
