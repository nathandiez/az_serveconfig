#!/usr/bin/env bash
# set-proxmox-env.sh

export PROXMOX_VE_API_TOKEN='root@pam!terraform=cd03658f-d1e3-45cd-88a8-fbb68340640a'

# --- Other Optional Vars (if endpoint/insecure removed from provider block) ---
# export PROXMOX_VE_ENDPOINT='https://192.168.5.5:8006'
# export PROXMOX_VE_INSECURE='true' # Use string 'true' or '1'

echo '✅ Proxmox Terraform environment variables set (using PROXMOX_VE_API_TOKEN).'