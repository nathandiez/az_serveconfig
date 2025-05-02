#!/usr/bin/env bash
# deploy.sh - Simple deployment script for nedserveconfig
set -e

# Configuration
TARGET_HOSTNAME="nedserveconfig"

# Check for --nuke flag
if [[ "$1" == "--nuke" ]]; then
  NUKE_MODE=true
  echo "Flag --nuke detected: Will recreate VM before configuring"
else
  NUKE_MODE=false
  echo "No --nuke flag: Will only configure the existing VM"
fi

# Source Proxmox environment variables
source ./set-proxmox-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Run Terraform if in nuke mode
if [ "$NUKE_MODE" = true ]; then
  echo "Starting with a clean slate..."
  rm -f terraform.tfstate terraform.tfstate.backup
  
  echo "Initializing Terraform..."
  terraform init
  
  echo "Creating new VM..."
  terraform apply -auto-approve
fi

# Wait a bit for VM to fully initialize
echo "Waiting for VM to initialize and get an IP address..."
sleep 60

# Get the IP address using multiple methods
get_ip() {
  # Try terraform output first
  local ip=$(terraform output -raw server_ip 2>/dev/null || echo "")
  
  # Check if it's valid
  if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "No IP assigned yet" ] && [ "$ip" != "127.0.0.1" ]; then
    echo "$ip"
    return 0
  fi
  
  # Try to extract from terraform state
  ip=$(terraform refresh > /dev/null 2>&1; terraform show | grep -A 5 "ipv4_addresses" | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -n 1)
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  # Try DNS resolution
  ip=$(ping -c 1 ${TARGET_HOSTNAME}.local 2>/dev/null | head -n 1 | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}')
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  # If all else fails
  echo ""
  return 1
}

# Try multiple times to get a valid IP
for i in {1..5}; do
  echo "Attempt $i to get IP address..."
  IP=$(get_ip)
  
  if [ -n "$IP" ]; then
    echo "Found IP: $IP"
    break
  fi
  
  echo "No valid IP found, waiting before trying again..."
  sleep 30
done

# Validate IP address
if [ -z "$IP" ]; then
  echo "Error: Could not retrieve a valid IP address for $TARGET_HOSTNAME."
  echo "You may need to check the Proxmox web UI or console to see what's happening."
  exit 1
fi

echo "VM IP address: $IP"

# Update Ansible inventory
cd ../ansible
sed -i '' "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

# Wait for SSH to become available
echo "Waiting for SSH to become available..."
MAX_SSH_WAIT=300 # 5 minutes
START_TIME=$(date +%s)

while true; do
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
    echo "SSH is available!"
    break
  fi
  
  # Check if we've waited too long
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
  
  if [ $ELAPSED_TIME -gt $MAX_SSH_WAIT ]; then
    echo "Timed out waiting for SSH. You may need to check the VM console."
    exit 1
  fi
  
  echo "Still waiting for SSH..."
  sleep 10
done

# Run Ansible playbook
echo "Running Ansible to configure the server..."
ansible-playbook playbooks/serve_config.yml

echo "Deployment complete! Server is now running at http://$IP:5000"