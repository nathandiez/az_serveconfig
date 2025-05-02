#!/usr/bin/env bash
# deploy.sh - Deployment script for nedserveconfig on Azure
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

# Source Azure environment variables
source ./set-azure-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Get the current IP address for host key removal
CURRENT_IP=$(terraform output -raw public_ip 2>/dev/null || echo "")

# Run Terraform if in nuke mode
if [ "$NUKE_MODE" = true ]; then
  echo "Starting with a clean slate..."
  
  # Remove host key if we have a current IP
  if [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "null" ]; then
    echo "Removing SSH host key for $CURRENT_IP..."
    ssh-keygen -R "$CURRENT_IP"
  fi
  
  # Initialize Terraform first
  echo "Initializing Terraform..."
  terraform init
  
  # Check if resource group exists and import it if needed
  echo "Checking if resource group already exists in Azure..."
  if az group show --name rg-serve-config >/dev/null 2>&1; then
    echo "Resource group exists in Azure but might not be in Terraform state"
    echo "Attempting to import resource group into Terraform state..."
    terraform import azurerm_resource_group.rg /subscriptions/c1508b64-fb45-46f5-bf88-511ae65059d0/resourceGroups/rg-serve-config || true
  fi
  
  # Check for persistent IP and import if needed
  echo "Verifying persistent IP exists..."
  if az network public-ip show --name ned-serve-config-persistent --resource-group rg-persistent-resources >/dev/null 2>&1; then
    echo "✅ Persistent IP found"
  else
    echo "❌ ERROR: Persistent IP 'ned-serve-config-persistent' not found in resource group 'rg-persistent-resources'"
    echo "Please create the persistent IP first. See README for instructions."
    exit 1
  fi
  
  # Try targeted destruction of resources except resource group
  echo "Removing previous VM resources..."
  terraform state list | grep -v "azurerm_resource_group.rg" | while read -r resource; do
    echo "Destroying $resource..."
    terraform destroy -target="$resource" -auto-approve || true
  done
  
  echo "Creating new VM in Azure..."
  terraform apply -auto-approve
fi

# Get the IP address using terraform output
echo "Getting VM public IP address..."
# Retry a few times because IP might not be immediately available after VM creation
for i in {1..10}; do
  IP=$(terraform output -raw public_ip 2>/dev/null || echo "")
  
  if [ -n "$IP" ] && [ "$IP" != "null" ]; then
    echo "Found IP: $IP"
    break
  fi
  
  echo "Waiting for IP address to be assigned... (attempt $i)"
  sleep 15
  terraform refresh > /dev/null 2>&1
done

# Validate IP address
if [ -z "$IP" ] || [ "$IP" == "null" ]; then
  echo "Error: Could not retrieve a valid IP address for $TARGET_HOSTNAME."
  echo "You may need to check the Azure portal or run terraform refresh."
  exit 1
fi

echo "VM IP address: $IP"

# Update Ansible inventory
cd ../ansible
sed -i.bak "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

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
    echo "Timed out waiting for SSH. You may need to check the VM console in Azure portal."
    exit 1
  fi
  
  echo "Still waiting for SSH..."
  sleep 10
done

# Run Ansible playbook
echo "Running Ansible to configure the server..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/serve_config.yml

# Display IP and FQDN information at the end
echo "Deployment complete! Server is now running at http://$IP:5000"
echo "FQDN: $(cd ../terraform && terraform output -raw fqdn 2>/dev/null || echo "Not available")"
echo ""
echo "IP Address: $IP"

# Set up SSL certificates if in nuke mode
if [ "$NUKE_MODE" = true ]; then
  echo "Setting up SSL certificates..."
  DOMAIN=$(cd ../terraform && terraform output -raw fqdn 2>/dev/null)
  if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "null" ]; then
    echo "Setting up SSL certificates for $DOMAIN"
    # Use the same SSH options to ignore host key verification
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null nathan@"$IP" "sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email nathandiez12@gmail.com"
    echo "SSL certificates installed successfully!"
    echo "Your secure service is now available at https://$DOMAIN"
  else
    echo "Warning: Could not retrieve FQDN. SSL certificate installation skipped."
  fi
fi