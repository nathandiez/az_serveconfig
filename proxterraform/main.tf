terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.5.6:8006"
  insecure = true
}

module "ned_serveconfig_server" {
  source = "./base-module"
  
  vm_name     = "nedserveconfig"
  mac_address = "52:54:00:12:33:01"
}

output "server_ip" {
  value = module.ned_serveconfig_server.primary_ip
}