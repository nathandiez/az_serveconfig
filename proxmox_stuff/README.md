# Proxmox Template and Terraform Deployment Guide

This guide walks through creating VM templates in Proxmox using cloud images and deploying VMs from those templates using Terraform.

## Prerequisites

- Proxmox VE server (tested with version 8.x)
- Admin access to Proxmox server (root or privileged user)
- Terraform installed on your workstation
```bash
# Using Homebrew install terraform and ansible
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install ansible
```
## Step 1: Install Required Tools on Proxmox

Log in to your Proxmox server as root and install required tools:

```bash
apt update
apt install libguestfs-tools -y
```

The `libguestfs-tools` package provides utilities for modifying VM disk images without booting them.

## Step 2: Download Ubuntu Cloud Image

Ubuntu cloud images are pre-built for cloud environments and work well with cloud-init.

```bash
# Ubuntu cloud images are typically stored in /var/lib/vz/template/iso/
cd /var/lib/vz/template/iso/

# If you need to download a fresh cloud image:
# wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

For this guide, we used the Ubuntu 22.04 (noble) cloud image.

## Step 3: Prepare the Cloud Image

```bash
# If needed destroy the existing template if you are making updates
qm status 9002
qm destroy 9002
```

We need to install the QEMU guest agent and avahi-daemon in the cloud image:

```bash
# First, if not already done, modify the cloud image to install qemu-guest-agent
virt-customize -a /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img --install qemu-guest-agent
```

This allows proper communication between Proxmox and the VM, which is essential for Terraform. The second command fixes the issue where avahi-daemon appends numbers to hostnames by disabling IPv6 for the avahi service.

## Step 4: Create a VM Template in Proxmox

Create and configure a VM that will become our template:

```bash
# Create base VM
qm create 9002 --name "ubuntu-2204-cloudinit-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Import the disk
qm importdisk 9002 /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img local-lvm

# Configure the VM to use the imported disk
qm set 9002 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9002-disk-0

# Set boot configuration
qm set 9002 --boot c --bootdisk scsi0

# Add cloud-init drive
qm set 9002 --ide2 local-lvm:cloudinit

# Configure serial and display settings
qm set 9002 --serial0 socket --vga serial0

# Enable QEMU guest agent
qm set 9002 --agent enabled=1

# Convert the VM to a template
qm template 9002
```

## Step 5: Configure Terraform Provider

Create a `main.tf` file with the Proxmox provider configuration:

```hcl
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
  endpoint = "https://your-proxmox-ip:8006"
  insecure = true
}
```

Replace `your-proxmox-ip` with the actual IP of your Proxmox server.

## Step 6: Create API Token for Terraform

In the Proxmox web UI:

1. Go to Datacenter → Permissions → API Tokens
2. Click "Add"
3. Select your user (e.g., "root@pam")
4. Enter a Token ID (e.g., "terraform")
5. Uncheck "Privilege Separation" for simplicity
6. Click "Add"
7. Note the secret - you will only see it once!

Set the token as an environment variable:

## Create a script called set-proxmox-env.sh and include it in the deploy.sh script
export PROXMOX_VE_API_TOKEN='root@pam!nedterraform=your_proxmox_api_secret'
source ./<path>/set-proxmox-env.sh

**Important**: The bpg/proxmox provider requires the combined token format with an equals sign between the token ID and secret, not separate environment variables for ID and secret.

## Step 7: Define VM Resources in Terraform

Add the VM resource definition to your `main.tf`:

```hcl
# Define VM names using a variable
variable "vm_names" {
  description = "A list of Virtual Machine names to create"
  type        = list(string)
  default     = ["test-vm1"]
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
    vm_id = 9002
    full  = true
  }

  # --- QEMU Guest Agent ---
  agent {
    enabled = true
    trim    = true # Optional
  }

  # --- Hardware Configuration ---
  cpu {
    cores = 1
  }
  memory {
    dedicated = 1024
  }
  network_device {
    bridge = "vmbr0"
  }

  # --- Disk Configuration ---
  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 10
  }

  # --- Operating System Type ---
  operating_system {
    type = "l26"
  }

  # --- Cloud-Init Configuration ---
  initialization {
    ip_config {
      ipv4 { address = "dhcp" }
      ipv6 { address = "dhcp" } # Remove if not needed
    }

    user_account {
      username = "your-username"
      keys     = [ file("~/.ssh/id_ed25519.pub") ] # Path to your SSH key
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
```

Customize the resource definition as needed, especially:
- `node_name`: The name of your Proxmox node
- `vm_id`: The ID of your template (9002 in our example)
- `username`: The user to create in the VM
- SSH key path: The path to your public SSH key

## Cache your passphrase
ssh-add ~/.ssh/id_ed25519

## Step 8: Deploy VMs with Terraform
source ./terraform/set-proxmox-env.sh

## Step 8: Deploy VMs with Terraform
Initialize and apply the Terraform configuration:

```bash
terraform init
terraform plan
terraform apply
```

After successful deployment, Terraform will output the IP addresses of your VMs.

## Step 9: Connect to Your New VM

Use SSH to connect to your new VM using the username and SSH key you specified:

```bash
# Connect via IP address
ssh your-username@vm-ip-address

# Or connect via hostname (if avahi-daemon is configured)
ssh your-username@vm-name.local
```

The VM should be accessible via its hostname.local address thanks to the avahi-daemon we installed in the template. This enables zero-configuration networking for easier service discovery on your local network.

## Troubleshooting

- **VM doesn't boot**: Ensure the cloud image is properly configured and cloud-init is working
- **Cannot connect via SSH**: Check VM networking and ensure SSH keys were properly injected
- **Terraform authentication errors**: Verify your API token has the correct permissions and is using the combined format with equals sign
- **"Host key verification failed"**: When recreating VMs with the same IP, run `ssh-keygen -R ip-address` to remove the old key
- **Hostname appends numbers (like vm-name-2.local)**: This is fixed by our step to disable IPv6 for avahi-daemon
- **Template not found error**: Verify the template exists with `qm list` and that the template ID in Terraform matches

## Best Practices

- **Immutable Infrastructure**: The approach we've used follows the immutable infrastructure pattern, where VMs are never modified after deployment but instead replaced with new versions when changes are needed.
- **Template Strategy**: Consider creating a hierarchy of templates:
  - Base OS template with common utilities (like we've done here)
  - Service-specific templates built from the base (e.g., web server, database)
- **Infrastructure as Code**: Keep your Terraform configurations in version control and make changes through your code rather than manually.
- **Token Management**: Create specific API tokens for different purposes and limit their permissions as needed.
- **Template Versioning**: Consider using VM IDs to version your templates (e.g., 9001 for the next version).

## Additional Resources

- [Proxmox Documentation](https://www.proxmox.com/en/downloads/category/documentation)
- [Terraform Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)