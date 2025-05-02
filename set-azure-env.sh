#!/usr/bin/env bash
# set-azure-env.sh - Configure Azure authentication for Terraform

# Choose one of the authentication methods below:

# Method 1: Service Principal Authentication (recommended for automation)
# export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
# export ARM_CLIENT_SECRET="your-client-secret"
# export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
# export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

# Method 2: Azure CLI Authentication (easier for development)
# Requires running 'az login' first
echo "Using Azure CLI authentication for Terraform."
echo "If not logged in, please run: az login"

# Optional: Select a specific subscription
# az account set --subscription "Your Subscription Name"

echo "✅ Azure Terraform environment configured."
