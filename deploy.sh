#!/usr/bin/env bash
# deploy.sh
# Deploys or configures the application. Checks for --nuke flag.
# Usage:
#   ./deploy.sh          (Configures existing VM using Ansible)
#   ./deploy.sh --nuke   (Destroys existing VM via Terraform, creates a new one, then configures with Ansible)
set -e

# --- Configuration ---
# Set the base hostname for the target server (without .local)
TARGET_HOSTNAME=nedserveconfig"
# --- End Configuration ---


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
  # Pass the hostname variable to terraform apply
  terraform destroy -var="vm_names=[\"${TARGET_HOSTNAME}\"]" -auto-approve

  SLEEP_DURATION=1 # Example: 1 second
  echo "Waiting ${SLEEP_DURATION} seconds for network/mDNS caches to clear before recreating VM..."
  sleep ${SLEEP_DURATION}

  echo "Initializing Terraform…"
  terraform init

  # Message slightly updated for clarity after destroy
  echo "Applying Terraform configuration (recreating infrastructure)..."
  # Pass the hostname variable to terraform apply
  terraform apply -var="vm_names=[\"${TARGET_HOSTNAME}\"]" -auto-approve
fi # --- End conditional Terraform ---


# Extract only the first non-loopback IP address
# This will run regardless, reading from the state file if apply was skipped
# Use the TARGET_HOSTNAME to filter the output correctly
IP=$(terraform output -json vm_ip_addresses \
     | jq -r --arg NAME "$TARGET_HOSTNAME" '.[$NAME] | .[][] | select(. != "127.0.0.1")' | head -n 1)


# Validate IP Address (Basic Check)
if [ -z "$IP" ] || [ "$IP" == "null" ]; then
    echo "Error: Could not retrieve IP address for ${TARGET_HOSTNAME} from Terraform output." >&2
    if [ "$RUN_TERRAFORM_APPLY" = false ]; then
        echo "Maybe the VM doesn't exist or Terraform state is missing/corrupt?" >&2
        echo "Try running with the '--nuke' flag to create it." >&2 # Using double dash
    else
        echo "Terraform apply might have failed to output the IP address." >&2
    fi
    exit 1
fi
echo "VM IP address (${TARGET_HOSTNAME}): $IP"

# Update the Ansible inventory with the new IP
# Assuming deploy.sh is in project root
cd ../ansible
# NOTE: sed -i '' is for macOS/BSD sed. Use sed -i for GNU sed.
# Consider making the inventory update more robust if needed,
# e.g., targeting a specific host entry if inventory has multiple hosts.
sed -i '' "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

# Wait for SSH to become available on the VM
echo "Waiting for SSH to become available on ${TARGET_HOSTNAME} ($IP)..."
while ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; do
  echo "Still waiting for SSH..."
  sleep 5
done

# Run the Ansible playbook to configure the server
echo "Running Ansible playbook against ${TARGET_HOSTNAME}..."
ansible-playbook playbooks/serve_config.yml

echo "Deployment complete! Your serve_config application is now running at http://$IP:5000"

# Adding current date as requested by context
echo "Current date: $(date)"
echo ""

# --- Quick Check for ${TARGET_HOSTNAME}.local --- 
HOSTNAME_TO_CHECK="${TARGET_HOSTNAME}.local"
URL_TO_CHECK="http://${HOSTNAME_TO_CHECK}:5000/pico_iot_config.json"
CONNECT_TIMEOUT=5
MAX_TIME=10
echo "--- Checking ${HOSTNAME_TO_CHECK}..."
# Step 1: Get HTTP status silently first (like you already have)
http_status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout ${CONNECT_TIMEOUT} --max-time ${MAX_TIME} "${URL_TO_CHECK}" 2>/dev/null)
curl_exit_code=$? # Capture curl's exit code
# Step 2: Run curl again just to display output (headers and body)
echo ""
curl -is --connect-timeout ${CONNECT_TIMEOUT} --max-time ${MAX_TIME} "${URL_TO_CHECK}" | head -n 30 || true
echo ""
# Step 3: Check result from the *first* (silent) curl (your existing logic)
if [[ ${curl_exit_code} -eq 0 && "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
  echo "✅ SUCCESS: ${HOSTNAME_TO_CHECK} check passed (HTTP ${http_status})."
else
  echo "❌ FAIL: ${HOSTNAME_TO_CHECK} check failed (Curl Exit: ${curl_exit_code}, HTTP Status: ${http_status:-'N/A'})."
  exit 1 # Exit script with failure code
fi