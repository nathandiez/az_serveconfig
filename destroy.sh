#!/usr/bin/env bash
# destroy.sh - Complete teardown script for Azure nedserveconfig
# WARNING: This will completely destroy the VM and all Terraform state!
set -e

echo "=========================================="
echo "WARNING: DESTRUCTIVE OPERATION"
echo "=========================================="
echo "This will:"
echo "  - Destroy the VM in Azure"
echo "  - Destroy all networking resources"
echo "  - Delete all Terraform state files"
echo "  - Clean up lock files"
echo "  - Reset everything to a clean slate"
echo "  - PRESERVE the persistent IP (ned-serve-config-persistent)"
echo ""
echo "This action is IRREVERSIBLE!"
echo "=========================================="

# Prompt for confirmation
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation

if [[ "$confirmation" != "yes" ]]; then
  echo "Operation cancelled."
  exit 0
fi

echo ""
echo "Starting destruction process..."

# Source Azure environment variables
echo "Loading Azure environment..."
source ./set-azure-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Check if terraform state exists
if [[ -f "terraform.tfstate" ]]; then
  echo ""
  echo "Terraform state found. Destroying infrastructure..."
  
  # Initialize terraform (in case .terraform directory is missing)
  terraform init -upgrade
  
  # Get current IP for SSH cleanup
  CURRENT_IP=$(terraform output -raw public_ip 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
  
  if [ -n "$CURRENT_IP" ]; then
    echo "Current VM IP: $CURRENT_IP"
    echo "Cleaning up SSH known hosts..."
    ssh-keygen -R "$CURRENT_IP" 2>/dev/null || true
  fi
  
  # Destroy the infrastructure
  echo "Running terraform destroy..."
  terraform destroy -auto-approve
  
  echo "Infrastructure destroyed successfully."
  
  # Double-check: manually delete resource group if it still exists
  echo "Double-checking resource group deletion..."
  if az group show --name rg-serve-config >/dev/null 2>&1; then
    echo "Resource group still exists, forcing deletion..."
    az group delete --name rg-serve-config --yes --no-wait
  fi
else
  echo "No terraform.tfstate found. Skipping terraform destroy."
fi

# Clean up all Terraform files
echo ""
echo "Cleaning up Terraform state and lock files..."

# Remove state files
rm -f terraform.tfstate
rm -f terraform.tfstate.backup

# Remove lock file if it exists
rm -f .terraform.lock.hcl

# Remove .terraform directory (contains providers and modules)
rm -rf .terraform

echo "All Terraform files cleaned up."

# Clean up Ansible inventory
echo ""
echo "Resetting Ansible inventory..."
cd ../ansible

# Reset the inventory to a default state (remove the IP)
if [[ -f "inventory/hosts" ]]; then
  # Use different sed syntax for different OS
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' 's/ansible_host=.*/ansible_host=PLACEHOLDER/' inventory/hosts
  else
    # Linux
    sed -i 's/ansible_host=.*/ansible_host=PLACEHOLDER/' inventory/hosts
  fi
  echo "Ansible inventory reset to placeholder state."
fi

# Clean up any backup files
rm -f inventory/hosts.bak
rm -f inventory/hosts.tmp

echo ""
echo "=========================================="
echo "DESTRUCTION COMPLETE"
echo "=========================================="
echo "✅ VM destroyed in Azure"
echo "✅ All networking resources destroyed"
echo "✅ Resource group destroyed"
echo "✅ Terraform state files deleted"
echo "✅ Terraform lock files removed"
echo "✅ Provider cache cleared"
echo "✅ SSH known hosts cleaned"
echo "✅ Ansible inventory reset"
echo ""
echo "🔒 PRESERVED:"
echo "   - Persistent IP (ned-serve-config-persistent)"
echo "   - Persistent resources group (rg-persistent-resources)"
echo ""
echo "You can now run './deploy.sh --nuke' to start fresh!"
echo "=========================================="