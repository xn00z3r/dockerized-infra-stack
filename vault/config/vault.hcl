# =============================================================================
# vault.hcl — Vault Server Configuration
# Di-mount ke container sebagai: /vault/config/vault.hcl
#
# PENTING: Jangan set VAULT_LOCAL_CONFIG env var bersamaan dengan file ini
# Keduanya mendefinisikan konfigurasi Vault dan akan conflict (F07 FIX)
# =============================================================================

# Enable Vault UI
ui = true

# Required by newer Vault versions
disable_mlock = true

# Raft Integrated Storage — keputusan final, tidak bisa diubah tanpa vault operator migrate
# HashiCorp recommended sejak v1.4+, future-proof untuk multi-node
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

# TCP Listener
# tls_disable = 1 karena TLS termination dilakukan oleh Traefik
# Vault tidak pernah di-expose langsung — hanya via infra-proxy-net ke Traefik
# dan infra-backend-net ke service internal
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# API address — digunakan oleh raft untuk cluster communication
api_addr     = "http://vault:8200"
cluster_addr = "http://vault:8201"
