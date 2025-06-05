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

# Function to safely get terraform output
get_terraform_output() {
  local output_name="$1"
  local result
  
  # Try from terraform subdirectory first (where the actual resources are defined)
  pushd terraform > /dev/null
  result=$(terraform output -raw "$output_name" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || echo "")
  popd > /dev/null
  
  echo "$result"
}

# Function to check if VM exists in Azure
vm_exists_in_azure() {
  az vm show --name vm-nedserveconfig --resource-group rg-serve-config --query "name" -o tsv >/dev/null 2>&1
}

# Function to get IP directly from Azure persistent IP
get_persistent_ip() {
  az network public-ip show --name ned-serve-config-persistent --resource-group rg-persistent-resources --query "ipAddress" -o tsv 2>/dev/null || echo ""
}

# Check current state
echo "Checking current infrastructure state..."
VM_EXISTS=$(vm_exists_in_azure && echo "true" || echo "false")
PERSISTENT_IP=$(get_persistent_ip)

echo "- VM exists in Azure: $VM_EXISTS"
echo "- Persistent IP: $PERSISTENT_IP"

# If VM doesn't exist and we're not in nuke mode, force nuke mode
if [ "$VM_EXISTS" = "false" ] && [ "$NUKE_MODE" = "false" ]; then
  echo ""
  echo "⚠️  VM doesn't exist in Azure, but --nuke flag not specified."
  echo "Since there's no VM to configure, switching to creation mode..."
  NUKE_MODE=true
fi

# Handle creation/recreation
if [ "$NUKE_MODE" = "true" ]; then
  echo ""
  echo "🚀 Creating/recreating infrastructure..."
  
  # Verify persistent IP exists
  if [ -z "$PERSISTENT_IP" ]; then
    echo "❌ ERROR: Persistent IP 'ned-serve-config-persistent' not found"
    echo "Please create it first with:"
    echo "az network public-ip create --name ned-serve-config-persistent --resource-group rg-persistent-resources --allocation-method Static --sku Standard --location eastus"
    exit 1
  fi
  echo "✅ Persistent IP found: $PERSISTENT_IP"
  
  # Work in terraform subdirectory
  cd terraform
  
  # Remove any existing host keys for the persistent IP
  echo "Cleaning up SSH host keys..."
  ssh-keygen -R "$PERSISTENT_IP" 2>/dev/null || true
  
  # Initialize Terraform
  echo "Initializing Terraform..."
  terraform init
  
  # Clean up any existing state (in case of partial deployments)
  echo "Cleaning up any existing resources..."
  terraform destroy -auto-approve 2>/dev/null || true
  
  # Create infrastructure
  echo "Creating new infrastructure..."
  terraform apply -auto-approve
  
  # Get the IP address
  echo "Getting VM IP address..."
  IP=""
  for i in {1..10}; do
    IP=$(terraform output -raw public_ip 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || echo "")
    
    if [ -n "$IP" ]; then
      echo "Found IP: $IP"
      break
    fi
    
    echo "Waiting for IP address... (attempt $i)"
    sleep 10
    terraform refresh > /dev/null 2>&1
  done
  
  # Go back to root directory
  cd ..
  
else
  # Just get the existing IP
  IP=$(get_terraform_output "public_ip")
  if [ -z "$IP" ]; then
    IP="$PERSISTENT_IP"
  fi
fi

# Validate we have an IP
if [ -z "$IP" ] || ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ ERROR: Could not obtain a valid IP address."
  echo "Current value: '$IP'"
  echo "Persistent IP: '$PERSISTENT_IP'"
  echo "Please check Azure portal for VM status."
  exit 1
fi

echo ""
echo "✅ VM IP address: $IP"

# Update Ansible inventory
echo "📝 Updating Ansible inventory..."
cd ansible
if [ -f inventory/hosts ]; then
  cp inventory/hosts inventory/hosts.bak
fi

# Fix the inventory update to handle PLACEHOLDER correctly
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/ansible_host=PLACEHOLDER/ansible_host=$IP/" inventory/hosts
  sed -i '' "s/ansible_host=[0-9.]*PLACEHOLDER/ansible_host=$IP/" inventory/hosts
  sed -i '' "s/ansible_host=[0-9.]\+/ansible_host=$IP/" inventory/hosts
else
  # Linux
  sed -i "s/ansible_host=PLACEHOLDER/ansible_host=$IP/" inventory/hosts
  sed -i "s/ansible_host=[0-9.]*PLACEHOLDER/ansible_host=$IP/" inventory/hosts
  sed -i "s/ansible_host=[0-9.]\+/ansible_host=$IP/" inventory/hosts
fi

# Verify the inventory was updated correctly
echo "Updated inventory:"
cat inventory/hosts

# Wait for SSH to become available
echo ""
echo "⏳ Waiting for SSH to become available..."
MAX_SSH_WAIT=300 # 5 minutes
START_TIME=$(date +%s)

while true; do
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
    echo "✅ SSH is available!"
    break
  fi
  
  # Check if we've waited too long
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
  
  if [ $ELAPSED_TIME -gt $MAX_SSH_WAIT ]; then
    echo "❌ Timed out waiting for SSH. You may need to check the VM console in Azure portal."
    exit 1
  fi
  
  echo "Still waiting for SSH... (${ELAPSED_TIME}s elapsed)"
  sleep 10
done

# Run Ansible playbook
echo ""
echo "🔧 Running Ansible to configure the server..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/serve_config.yml

# Get FQDN for final output
FQDN=""
if [ "$NUKE_MODE" = "true" ]; then
  cd ../terraform
  FQDN=$(terraform output -raw fqdn 2>/dev/null || echo "")
  cd ../ansible
fi

# Display final information
echo ""
echo "🎉 Deployment complete!"
echo "📍 Server is now running at:"
echo "   HTTP:  http://$IP:5000"
if [ -n "$FQDN" ]; then
  echo "   HTTPS: https://$FQDN"
fi
echo ""
echo "🌐 IP Address: $IP"
if [ -n "$FQDN" ]; then
  echo "🔗 FQDN: $FQDN"
fi

# Set up SSL certificates if in nuke mode
if [ "$NUKE_MODE" = "true" ] && [ -n "$FQDN" ]; then
  echo ""
  echo "🔒 Setting up SSL certificates..."
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null nathan@"$IP" "sudo certbot --nginx -d $FQDN --non-interactive --agree-tos --email nathandiez12@gmail.com" 2>/dev/null; then
    echo "✅ SSL certificates installed successfully!"
    echo "🔐 Your secure service is now available at https://$FQDN"
  else
    echo "⚠️  SSL certificate installation failed. You can set it up manually later."
  fi
fi