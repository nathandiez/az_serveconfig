#!/usr/bin/env bash
# deploy.sh
# Deploys or configures the application. Checks for --nuke flag.
# Usage:
#   ./deploy.sh          (Configures existing VM using Ansible)
#   ./deploy.sh --nuke   (Destroys existing VM via Terraform, creates a new one, then configures with Ansible)
set -e

# +++ START DEBUGGING +++
echo "----------------------------------------"
echo "DEBUG: Executing script: $0"
echo "DEBUG: Raw arguments received (\$@): '$@'"
echo "DEBUG: Checking first argument (\$1): '$1'"
echo "DEBUG: Expected flag value: '--nuke'" # Expecting double dash
echo "----------------------------------------"
# +++ END DEBUGGING +++

# --- Check for Terraform flag ---
# Default is not to run terraform destroy/apply
RUN_TERRAFORM_APPLY=false # Variable name kept for minimal change, now means "do nuke"
# Check if the first argument is --nuke
if [[ "$1" == "--nuke" ]]; then # Checking for double dash --nuke
  RUN_TERRAFORM_APPLY=true
  echo "DEBUG: Flag comparison SUCCESS." # Added debug inside condition
  echo "Flag --nuke detected: Terraform destroy, init & apply will run." # Using double dash
else
  RUN_TERRAFORM_APPLY=false # Explicitly set false
  echo "DEBUG: Flag comparison FAILED." # Added debug inside condition
  echo "No --nuke flag: Skipping Terraform destroy, init & apply." # Using double dash
fi

# Source the Proxmox environment variables
# Assuming this script exists in ./terraform relative to project root
source ./terraform/set-proxmox-env.sh

# Change into the terraform directory
# Assuming deploy.sh is in project root
cd "$(dirname "$0")/terraform"

# --- Conditionally run Terraform ---
if [ "$RUN_TERRAFORM_APPLY" = true ]; then
  # ADDED: Destroy step before init/apply when --nuke flag is present
  echo "Destroying existing Terraform-managed infrastructure (VM)..."
  terraform destroy -auto-approve

  SLEEP_DURATION=90 # Example: 90 seconds (adjust as needed for testing)
  echo "Waiting ${SLEEP_DURATION} seconds for network/mDNS caches to clear before recreating VM..."
  sleep ${SLEEP_DURATION}

  echo "Initializing Terraform…"
  terraform init

  # Message slightly updated for clarity after destroy
  echo "Applying Terraform configuration (recreating infrastructure)..."
  terraform apply -auto-approve
fi # --- End conditional Terraform ---

# --- REST OF SCRIPT IS UNCHANGED FROM ORIGINAL MINIMAL VERSION ---

# Extract only the first non-loopback IP address
# This will run regardless, reading from the state file if apply was skipped
IP=$(terraform output -json vm_ip_addresses \
     | jq -r '[.[] | .[][] | select(. != "127.0.0.1")] | .[0]')

# Validate IP Address (Basic Check)
if [ -z "$IP" ] || [ "$IP" == "null" ]; then
    echo "Error: Could not retrieve IP address from Terraform output." >&2
    if [ "$RUN_TERRAFORM_APPLY" = false ]; then
        echo "Maybe the VM doesn't exist or Terraform state is missing/corrupt?" >&2
        echo "Try running with the '--nuke' flag to create it." >&2 # Using double dash
    else
        echo "Terraform apply might have failed to output the IP address." >&2
    fi
    exit 1
fi
echo "VM IP address: $IP"

# Update the Ansible inventory with the new IP
# Assuming deploy.sh is in project root
cd ../ansible
# NOTE: sed -i '' is for macOS/BSD sed. Use sed -i for GNU sed.
sed -i '' "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

# Wait for SSH to become available on the VM
echo "Waiting for SSH to become available..."
while ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 eric@"$IP" echo ready 2>/dev/null; do
  echo "Still waiting for SSH..."
  sleep 5
done

# Run the Ansible playbook to configure the server
echo "Running Ansible playbook…"
ansible-playbook playbooks/serve_config.yml

echo "Deployment complete! Your serve_config application is now running at http://$IP:5000"

# Adding current date as requested by context
# Current date: Saturday, April 26, 2025 at 07:27:59 AM EDT
echo "Current date: $(date)"

# Final check
sleep 2 # Optional: Wait a bit before the final check
echo "about to run curl -i http://$IP:5000/pico_iot_config.json"
curl -i http://$IP:5000/pico_iot_config.json
echo "just ran curl -i http://$IP:5000/pico_iot_config.json"
sleep 5
echo "about to run curl -i http://proxvm1.local:5000/pico_iot_config.json"
curl -i http://proxvm1.local:5000/pico_iot_config.json
echo "just ran curl -i http://proxvm1.local:5000/pico_iot_config.json"