terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Import proxmox module reference for the main.tf
# Note: Instead of using the Proxmox module, we're now using Azure resources directly
# This is just a reference to show the transformation

module "ned_serveconfig_server" {
  source = "./terraform"
  
  # These variables are now all handled inside the terraform directory
  # No need to pass them explicitly as the Azure configuration uses variables.tf
}

output "server_ip" {
  value = module.ned_serveconfig_server.public_ip
}
