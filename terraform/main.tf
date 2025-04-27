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
  default     = ["pxserveconfig"]
}

# Define VM resources using for_each based on the variable
resource "proxmox_virtual_environment_vm" "linux_vm" {
  for_each = toset(var.vm_names) # Create one for each name

  # --- Basic VM Settings ---
  name      = each.key
  node_name = "proxmox"
  tags      = ["terraform-managed"]

  # --- VM Template Source (CRITICAL: CUSTOMIZE vm_id!) ---
  clone {
    # IMPORTANT: Replace 9000 with the actual VMID of your Proxmox template.
    vm_id = 9000
    full  = true
  }

  # --- QEMU Guest Agent (Corrected 'trim' argument) ---
  agent {
    enabled = true
    # Ensure this line reads 'trim', not 'use_fstrim'
    trim    = true # Optional
  }

  # --- Hardware Configuration ---
  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  network_device {
    bridge = "vmbr0"
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

  # --- Cloud-Init Configuration (Removed unsupported 'hostname' argument) ---
  initialization {
    # Ensure the 'hostname = ...' line below is REMOVED
    # Cloud-Init will likely set hostname based on VM name or other defaults

    ip_config {
      ipv4 { address = "dhcp" }
      ipv6 { address = "dhcp" } # Remove if not needed
    }

    user_account {
      username = "eric"
      keys     = [ file("~/.ssh/id_ed25519v2.pub") ] # Assumes key in ~/.ssh/
    }
  }
}

# Optional: Output VM IPs
output "vm_ip_addresses" {
  value = {
    for vm_name, vm_data in proxmox_virtual_environment_vm.linux_vm :
    vm_name => vm_data.ipv4_addresses
  }
  description = "Map of VM names to their primary IPv4 addresses"
}