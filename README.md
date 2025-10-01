# OpenVPN Admin Panel - Complete Knowledge Transfer Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture Deep Dive](#architecture-deep-dive)
3. [Docker Compose Configuration](#docker-compose-configuration)
4. [Configure.sh Script Analysis](#configuresh-script-analysis)
5. [OpenVPN Configuration](#openvpn-configuration)
6. [Client Configuration Template](#client-configuration-template)
7. [Installation and Setup](#installation-and-setup)
8. [Environment Variables Reference](#environment-variables-reference)
9. [Troubleshooting Guide](#troubleshooting-guide)
10. [Security Considerations](#security-considerations)

---

## Overview

### What is ovpn-admin?

**ovpn-admin** is a web-based management interface for OpenVPN servers that simplifies the administration of VPN users, certificates, and network configurations. It consists of two main components:

1. **OpenVPN Server Container**: Runs the actual VPN server with automated certificate management
2. **Admin Web Interface**: Go-based backend with Vue.js frontend for user management

### Key Features
- **User Management**: Add, delete, enable/disable VPN users
- **Client Certificate Management**: Automatic generation, revocation, and renewal of SSL certificates
- **Route Management**: Configure custom network routes for clients
- **Real-time Monitoring**: Track connected users and connection statistics
- **Password Authentication**: Optional additional password layer beyond certificates
- **Client Configuration**: Automatic generation of client `.ovpn` files

### Architecture Components

```
┌─────────────────┐    ┌─────────────────┐
│   Web Browser   │───▶│   ovpn-admin    │
│  (Port 8080)    │    │   (Go Backend)  │
└─────────────────┘    └─────────┬───────┘
                                │
                                ▼
┌─────────────────┐    ┌─────────────────┐
│  VPN Clients    │───▶│  OpenVPN Server │
│  (Port 7777)    │    │  (Port 1194)    │
└─────────────────┘    └─────────────────┘
```

---

## Architecture Deep Dive

### Container Communication
Both containers run in the same Docker network (`vpn-internal`) and share volumes for:
- **Certificate Storage**: `/etc/openvpn/easyrsa` (EasyRSA PKI)
- **Client Configurations**: `/etc/openvpn/ccd` (Client Config Directory)

### Networking Strategy
- **Internal Network**: `172.20.0.0/16` (Docker containers)
- **VPN Network**: `10.8.0.0/24` (VPN clients get IPs from this range)
- **MTU Optimization**: Set to 1372 to prevent fragmentation -> (Change to according with network)
- **Port Mapping**: External port 7777 maps to internal port 1194

---

## Docker Compose Configuration

Let's analyze the `docker-compose.yaml` file section by section:

### Network Configuration
```yaml
networks:
  vpn-internal:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: 1372  # Prevents packet fragmentation
    ipam:
      config:
        - subnet: 172.20.0.0/16             # Internal container network
```

**Explanation:**
- Creates isolated network for containers
- MTU of 1372 prevents fragmentation issues common in VPN scenarios
- Subnet `172.20.0.0/16` provides plenty of IP addresses for containers

### OpenVPN Service Configuration

```yaml
openvpn:
    image: nexus.spreezy.in/openvpn:v1.0.0
    pull_policy: always
    command: /etc/openvpn/setup/configure.sh
```

**Build Process:**
- Pulls pre-built image from private registry (nexus.spreezy.in)
- Always pulls latest image on startup
- Executes `configure.sh` as the main command (we'll analyze this script later)

#### Environment Variables Breakdown

```yaml
    env_file:
      - ./.env
```

**Variable Details:**
- Loads environment variables from `.env` file 
- Read the .env.template for details on each variable

#### Networking and Security

```yaml
cap_add:
  - NET_ADMIN                               # Required for network operations
sysctls:
  - net.ipv4.ip_forward=1                   # Enable IP forwarding
ports:
  - 7777:1194/udp                          # VPN port mapping
  - 8080:8080                              # Admin interface port
```

**Security Notes:**
- `NET_ADMIN` capability allows network interface manipulation
- IP forwarding is essential for routing VPN traffic
- UDP protocol chosen for better VPN performance than TCP

### Admin Service Configuration

```yaml
ovpn-admin:
    image: nexus.spreezy.in/ovpn-admin:v1.0.0
    pull_policy: always
    command: /app/ovpn-admin
```

#### Admin Environment Variables

```yaml
    env_file:
      - ./.env
```
**Variable Details:**
- Shares the same `.env` file for consistent configuration

#### Networking and Volumes

```yaml
    network_mode: service:openvpn            # Shares network stack with OpenVPN
    volumes:
      - ./easyrsa_master:/mnt/easyrsa       # Certificate storage
      - ./ccd_master:/mnt/ccd                # Client config directory
```

**Critical Configuration:**
- **network_mode: service:openvpn**: Shares network stack with OpenVPN container
- **OVPN_SERVER**: Must match your actual public IP and port
- **Volume Mounts**: Share certificate and config directories with OpenVPN

---

## Configure.sh Script Analysis

The `configure.sh` script is the main part of the OpenVPN setup process.

### Initial Setup
```bash
#!/usr/bin/env bash
set -ex                                    # Exit on error, show commands

EASY_RSA_LOC="/etc/openvpn/easyrsa"
SERVER_CERT="${EASY_RSA_LOC}/pki/issued/server.crt"

OVPN_SRV_NET=${OVPN_SERVER_NET:-10.8.0.0}
OVPN_SRV_MASK=${OVPN_SERVER_MASK:-255.255.255.0}
```

**Explanation:**
- `set -ex`: Enables debugging and exits on first error
- Defines paths for EasyRSA and server certificate
- Uses parameter expansion for default values if env vars not set

### Certificate Management
```bash
cd $EASY_RSA_LOC

if [ -e "$SERVER_CERT" ]; then
  echo "Found existing certs - reusing"
else
  if [ ${OVPN_ROLE:-"master"} = "slave" ]; then
    echo "Waiting for initial sync data from master"
    while [ $(wget -q localhost/api/sync/last/try -O - | wc -m) -lt 1 ]
    do
      sleep 5
    done
  else
    echo "Generating new certs"
    easyrsa --batch init-pki
    cp -R /usr/share/easy-rsa/* $EASY_RSA_LOC/pki
    echo "ca" | easyrsa build-ca nopass
    easyrsa --batch build-server-full server nopass
    easyrsa gen-dh
    openvpn --genkey --secret ./pki/ta.key
  fi
fi
easyrsa gen-crl
```

**Certificate Process:**
1. **Check Existing**: Looks for existing server certificate
2. **Master/Slave Logic**: If slave mode, waits for certificate sync
3. **PKI Initialization**: Creates Public Key Infrastructure
4. **CA Creation**: Generates Certificate Authority
5. **Server Certificate**: Creates server SSL certificate
6. **DH Parameters**: Generates Diffie-Hellman parameters for key exchange
7. **TLS Auth Key**: Creates additional TLS authentication key
8. **CRL Generation**: Creates Certificate Revocation List

### Network Configuration (IPTables)
```bash
iptables -t nat -D POSTROUTING -s ${OVPN_SRV_NET}/${OVPN_SRV_MASK} ! -d ${OVPN_SRV_NET}/${OVPN_SRV_MASK} -j MASQUERADE || true
iptables -t nat -A POSTROUTING -s ${OVPN_SRV_NET}/${OVPN_SRV_MASK} ! -d ${OVPN_SRV_NET}/${OVPN_SRV_MASK} -j MASQUERADE
iptables -t nat -A POSTROUTING -s ${OVPN_SRV_NET}/${OVPN_SRV_MASK} -d ${DOCKER_NETWORK} -j MASQUERADE
```

**NAT Rules Explanation:**
1. **Delete Existing**: Removes old MASQUERADE rule (|| true ignores errors)
2. **General Internet**: Allows VPN clients to access internet
3. **Docker Access**: Allows VPN clients to access Docker containers

### TUN Device Setup
```bash
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi
```

**Device Creation:**
- Creates TUN device if it doesn't exist
- TUN device is required for VPN tunnel interface
- Character device with major:minor numbers 10:200

### OpenVPN Configuration (Dynamically Appends Config in openvpn.conf (openvpn server config file) )
```bash
cp -f /etc/openvpn/setup/openvpn.conf /etc/openvpn/openvpn.conf

if [ ! -z "$OVPN_TUN_MTU" ]; then
    echo "tun-mtu $OVPN_TUN_MTU" >> /etc/openvpn/openvpn.conf
fi

if [ ! -z "$OVPN_MSSFIX" ]; then
    echo "mssfix $OVPN_MSSFIX" >> /etc/openvpn/openvpn.conf
fi

if [ ! -z "${OVPN_CUSTOM_ROUTES}" ]; then
  echo 'push "route '${OVPN_CUSTOM_ROUTES}'"' >> /etc/openvpn/openvpn.conf
fi
```

**Configuration Logic:**
- Copies base configuration to runtime location
- Dynamically adds MTU settings if specified in .env file
- Adds MSS fix if specified in .env file
- Injects custom routes for client access

### Password Authentication Setup
```bash
if [ ${OVPN_PASSWD_AUTH} = "true" ]; then
  mkdir -p /etc/openvpn/scripts/
  cp -f /etc/openvpn/setup/auth.sh /etc/openvpn/scripts/auth.sh
  chmod +x /etc/openvpn/scripts/auth.sh
  echo "auth-user-pass-verify /etc/openvpn/scripts/auth.sh via-file" | tee -a /etc/openvpn/openvpn.conf
  echo "script-security 2" | tee -a /etc/openvpn/openvpn.conf
  echo "verify-client-cert require" | tee -a /etc/openvpn/openvpn.conf
  openvpn-user db-init --db.path=$EASY_RSA_LOC/pki/users.db && openvpn-user db-migrate --db.path=$EASY_RSA_LOC/pki/users.db
fi
```

**Authentication Setup:**
- Copies authentication script
- Configures OpenVPN to use external auth verification
- Enables script execution with security level 2
- Still requires client certificates (two-factor)
- Initializes user database for password storage

### Final Server Startup
```bash
[ -d $EASY_RSA_LOC/pki ] && chmod 755 $EASY_RSA_LOC/pki
[ -f $EASY_RSA_LOC/pki/crl.pem ] && chmod 644 $EASY_RSA_LOC/pki/crl.pem

mkdir -p /etc/openvpn/ccd

openvpn --config /etc/openvpn/openvpn.conf --client-config-dir /etc/openvpn/ccd --port 1194 --proto udp --management 127.0.0.1 8989 --dev tun0 --server ${OVPN_SRV_NET} ${OVPN_SRV_MASK}
```

**Server Launch:**
- Sets proper permissions on certificate files
- Creates client config directory
- Launches OpenVPN with all configuration parameters
- Management interface on port 8989 for admin communication

---

## OpenVPN Configuration

Let's analyze the `setup/openvpn.conf` file:

### Basic Configuration
```
topology subnet                             # Use subnet topology (recommended)
#duplicate-cn                              # Allow multiple connections per cert (disabled)
#proto udp                                 # Protocol set via command line
#port 1194                                 # Port set via command line
#dev tun0                                  # Device set via command line
```
***Note**: Protocol, port, and device are set via command line in `configure.sh`*

### Certificate Paths
```
ca /etc/openvpn/easyrsa/pki/ca.crt          # Certificate Authority
key /etc/openvpn/easyrsa/pki/private/server.key  # Server private key
cert /etc/openvpn/easyrsa/pki/issued/server.crt  # Server certificate
dh /etc/openvpn/easyrsa/pki/dh.pem          # Diffie-Hellman parameters
crl-verify /etc/openvpn/easyrsa/pki/crl.pem # Certificate Revocation List
tls-auth /etc/openvpn/easyrsa/pki/ta.key    # TLS authentication key
```

### Connection Management
```
#management 127.0.0.1 8989                 # Management interface (set via command line)
keepalive 10 60                            # Ping every 10s, timeout after 60s
```

### Persistence Options
```
persist-key                                 # Don't re-read key files on restart
persist-tun                                 # Don't close/reopen TUN device on restart
```

### Logging Configuration
```
verb 3                                      # Verbosity level (0-15)
status /tmp/openvpn-status.log             # Status file for monitoring
log-append /tmp/openvpn.log                # Log file location
```

### Security Settings
```
user nobody                                # Run as unprivileged user
group nogroup                              # Run as unprivileged group
tls-server                                 # Initialize TLS as server
key-direction 0                            # Key direction for tls-auth
cipher AES-128-CBC                         # Fallback cipher
cipher AES-256-GCM                         # Preferred cipher (AEAD)
```

### Client Network Configuration
```
push "redirect-gateway def1 bypass-dhcp"   # Route all traffic through VPN
push "dhcp-option DNS 8.8.8.8"            # Primary DNS server
push "dhcp-option DNS 8.8.4.4"            # Secondary DNS server
```

**Security Analysis:**
- **AES-256-GCM**: Modern authenticated encryption
- **TLS-Auth**: Prevents DoS attacks and port scanning
- **Certificate Verification**: Multiple layers of authentication
- **User/Group**: Runs with minimal privileges

---

## Client Configuration Template

The `templates/client.conf.tpl` is a Go template that generates client configuration files:

### Server Connection Block
```
{{- range $server := .Hosts }}
remote {{ $server.Host }} {{ $server.Port }} {{ $server.Protocol }}
{{- end }}
```

**Template Logic:**
- Iterates through server definitions
- Supports multiple server entries for redundancy
- Each entry includes host, port, and protocol

### Client Basic Configuration
```
verb 4                                      # Verbose logging for troubleshooting
client                                      # Client mode
nobind                                      # Don't bind to local port
dev tun                                     # TUN device type
cipher AES-256-GCM                         # Encryption cipher
key-direction 1                            # Client key direction (opposite of server)
redirect-gateway def1                      # Route all traffic through VPN
persist-key                                # Don't re-read keys on restart
persist-tun                                # Don't close TUN on restart
#tls-client                                # TLS client mode (commented out)
remote-cert-tls server                     # Verify server certificate
auth-user-pass                            # Prompt for username/password
```

### Embedded Certificates
```
<cert>
{{ .Cert -}}
</cert>
<key>
{{ .Key -}}
</key>
<ca>
{{ .CA -}}
</ca>
<tls-auth>
{{ .TLS -}}
</tls-auth>
```

**Certificate Embedding:**
- **Cert**: Client certificate (public key)
- **Key**: Client private key
- **CA**: Certificate Authority root certificate
- **TLS**: TLS authentication key for additional security

**Template Variables:**
- `.Hosts`: Array of server configurations
- `.Cert`: Client certificate PEM data
- `.Key`: Client private key PEM data
- `.CA`: Certificate Authority PEM data
- `.TLS`: TLS auth key data

---

## Installation and Setup

### Prerequisites

Before starting, ensure you have the following installed on your Linux system:

1. **Docker Engine** (version 20.10+)
2. **Docker Compose** (version 2.0+)
3. **Git** for cloning the repository
4. **Root/sudo access** for Docker operations

### Step-by-Step Installation

#### Step 1: Clone Repository
```bash
git clone https://github.com/flant/ovpn-admin.git
cd ovpn-admin
```

#### Step 2: Configure Environment
Copy the template and configure your environment:

```bash
# Copy the template file
cp .env.template .env

# Edit the .env file with your specific values
nano .env
```

**Critical Configuration Changes:**
```env
# ⚠️ MUST CHANGE: Replace with your server's public IP
OVPN_SERVER="YOUR_PUBLIC_IP:7777:udp"

# Network Configuration (adjust if conflicts exist)
OVPN_SERVER_NET="10.8.0.0"
OVPN_SERVER_MASK="255.255.255.0"
DOCKER_NETWORK="172.20.0.0/16"

# Custom Routes (allows VPN clients to access Docker containers)
OVPN_CUSTOM_ROUTES="172.20.0.0 255.255.0.0"

# MTU Optimization for better performance
OVPN_TUN_MTU="1372"
OVPN_MSSFIX="1332"

# Security Settings
OVPN_PASSWD_AUTH="true"  # Enable two-factor authentication
OVPN_AUTH="true"         # Enable user database
```

**Important Configuration Notes:**
- **OVPN_SERVER**: Replace `YOUR_PUBLIC_IP` with your server's actual public IP address or domain name
- **Port Access**: Ensure port 7777/UDP is open in your firewall
- **Network Conflicts**: Verify the Docker network (`172.20.0.0/16`) and VPN network (`10.8.0.0/24`) don't conflict with existing networks
- **Authentication**: Two-factor auth (certificate + password) is enabled by default for security

#### Step 3: Launch Services
```bash
# Make start script executable
chmod +x start.sh

# Start all services using environment file
./start.sh

# Or use docker-compose directly with env file
docker-compose --env-file .env up -d
```

**Alternative: Using Pre-built Images**
If you want to use pre-built images from Docker Hub:

```bash
# Use the image-based docker-compose file
docker-compose -f docker-compose-image-based.yaml --env-file .env up -d
```

**What happens during startup:**
1. Docker builds both OpenVPN and ovpn-admin images
2. Creates internal network with MTU optimization
3. Generates CA and server certificates (first run only)
4. Configures iptables rules for NAT
5. Starts OpenVPN server on port 1194 (mapped to 7777)
6. Launches web interface on port 8080

#### Step 4: Verify Installation
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f openvpn
docker-compose logs -f ovpn-admin

# Test web interface
curl http://localhost:8080
```

### First-Time Setup Tasks

#### Access Web Interface
1. Open browser to `http://YOUR_SERVER_IP:8080`
2. The interface should load without authentication by default
3. Navigate to "Users" section to manage VPN users

#### Create First VPN User
1. Click "Add User" button
2. Enter username (no special characters)
3. Optionally set password if `OVPN_PASSWD_AUTH: "true"`
4. Download generated `.ovpn` file
5. Import into OpenVPN client

#### Test VPN Connection
1. Install OpenVPN client on test device
2. Import downloaded `.ovpn` configuration
3. Connect and verify:
   - IP address changes to server IP
   - Can access internal Docker services
   - Internet routing works correctly

### Directory Structure After Installation

```
ovpn-admin/
├── docker-compose.yaml          # Main configuration
├── start.sh                     # Startup script
├── easyrsa_master/              # Certificate storage (created)
│   ├── pki/
│   │   ├── ca.crt              # Certificate Authority
│   │   ├── issued/             # Client certificates
│   │   ├── private/            # Private keys
│   │   └── users.db            # User database
├── ccd_master/                  # Client configs (created)
└── setup/
    ├── configure.sh             # OpenVPN setup script
    ├── openvpn.conf            # Base configuration
    └── auth.sh                 # Authentication script
```

---

### Environment Variables Reference

All environment variables are configured via the `.env` file. Copy [`.env.template`](.env.template) to `.env` and modify according to your setup.

### OpenVPN Server Variables

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `OVPN_SERVER_NET` | `10.8.0.0` | VPN client subnet network address | `"10.8.0.0"` |
| `OVPN_SERVER_MASK` | `255.255.255.0` | VPN client subnet mask (/24 = ~250 clients) | `"255.255.255.0"` |
| `OVPN_PASSWD_AUTH` | `false` | Enable username/password authentication | `"true"` for production |
| `OVPN_CUSTOM_ROUTES` | - | Custom routes pushed to clients | `"172.20.0.0 255.255.0.0"` |
| `DOCKER_NETWORK` | `172.20.0.0/16` | Docker internal network CIDR | `"172.20.0.0/16"` |
| `OVPN_TUN_MTU` | `1500` | Tunnel interface MTU size | `"1372"` for optimization |
| `OVPN_MSSFIX` | - | TCP MSS clamping value (MTU-40) | `"1332"` |
| `OVPN_ROLE` | `master` | Server role for master/slave setup | `"master"` or `"slave"` |

### Admin Interface Variables

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `OVPN_DEBUG` | `false` | Enable debug mode for troubleshooting | `"true"` |
| `OVPN_VERBOSE` | `false` | Enable verbose logging | `"true"` |
| `OVPN_NETWORK` | `10.8.0.0/24` | VPN network in CIDR format | `"10.8.0.0/24"` |
| `OVPN_CCD` | `false` | Enable Client Config Directory | `"true"` |
| `OVPN_CCD_PATH` | `/mnt/ccd` | Path to client config directory | `"/mnt/ccd"` |
| `EASYRSA_PATH` | `/mnt/easyrsa` | Path to EasyRSA directory | `"/mnt/easyrsa"` |
| `OVPN_SERVER` | - | **🚨 REQUIRED**: Public server address | `"203.0.113.10:7777:udp"` |
| `OVPN_INDEX_PATH` | `/mnt/easyrsa/pki/index.txt` | Certificate index file path | Default path |
| `OVPN_AUTH` | `false` | Enable authentication features | `"true"` if password auth enabled |
| `OVPN_AUTH_DB_PATH` | `/mnt/easyrsa/pki/users.db` | User database file path | Default path |
| `LOG_LEVEL` | `info` | Application logging level | `"debug"` for troubleshooting |

### Global Variables
| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `EASYRSA_CERT_EXPIRY` | `false` | Certificate expiry duration (in days) | `365` |

### Configuration Examples

#### Production Configuration
```env
# Security-focused production setup
OVPN_PASSWD_AUTH="true"
OVPN_AUTH="true"
LOG_LEVEL="info"
OVPN_DEBUG="false"
OVPN_SERVER="vpn.yourcompany.com:7777:udp"
```

#### Development Configuration
```env
# Debug-friendly development setup
OVPN_PASSWD_AUTH="false"
OVPN_AUTH="false"
LOG_LEVEL="debug"
OVPN_DEBUG="true"
OVPN_SERVER="192.168.1.100:7777:udp"
```

#### Network Optimization
```env
# Optimized for most networks
OVPN_TUN_MTU="1372"
OVPN_MSSFIX="1332"
OVPN_CUSTOM_ROUTES="172.20.0.0 255.255.0.0"
```

### Critical Environment Variables

⚠️ **Must Configure Before First Use:**
1. **`OVPN_SERVER`**: Replace with your actual public IP or domain
2. **`DOCKER_NETWORK`**: Ensure no conflicts with existing networks
3. **`OVPN_PASSWD_AUTH`**: Set to `"true"` for production security

### Network Configuration Variables

| Variable | Purpose | Impact | Best Practice |
|----------|---------|--------|---------------|
| `OVPN_CUSTOM_ROUTES` | Routes pushed to VPN clients | Allows access to internal networks | `"172.20.0.0 255.255.0.0"` for Docker access |
| `DOCKER_NETWORK` | Docker container network | Must match docker-compose network | Verify no IP conflicts |
| `OVPN_TUN_MTU` | Tunnel MTU optimization | Prevents fragmentation | `"1372"` for most networks |
| `OVPN_MSSFIX` | TCP MSS clamping | Prevents TCP fragmentation | `"1332"` (MTU - 40) |

### Security Variables

| Variable | Security Impact | Recommendation | Notes |
|----------|----------------|----------------|-------|
| `OVPN_PASSWD_AUTH` | Enables two-factor auth | `"true"` for production | Requires certificate + password |
| `OVPN_AUTH` | Enables auth database | Must match `OVPN_PASSWD_AUTH` | Required for password auth |
| `LOG_LEVEL` | Controls log verbosity | `"info"` for production, `"debug"` for troubleshooting | Monitor for security events |

---

## Docker Build and Deployment

### Building Images Locally

#### Prerequisites for Building
```bash
# Install build dependencies
sudo apt-get update
sudo apt-get install -y docker.io docker-compose git nodejs npm

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

#### Build Process
```bash
# Clone and enter repository
git clone https://github.com/adityagaikwad888/ovpn-admin-test.git
cd ovpn-admin

# Build both images locally
docker build -f Dockerfile.openvpn -t adityagaikwad888/openvpn:latest .
docker build -f Dockerfile.ovpn-admin -t adityagaikwad888/ovpn-admin:latest .

# Tag with version
docker tag adityagaikwad888/openvpn:latest adityagaikwad888/openvpn:v1.0.0
docker tag adityagaikwad888/ovpn-admin:latest adityagaikwad888/ovpn-admin:v1.0.0
```

#### Push to Docker Hub
```bash
# Login to Docker Hub
docker login

# Push images
docker push adityagaikwad888/openvpn:latest
docker push adityagaikwad888/openvpn:v1.0.0
docker push adityagaikwad888/ovpn-admin:latest
docker push adityagaikwad888/ovpn-admin:v1.0.0
```

#### Automated Build Script
Create a [`build-and-push.sh`](build-and-push.sh) script:

```bash
#!/bin/bash
set -e

# Configuration
DOCKER_REPO_OPENVPN="adityagaikwad888/openvpn"
DOCKER_REPO_ADMIN="adityagaikwad888/ovpn-admin"
VERSION="v1.0.0"

echo "🏗️  Building ovpn-admin locally and pushing to Docker Hub..."

# Login to Docker Hub
docker login

# Build OpenVPN image
echo "🔨 Building OpenVPN server image..."
docker build -f Dockerfile.openvpn \
    -t ${DOCKER_REPO_OPENVPN}:latest \
    -t ${DOCKER_REPO_OPENVPN}:${VERSION} .

# Build ovpn-admin image
echo "🔨 Building ovpn-admin image..."
docker build -f Dockerfile.ovpn-admin \
    -t ${DOCKER_REPO_ADMIN}:latest \
    -t ${DOCKER_REPO_ADMIN}:${VERSION} .

# Push images
echo "🚀 Pushing images to Docker Hub..."
docker push ${DOCKER_REPO_OPENVPN}:latest
docker push ${DOCKER_REPO_OPENVPN}:${VERSION}
docker push ${DOCKER_REPO_ADMIN}:latest
docker push ${DOCKER_REPO_ADMIN}:${VERSION}

echo "✅ All images built and pushed successfully!"
```

#### Using Pre-built Images
```bash
# Use image-based docker-compose file
cp .env.template .env
# Edit .env with your configuration
nano .env

# Deploy using pre-built images
docker-compose -f docker-compose-image-based.yaml --env-file .env up -d
```

### Deployment Options

#### Option 1: Build Locally (Recommended for Development)
```bash
# Traditional build and run
./start.sh

# Or with custom env file
docker-compose --env-file .env up -d
```

#### Option 2: Use Pre-built Images (Recommended for Production)
```bash
# Quick deployment with pre-built images
docker-compose -f docker-compose-image-based.yaml --env-file .env up -d
```

#### Option 3: Custom Build for Production
```bash
# Build with production optimizations
docker build -f Dockerfile.ovpn-admin \
    --build-arg TARGETARCH=amd64 \
    -t your-registry/ovpn-admin:prod .

# Deploy with production settings
LOG_LEVEL=info OVPN_DEBUG=false docker-compose up -d
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Container Startup Failures

**Symptom**: Containers exit immediately or fail to start
```bash
# Check container logs
docker-compose logs openvpn
docker-compose logs ovpn-admin

# Common error: Permission denied
# Solution: Run with sudo or add user to docker group
sudo usermod -aG docker $USER
```

**Certificate Generation Issues**:
```bash
# Remove existing certificates and regenerate
sudo rm -rf easyrsa_master/
docker-compose down
docker-compose up -d
```

#### 2. Network Connectivity Problems

**VPN Clients Can't Connect**:
1. Verify firewall allows port 7777/UDP:
   ```bash
   sudo ufw allow 7777/udp
   # OR for iptables:
   sudo iptables -A INPUT -p udp --dport 7777 -j ACCEPT
   ```

2. Check server IP configuration:
   ```yaml
   # In docker-compose.yaml, ensure correct public IP
   OVPN_SERVER: "YOUR_ACTUAL_PUBLIC_IP:7777:udp"
   ```

3. Verify port mapping:
   ```bash
   docker-compose ps
   # Should show: 0.0.0.0:7777->1194/udp
   ```

**VPN Connected but No Internet**:
```bash
# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should output: 1

# If disabled, enable it
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Can't Access Docker Services**:
```bash
# Verify custom routes configuration
# In docker-compose.yaml:
OVPN_CUSTOM_ROUTES: "172.20.0.0 255.255.0.0"

# Check iptables rules inside container
docker exec -it ovpn-admin_openvpn_1 iptables -t nat -L
```

#### 3. Web Interface Issues

**Admin Panel Not Accessible**:
```bash
# Check if service is running
curl http://localhost:8080

# Check logs for errors
docker-compose logs ovpn-admin

# Verify network mode
docker inspect ovpn-admin_ovpn-admin_1 | grep NetworkMode
# Should show: "NetworkMode": "container:..."
```

**Certificate Management Errors**:
```bash
# Check EasyRSA permissions
docker exec -it ovpn-admin_openvpn_1 ls -la /etc/openvpn/easyrsa/pki/

# Fix permissions if needed
docker exec -it ovpn-admin_openvpn_1 chmod 755 /etc/openvpn/easyrsa/pki/
```

#### 4. Authentication Problems

**Password Authentication Not Working**:
```bash
# Verify openvpn-user is installed
docker exec -it ovpn-admin_openvpn_1 which openvpn-user

# Check user database
docker exec -it ovpn-admin_openvpn_1 ls -la /etc/openvpn/easyrsa/pki/users.db

# Reinitialize database
docker exec -it ovpn-admin_openvpn_1 openvpn-user db-init --db.path=/etc/openvpn/easyrsa/pki/users.db
```

#### 5. Performance Issues

**Slow VPN Connections**:
1. **MTU Optimization**:
   ```yaml
   # In docker-compose.yaml
   OVPN_TUN_MTU: "1372"
   OVPN_MSSFIX: "1332"
   ```

2. **Protocol Selection**:
   ```yaml
   # UDP is generally faster than TCP
   ports:
     - 7777:1194/udp
   ```

3. **Cipher Optimization**:
   ```bash
   # In setup/openvpn.conf, prefer AES-GCM
   cipher AES-256-GCM  # Hardware accelerated
   ```

### Debugging Commands

#### Container Inspection
```bash
# View detailed container configuration
docker inspect ovpn-admin_openvpn_1

# Execute commands inside container
docker exec -it ovpn-admin_openvpn_1 /bin/bash

# Monitor resource usage
docker stats
```

#### Network Debugging
```bash
# Check OpenVPN process
docker exec -it ovpn-admin_openvpn_1 ps aux | grep openvpn

# View OpenVPN logs
docker exec -it ovpn-admin_openvpn_1 tail -f /tmp/openvpn.log

# Check network interfaces
docker exec -it ovpn-admin_openvpn_1 ip addr show

# Test connectivity
docker exec -it ovpn-admin_openvpn_1 ping google.com
```

#### Certificate Debugging
```bash
# List certificates
docker exec -it ovpn-admin_openvpn_1 ls -la /etc/openvpn/easyrsa/pki/issued/

# Verify certificate
docker exec -it ovpn-admin_openvpn_1 openssl x509 -in /etc/openvpn/easyrsa/pki/issued/server.crt -text -noout

# Check certificate revocation list
docker exec -it ovpn-admin_openvpn_1 cat /etc/openvpn/easyrsa/pki/crl.pem
```

### Logs Analysis

#### Important Log Locations
- **OpenVPN Server**: `/tmp/openvpn.log`
- **OpenVPN Status**: `/tmp/openvpn-status.log`
- **Admin Logs**: `docker-compose logs ovpn-admin`

#### Log Patterns to Look For
```bash
# Successful client connection
grep "CLIENT_CONNECT" /tmp/openvpn.log

# Failed authentication
grep "AUTH_FAILED" /tmp/openvpn.log

# Certificate errors
grep "VERIFY ERROR" /tmp/openvpn.log

# Network issues
grep "TLS Error" /tmp/openvpn.log
```

---

## Security Considerations

### Production Security Checklist

#### Network Security
- [ ] **Firewall Configuration**: Only allow necessary ports (7777/UDP, 8080/TCP from admin networks)
- [ ] **Admin Interface**: Restrict port 8080 to trusted networks only
- [ ] **VPN Port**: Consider using non-standard ports to reduce scanning
- [ ] **Network Isolation**: Use separate VLANs for management and client traffic

#### Authentication Security
- [ ] **Two-Factor Auth**: Enable `OVPN_PASSWD_AUTH: "true"` for production
- [ ] **Strong Passwords**: Enforce password complexity for VPN users
- [ ] **Certificate Revocation**: Regularly audit and revoke unused certificates
- [ ] **Admin Access**: Implement authentication for web interface (not built-in)

#### Container Security
- [ ] **User Privileges**: Containers run as root - consider user namespace mapping
- [ ] **Volume Permissions**: Secure certificate storage with appropriate permissions
- [ ] **Image Updates**: Regularly update base images for security patches
- [ ] **Resource Limits**: Set memory and CPU limits in docker-compose.yaml

#### Certificate Management
- [ ] **CA Security**: Protect Certificate Authority private key
- [ ] **Certificate Rotation**: Plan for certificate renewal before expiration
- [ ] **Backup Strategy**: Regular backups of easyrsa_master/ directory
- [ ] **Key Storage**: Use hardware security modules (HSM) for CA keys in high-security environments

#### Monitoring and Auditing
- [ ] **Log Monitoring**: Centralize and monitor OpenVPN logs
- [ ] **Connection Auditing**: Track user connections and data usage
- [ ] **Security Alerts**: Alert on failed authentication attempts
- [ ] **Certificate Monitoring**: Alert on certificate expiration

### Security Warnings

⚠️ **CRITICAL SECURITY NOTES:**

1. **Default Configuration**: This setup lacks authentication on the admin interface
2. **Root Privileges**: Containers run with elevated privileges
3. **Network Exposure**: Admin interface exposed on all interfaces by default
4. **Certificate Storage**: Certificates stored in Docker volumes (secure appropriately)

### Recommended Security Enhancements

#### 1. Admin Interface Protection
```bash
# Use reverse proxy with authentication (nginx + basic auth)
# Or implement VPN-only access to admin interface
```

#### 2. Certificate Security
```bash
# Set strict permissions on certificate directories
chmod 700 easyrsa_master/
chmod 600 easyrsa_master/pki/private/*
```

#### 3. Network Hardening
```yaml
# Restrict admin interface to localhost only
ports:
  - "127.0.0.1:8080:8080"  # Admin interface
  - "7777:1194/udp"        # VPN port
```

#### 4. Logging and Monitoring
```yaml
# Add logging driver for centralized logs
logging:
  driver: "syslog"
  options:
    syslog-address: "udp://your-log-server:514"
```

---

## Knowledge Transfer Summary

### Key Components Understanding
1. **docker-compose.yaml**: Orchestrates two containers with shared networking and storage
2. **configure.sh**: Automates OpenVPN setup, certificate generation, and network configuration
3. **openvpn.conf**: Base OpenVPN server configuration with security-focused defaults
4. **client.conf.tpl**: Go template for generating client configuration files

### Critical Dependencies
- **EasyRSA**: Certificate management and PKI operations
- **iptables**: Network address translation and routing
- **TUN device**: Virtual network interface for VPN tunnel
- **Docker networks**: Container isolation and communication

### Operational Knowledge
- **Certificate lifecycle**: Generation, distribution, revocation, renewal
- **Network routing**: VPN client access to internet and internal services
- **User management**: Adding, removing, and managing VPN users
- **Troubleshooting**: Log analysis, network debugging, certificate issues

### Maintenance Tasks
- **Regular backups** of certificate directory
- **Certificate monitoring** and renewal
- **Log rotation** and monitoring
- **Security updates** for Docker images
- **Network configuration** adjustments for changing requirements

This documentation provides comprehensive knowledge transfer for managing and maintaining the ovpn-admin OpenVPN solution. For additional support, refer to the official OpenVPN documentation and Docker best practices guides.

---

## Installation

### 1. Docker

There is a ready-to-use [docker-compose.yaml](https://github.com/palark/ovpn-admin/blob/master/docker-compose.yaml), so you can just change/add values you need and start it with [start.sh](https://github.com/palark/ovpn-admin/blob/master/start.sh).

Requirements:
You need [Docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) installed.

Commands to execute:

```bash
git clone https://github.com/palark/ovpn-admin.git
cd ovpn-admin
./start.sh
```
#### 1.1
Ready docker images available on [Docker Hub](https://hub.docker.com/r/flant/ovpn-admin/tags) 
. Tags are simple: `$VERSION` or `latest` for ovpn-admin and `openvpn-$VERSION` or `openvpn-latest` for openvpn-server

### 2. Building from source

Requirements. You need Linux with the following components installed:
- [golang](https://golang.org/doc/install)
- [packr2](https://github.com/gobuffalo/packr#installation)
- [nodejs/npm](https://nodejs.org/en/download/package-manager/)

Commands to execute:

```bash
git clone https://github.com/palark/ovpn-admin.git
cd ovpn-admin
./bootstrap.sh
./build.sh
./ovpn-admin 
```

(Please don't forget to configure all needed params in advance.)

### 3. Prebuilt binary

You can also download and use prebuilt binaries from the [releases](https://github.com/palark/ovpn-admin/releases/latest) page — just choose a relevant tar.gz file.


## Notes
* This tool uses external calls for `bash`, `coreutils` and `easy-rsa`, thus **Linux systems only are supported** at the moment.
* To enable additional password authentication, provide `--auth` and `--auth.db="/etc/easyrsa/pki/users.db`" flags and install [openvpn-user](https://github.com/pashcovich/openvpn-user/releases/latest). This tool should be available in your `$PATH` and its binary should be executable (`+x`).
* If you use `--ccd` and `--ccd.path="/etc/openvpn/ccd"` and plan to use static address setup for users, do not forget to provide `--ovpn.network="172.16.100.0/24"` with valid openvpn-server network.
* If you want to pass all the traffic generated by the user, you need to edit `ovpn-admin/templates/client.conf.tpl` and uncomment `redirect-gateway def1`.
* Tested with openvpn-server versions 2.4 and 2.5 and with tls-auth mode only.
* Not tested with Easy-RSA version > 3.0.8.
* Status of user connections update every 28 seconds.
* Master-replica synchronization and additional password authentication do not work with `--storage.backend=kubernetes.secrets` - **WIP**

## Usage

```
usage: ovpn-admin [<flags>]

Flags:
  --help                       show context-sensitive help (try also --help-long and --help-man)

  --listen.host="0.0.0.0"      host for ovpn-admin
  (or OVPN_LISTEN_HOST)

  --listen.port="8080"         port for ovpn-admin
  (or OVPN_LISTEN_PORT)

  --listen.base-url="/"        base URL for ovpn-admin web files
  (or $OVPN_LISTEN_BASE_URL)

  --role="master"              server role, master or slave
  (or OVPN_ROLE)

  --master.host="http://127.0.0.1"  
  (or OVPN_MASTER_HOST)       URL for the master server

  --master.basic-auth.user=""  user for master server's Basic Auth
  (or OVPN_MASTER_USER)
 
  --master.basic-auth.password=""  
  (or OVPN_MASTER_PASSWORD)   password for master server's Basic Auth

  --master.sync-frequency=600  master host data sync frequency in seconds
  (or OVPN_MASTER_SYNC_FREQUENCY)

  --master.sync-token=TOKEN    master host data sync security token
  (or OVPN_MASTER_TOKEN)

  --ovpn.network="172.16.100.0/24"  
  (or OVPN_NETWORK)           NETWORK/MASK_PREFIX for OpenVPN server

  --ovpn.server=HOST:PORT:PROTOCOL ...  
  (or OVPN_SERVER)            HOST:PORT:PROTOCOL for OpenVPN server
                               can have multiple values

  --ovpn.server.behindLB       enable if your OpenVPN server is behind Kubernetes
  (or OVPN_LB)                Service having the LoadBalancer type

  --ovpn.service="openvpn-external"  
  (or OVPN_LB_SERVICE)        the name of Kubernetes Service having the LoadBalancer
                               type if your OpenVPN server is behind it

  --mgmt=main=127.0.0.1:8989 ...  
  (or OVPN_MGMT)              ALIAS=HOST:PORT for OpenVPN server mgmt interface;
                               can have multiple values

  --metrics.path="/metrics"    URL path for exposing collected metrics
  (or OVPN_METRICS_PATH)

  --easyrsa.path="./easyrsa/"  path to easyrsa dir
  (or EASYRSA_PATH)

  --easyrsa.index-path="./easyrsa/pki/index.txt"  
  (or OVPN_INDEX_PATH)        path to easyrsa index file

  --ccd                        enable client-config-dir
  (or OVPN_CCD)

  --ccd.path="./ccd"           path to client-config-dir
  (or OVPN_CCD_PATH)

  --templates.clientconfig-path=""  
  (or OVPN_TEMPLATES_CC_PATH) path to custom client.conf.tpl

  --templates.ccd-path=""      path to custom ccd.tpl
  (or OVPN_TEMPLATES_CCD_PATH)

  --auth.password              enable additional password authorization
  (or OVPN_AUTH)

  --auth.db="./easyrsa/pki/users.db"
  (or OVPN_AUTH_DB_PATH)      database path for password authorization

  --auth.db-init
  (or OVPN_AUTH_DB_INIT)      enable database init if user db not exists or size is 0
   
  --log.level                  set log level: trace, debug, info, warn, error (default info)
  (or LOG_LEVEL)
  
  --log.format                 set log format: text, json (default text)
  (or LOG_FORMAT)
  
  --storage.backend            storage backend: filesystem, kubernetes.secrets (default filesystem)
  (or STORAGE_BACKEND)
 
  --version                    show application version
```

## Authors

ovpn-admin was originally created in [Flant](https://github.com/flant/) and used internally for years.

In March 2021, it [went public](https://medium.com/flant-com/introducing-ovpn-admin-a-web-interface-to-manage-openvpn-users-d81705ad8f23) and was still developed in Flant.
Namely, [@vitaliy-sn](https://github.com/vitaliy-sn) created its first version in Python, and [@pashcovich](https://github.com/pashcovich) rewrote it in Go.

In November 2024, this project was moved to [Palark](https://github.com/palark/), which is currently responsible for its maintenance and development.
