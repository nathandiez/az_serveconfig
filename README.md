# Azure ServeConfig - IoT Configuration Server

A Flask-based configuration server deployed on Azure using Terraform and Ansible. Serves JSON configuration files to IoT devices over HTTP/HTTPS.

## Architecture

- **Infrastructure**: Azure VM with persistent public IP
- **Application**: Flask app in Docker container
- **Configuration**: JSON files served via HTTP endpoints
- **Automation**: Terraform for infrastructure, Ansible for application deployment

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.9
- SSH key pair generated (`ssh-keygen -t rsa -b 4096`)

## Quick Start

### 1. Clone and Setup

```bash
git clone <this-repo>
cd az_serveconfig

# Copy environment template and configure
cp .env.example .env
# Edit .env with your actual values
```

### 2. Configure Environment

Edit `.env` file with your settings:

```bash
# Azure Configuration
AZURE_REGION=eastus
SSH_USERNAME=your-username
SSH_PUBLIC_KEY_PATH=~/.ssh/id_rsa.pub

# IoT Configuration
MQTT_BROKER_IP=your.mqtt.broker.ip
API_KEY=your-secret-api-key
INTERNAL_HOSTNAME=your-hostname.local
CERTBOT_EMAIL=your-email@example.com
```

### 3. Create Persistent IP (One-time setup)

```bash
# Login to Azure
az login

# Create persistent IP (only needed once)
az group create --name rg-persistent-resources --location eastus
az network public-ip create \
  --name ned-serve-config-persistent \
  --resource-group rg-persistent-resources \
  --allocation-method Static \
  --sku Standard \
  --location eastus
```

### 4. Deploy

```bash
# Deploy everything
./deploy.sh --nuke

# Or for existing infrastructure
./deploy.sh
```

### 5. Test

```bash
# Get the server IP from output, then test:
curl http://YOUR_IP:5000/ping
curl http://YOUR_IP:5000/pico_iot_config.json
```

## Project Structure

```
az_serveconfig/
├── terraform/          # Infrastructure as Code
│   ├── main.tf         # VM, networking, security
│   ├── variables.tf    # Configuration variables
│   └── outputs.tf      # IP addresses, FQDN
├── ansible/            # Configuration Management
│   ├── playbooks/
│   │   ├── serve_config.yml    # Main deployment
│   │   └── update_configs.yml  # Config-only updates
│   └── inventory/hosts # Server inventory
├── src/                # Application Code
│   ├── Dockerfile      # Container definition
│   ├── requirements.txt
│   └── serve_config.py # Flask application
├── config_files/       # IoT Configuration Files
│   ├── pico_iot_config.json
│   ├── cooker_config.json
│   └── eiot_config.json
├── deploy.sh          # Main deployment script
├── destroy.sh         # Teardown script
└── update_configs.sh  # Update configs only
```

## Operations

### Update Configuration Files Only

```bash
# Update configs without redeploying infrastructure
./update_configs.sh
```

### View Logs

```bash
./taillogs.sh
```

### Destroy Everything

```bash
./destroy.sh
# Note: Preserves persistent IP to avoid cost and reconfiguration
```

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/ping` | Health check - returns "pong" |
| `/pico_iot_config.json` | Pico W IoT device configuration |
| `/cooker_config.json` | Temperature controller configuration |
| `/eiot_config.json` | ESP32 IoT device configuration |

## Configuration

### Environment Variables

Configuration values are loaded from `.env` and used to replace placeholders in config files:

- `PLACEHOLDER_MQTT_BROKER` → `MQTT_BROKER_IP`
- `PLACEHOLDER_API_KEY` → `API_KEY` 
- `PLACEHOLDER_HOSTNAME` → `INTERNAL_HOSTNAME`

### Persistent IP

The project uses a persistent public IP to avoid reconfiguring IoT devices. This IP:
- Costs ~$3.65/month when not attached to a VM
- Is preserved across deployments
- Eliminates need to update device configurations

## Cost Optimization

- **VM**: Standard_B1s (~$7.60/month when running)
- **Persistent IP**: ~$3.65/month when VM is destroyed
- **Storage**: Minimal cost for OS disk
- **Total**: ~$11.25/month when running, ~$3.65/month when destroyed

## Security

- SSH access restricted to your IP address
- HTTP/HTTPS ports open only to specific IPs
- SSL certificates via Let's Encrypt (optional)
- Firewall configured via Network Security Groups

## Troubleshooting

### SSH Connection Issues
```bash
# Clean up old SSH keys
ssh-keygen -R YOUR_VM_IP
```

### Terraform State Issues
```bash
# Reset everything
./destroy.sh
./deploy.sh --nuke
```

### View Container Logs
```bash
ssh user@YOUR_VM_IP
docker logs serve_config
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Update `.env.example` if adding new environment variables
4. Test your changes
5. Submit a pull request

## License

MIT License - see LICENSE file for details
