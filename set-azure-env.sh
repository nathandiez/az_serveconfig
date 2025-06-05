#!/usr/bin/env bash
# set-azure-env.sh - Configure Azure authentication and environment variables for Terraform

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a
else
    echo "Warning: .env file not found. Copy .env.example to .env and configure your settings."
    echo "Using Azure CLI authentication as fallback..."
fi

# Choose authentication method
if [ -n "$ARM_CLIENT_ID" ] && [ -n "$ARM_CLIENT_SECRET" ] && [ -n "$ARM_TENANT_ID" ] && [ -n "$ARM_SUBSCRIPTION_ID" ]; then
    echo "Using Service Principal authentication for Terraform."
    export ARM_CLIENT_ID
    export ARM_CLIENT_SECRET
    export ARM_TENANT_ID
    export ARM_SUBSCRIPTION_ID
else
    echo "Using Azure CLI authentication for Terraform."
    echo "If not logged in, please run: az login"
    
    # Optional: Select a specific subscription if specified
    if [ -n "$ARM_SUBSCRIPTION_ID" ]; then
        echo "Setting subscription to: $ARM_SUBSCRIPTION_ID"
        az account set --subscription "$ARM_SUBSCRIPTION_ID"
    fi
fi

echo "✅ Azure Terraform environment configured."
