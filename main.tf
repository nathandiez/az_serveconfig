terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Use the terraform module in the terraform/ directory
module "azure_vm" {
  source = "./terraform"
}

output "public_ip" {
  value = module.azure_vm.public_ip
}

output "fqdn" {
  value = module.azure_vm.fqdn
}
