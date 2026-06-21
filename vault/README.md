# Vault — Secret Management

Image: `hashicorp/vault:2.0`

## Fungsi

Penyimpanan dan management secrets/credentials. Storage backend: Raft Integrated Storage.

## Akses

- UI: `https://vault.dts.system`
- Internal API: `http://vault:8200` (dari container di infra-backend-net)

## Bootstrap (First-Time Only)

```bash
# 1. Inisialisasi Vault (SEKALI SEUMUR HIDUP cluster ini)
docker exec vault vault operator init \
  -key-shares=1 -key-threshold=1 -format=json \
  > /tmp/vault-init.json

# 2. Simpan output di tempat aman
sudo mkdir -p /etc/vault-unseal
sudo mv /tmp/vault-init.json /etc/vault-unseal/vault-init.json
sudo chmod 400 /etc/vault-unseal/vault-init.json

# 3. Simpan unseal key
sudo jq -r '.unseal_keys_b64[0]' /etc/vault-unseal/vault-init.json | \
  sudo tee /etc/vault-unseal/unseal.key > /dev/null
sudo chmod 400 /etc/vault-unseal/unseal.key

# 4. Unseal
UNSEAL_KEY=$(sudo cat /etc/vault-unseal/unseal.key)
docker exec vault vault operator unseal "$UNSEAL_KEY"

# 5. Login dan setup
ROOT_TOKEN=$(sudo jq -r '.root_token' /etc/vault-unseal/vault-init.json)
docker exec vault vault login "$ROOT_TOKEN"
docker exec vault vault secrets enable -path=secret kv-v2

# 6. Setup cron auto-unseal
(crontab -l 2>/dev/null; echo "@reboot sleep 30 && bash /data/infra-stack/_shared/scripts/vault-unseal.sh") | crontab -
```

## Auto-Unseal

Vault di-unseal otomatis setelah VM restart via:
`_shared/scripts/vault-unseal.sh` (dipanggil via cron @reboot)

Unseal key: `/etc/vault-unseal/unseal.key` (di luar git, chmod 400)
