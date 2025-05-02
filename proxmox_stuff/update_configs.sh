#!/usr/bin/env bash
# update_configs.sh - Script to update only config files without redeploying

set -e

# Change into the ansible directory
cd "$(dirname "$0")/ansible"

# Get the IP address from the hosts file
IP=$(grep -oE 'ansible_host=[0-9.]+' inventory/hosts | cut -d= -f2)

if [ -z "$IP" ]; then
    echo "Error: Could not retrieve IP address from Ansible inventory." >&2
    exit 1
fi
echo "VM IP address: $IP"

# Run the Ansible playbook to update just the config files
echo "Updating config files only..."
ansible-playbook playbooks/update_configs.yml

echo "Config update complete! Changes are immediately available at http://$IP:5000"