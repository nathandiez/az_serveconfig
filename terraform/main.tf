# main.tf 

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

# Configure the Proxmox provider
provider "proxmox" {
  # Using environment variables for authentication (PROXMOX_VE_API_TOKEN)
  endpoint = "https://192.168.5.5:8006"
  insecure = true
}

# Define VM names using a variable
variable "vm_names" {
  description = "A list of Virtual Machine names to create"
  type        = list(string)
  default     = ["nedserveconfig"]
}

# Define VM resources using for_each based on the variable
resource "proxmox_virtual_environment_vm" "linux_vm" {
  for_each = toset(var.vm_names) # Create one for each name

  # --- Basic VM Settings ---
  name      = each.key
  node_name = "proxmox"
  tags      = ["terraform-managed"]

  # --- VM Template Source ---
  clone {
    # Use the 9002 noble template
    vm_id = 9002
    full  = true
  }

  # --- QEMU Guest Agent ---
  agent {
    enabled = true
    trim    = true
  }

  # --- Hardware Configuration ---
  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:00:12:34:58" # Added static MAC address

  }

  # --- Disk Configuration ---
  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 30
  }

  # --- Operating System Type ---
  operating_system {
    type = "l26"
  }

  # --- Cloud-Init Configuration ---
  initialization {
    ip_config {
      ipv4 {
        # Use DHCP to obtain an IP address and gateway
        address = "dhcp"
      }
    }

    dns {
      # You can keep static DNS servers or rely on DHCP-provided ones
      # If you want DHCP to provide DNS, you might remove this block too,
      # depending on your cloud-init template's default behavior.
      servers = ["192.168.6.1", "8.8.8.8"]
    }

    user_account {
      username = "nathan"
      keys     = [file("~/.ssh/id_ed25519.pub")]
    }
  }
}

# Output VM IPs
output "vm_ip_addresses" {
  value = {
    for vm_name, vm_data in proxmox_virtual_environment_vm.linux_vm :
    vm_name => vm_data.ipv4_addresses
  }
  description = "Map of VM names to their primary IPv4 addresses (will reflect DHCP assigned IPs)"
}