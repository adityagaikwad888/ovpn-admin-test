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
11. [DNS Configuration Deep Dive](#dns-configuration-deep-dive)

---

## Overview

### What is ovpn-admin?

**ovpn-admin** is a web-based management inte# Client-Side Setup
# VPN Connection Guide  

This guide explains how to connect to a VPN on **macOS** using Tunnelblick and on **Linux** using Network Manager.  

---

## macOS – Connect VPN via Tunnelblick  

### 1. Download & Install Tunnelblick  
- Visit [tunnelblick.net](https://tunnelblick.net)  
- Download the latest stable release for macOS  
- Open the `.dmg` file and drag **Tunnelblick** into your **Applications** folder  
- Open Tunnelblick (you may need to allow it in **System Preferences -> Security & Privacy**)  

### 2. Obtain VPN Configuration Files  
- we sent u `.ovpn` file 
- Download and Open the `.ovpn` file and comment out these 3 lines using #
```bash
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
```
### 3. Install the Configuration  
- Double-click the `.ovpn` file, Tunnelblick will ask to install it  
- Choose **Only Me** (for your account only) or **All Users**  
![screeshot2.jpg]
- The configuration will now be available in Tunnelblick  

### 4. Connect to the VPN  
- Click the **Tunnelblick** icon in the top menu bar (near the clock)  
- Select your VPN profile present at left hand side and click **Connect**  
![screenshot12.jpg](/screenshot12.jpg)
- Enter your VPN username and password (if required)  
![screenshot2.jpg](/screenshot2.jpg)
- Once connected, the icon will turn dark, indicating the tunnel is active  

### 5. Verify the Connection  
- Open terminal and just run command to confirm your IP has changed. you will get ip in 10.8.0.0/16 cider
```bash
ifconfig
```
- Or check logs via:  
  - Tunnelblick menu -> **VPN Details** -> select configuration -> **Log**  

### 6. Disconnect When Done  
- Click the **Tunnelblick** icon -> select your VPN -> **Disconnect**  
![screeshot4.jpg](/screeshot4.jpg)

---


## Linux – Connect VPN via GUI (Network Manager)  

### 1. Open Network Settings
- Install the required Packages
```bash
sudo apt update
sudo apt install network-manager-openvpn network-manager-openvpn-gnome -y
sudo systemctl restart NetworkManager
```
- Click the **Network** icon (top-right corner)  
- Go to **Settings -> Network -> VPN -> + Add VPN**  
![screenshot_from_2025-09-22_16-01-22.png](/screenshot_from_2025-09-22_16-01-22.png)

### 2. Import Configuration  
- Select **Import from file…**  
- Choose your `.ovpn` file  
![screenshot_from_2025-09-22_16-01-43.png](/screenshot_from_2025-09-22_16-01-43.png)

### 3. Authenticate & Connect
- Don't directly connect after step 2
- Go to the identity section. If u don't get it click on vpn settings for that perticular vpn and then go to identity section.
- Enter your username and password (if required)  
![screenshot_from_2025-09-22_16-02-32.png](/screenshot_from_2025-09-22_16-02-32.png)

- Save the configuration and click **Connect**
The three dots indicate that you are not connected to the VPN.
![screenshot_from_2025-09-22_16-05-04.png](/screenshot_from_2025-09-22_16-05-04.png)
- you are connected to vpn
![screenshot_from_2025-09-22_16-03-22.png](/screenshot_from_2025-09-22_16-03-22.png)

### 4. Verify the Connection  
- Open terminal and just run command to confirm your IP has changed. you will get ip in 10.8.0.0/16 cider
```bash
hostname -I
```rface for OpenVPN servers that simplifies the administration of VPN users, certificates, and network configurations. It consists of two main components:

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
        - subnet: 20.20.0.0/16              # Internal container network
```

**Explanation:**
- Creates isolated network for containers
- MTU of 1372 prevents fragmentation issues common in VPN scenarios
- Subnet `20.20.0.0/16` provides plenty of IP addresses for containers
- **Updated subnet** from `172.20.0.0/16` to `20.20.0.0/16` to avoid conflicts with AWS VPC networks

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
dns:
  - 172.31.0.2                             # Primary DNS (Private DNS server)
  - 8.8.8.8                                # Secondary DNS (Google Public DNS)
```

**Security Notes:**
- `NET_ADMIN` capability allows network interface manipulation
- IP forwarding is essential for routing VPN traffic
- UDP protocol chosen for better VPN performance than TCP

**DNS Configuration:**
- **Primary DNS (172.31.0.2)**: Private DNS server for internal domain resolution
  - Used for resolving private hosted zones (e.g., `*.spreezy.in`)
  - Typically points to AWS Route53 private DNS or internal DNS server
- **Secondary DNS (8.8.8.8)**: Google Public DNS for internet domain resolution
  - Fallback for public DNS queries
  - Ensures DNS resolution even if private DNS is unavailable

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

# DNS Domain Configuration
if [ ! -z "$CUSTOM_DOMAIN" ]; then
    echo 'push "dhcp-option DOMAIN '${CUSTOM_DOMAIN}'"' >> /etc/openvpn/openvpn.conf
fi

# Primary DNS Server
if [ ! -z "$CUSTOM_DNS_PRIM" ]; then
    echo 'push "dhcp-option DNS '${CUSTOM_DNS_PRIM}'"' >> /etc/openvpn/openvpn.conf
fi

# Secondary DNS Server
if [ ! -z "$CUSTOM_DNS_SECO" ]; then
    echo 'push "dhcp-option DNS '${CUSTOM_DNS_SECO}'"' >> /etc/openvpn/openvpn.conf
fi

# MTU Configuration
if [ ! -z "$OVPN_TUN_MTU" ]; then
    echo "tun-mtu $OVPN_TUN_MTU" >> /etc/openvpn/openvpn.conf
fi

# MSS Fix Configuration
if [ ! -z "$OVPN_MSSFIX" ]; then
    echo "mssfix $OVPN_MSSFIX" >> /etc/openvpn/openvpn.conf
fi

# Custom Routes
if [ ! -z "${OVPN_CUSTOM_ROUTES}" ]; then
  echo 'push "route '${OVPN_CUSTOM_ROUTES}'"' >> /etc/openvpn/openvpn.conf
fi
```

**Configuration Logic:**
- Copies base configuration to runtime location
- **DNS Domain Push**: Sets custom DNS domain suffix for VPN clients
  - `CUSTOM_DOMAIN`: Domain suffix (e.g., "spreezy.in") for DNS resolution
  - VPN clients will automatically append this domain to unqualified hostnames
- **Primary DNS Push**: Configures primary DNS server for VPN clients
  - `CUSTOM_DNS_PRIM`: Private DNS server (e.g., "172.31.0.2") for internal domains
  - Resolves private hosted zones and internal resources
- **Secondary DNS Push**: Configures fallback DNS server for VPN clients
  - `CUSTOM_DNS_SECO`: Public DNS server (e.g., "8.8.8.8") for internet domains
  - Ensures DNS redundancy and public domain resolution
- Dynamically adds MTU settings if specified in .env file
- Adds MSS fix if specified in .env file
- Injects custom routes for client access

**DNS Resolution Flow:**
1. VPN client queries hostname → checks if matches `CUSTOM_DOMAIN`
2. If internal domain → queries `CUSTOM_DNS_PRIM` (private DNS)
3. If external domain or timeout → queries `CUSTOM_DNS_SECO` (public DNS)
4. Result returned to client application

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
keepalive 10 300                           # Ping every 10s, timeout after 300s

# ADDED: Prevent idle disconnections (CRITICAL FIX!)
inactive 0                                 # Disable auto-disconnect on inactivity
ping-timer-rem                             # Restart timeout on ping receipt
```

**Connection Stability Enhancements:**
- **keepalive 10 300**: Increased timeout from 60s to 300s for more stable connections
- **inactive 0**: Disables automatic disconnection due to inactivity (critical for long-running connections)
- **ping-timer-rem**: Resets the timeout timer when ping is received, preventing false disconnects

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
cipher AES-256-GCM                         # Modern AEAD cipher (AES-128-CBC removed)
```

**Security Notes:**
- Using only **AES-256-GCM** cipher for enhanced security and performance
- Removed **AES-128-CBC** fallback cipher to enforce stronger encryption standards
- AES-256-GCM provides authenticated encryption with associated data (AEAD)

### Client Network Configuration
```
push "redirect-gateway def1 bypass-dhcp"   # Route all traffic through VPN
```

**Note:** DNS and domain settings are dynamically injected by `configure.sh` based on environment variables:
- `CUSTOM_DOMAIN` → `push "dhcp-option DOMAIN xxx"`
- `CUSTOM_DNS_PRIM` → `push "dhcp-option DNS xxx"` (Primary)
- `CUSTOM_DNS_SECO` → `push "dhcp-option DNS xxx"` (Secondary)

**DNS Configuration Details:**

| Setting | Environment Variable | Example Value | Purpose |
|---------|---------------------|---------------|---------|
| **Domain Suffix** | `CUSTOM_DOMAIN` | `spreezy.in` | DNS search domain for unqualified hostnames |
| **Primary DNS** | `CUSTOM_DNS_PRIM` | `172.31.0.2` | Private DNS server for internal domain resolution |
| **Secondary DNS** | `CUSTOM_DNS_SECO` | `8.8.8.8` | Public DNS server for internet domain resolution |

**DNS Resolution Examples:**

```bash
# Example 1: Internal resource lookup
VPN Client queries: "api-server"
→ Expanded to: "api-server.spreezy.in" (using CUSTOM_DOMAIN)
→ Resolved by: 172.31.0.2 (CUSTOM_DNS_PRIM)
→ Returns: Private IP (e.g., 10.0.1.50)

# Example 2: Public domain lookup
VPN Client queries: "google.com"
→ Not matching CUSTOM_DOMAIN
→ Resolved by: 8.8.8.8 (CUSTOM_DNS_SECO)
→ Returns: Public IP (e.g., 142.250.185.46)

# Example 3: Fully qualified internal domain
VPN Client queries: "db.spreezy.in"
→ Matches CUSTOM_DOMAIN
→ Resolved by: 172.31.0.2 (CUSTOM_DNS_PRIM)
→ Returns: Private IP from Route53 private hosted zone
```

**Why This Configuration?**

This DNS setup enables **split-horizon DNS** for VPN clients:

1. **Private Domain Resolution**:
   - Internal services (e.g., `*.spreezy.in`) resolve via private DNS
   - Enables access to AWS resources in private subnets
   - Works with Route53 private hosted zones

2. **Public Domain Resolution**:
   - Internet domains resolve via public DNS
   - Ensures normal internet browsing works
   - Provides DNS redundancy and reliability

3. **Domain Suffix Automation**:
   - Users can type short names (e.g., "api-server")
   - Automatically expanded to FQDN (e.g., "api-server.spreezy.in")
   - Improves user experience and reduces typing

**Security Analysis:**
- **AES-256-GCM**: Modern authenticated encryption
- **TLS-Auth**: Prevents DoS attacks and port scanning
- **Certificate Verification**: Multiple layers of authentication
- **User/Group**: Runs with minimal privileges
- **DNS Security**: Private DNS prevents DNS leaks and ensures internal resolution

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
cipher AES-256-GCM                         # Encryption cipher (matching server)
key-direction 1                            # Client key direction (opposite of server)
redirect-gateway def1                      # Route all traffic through VPN
persist-key                                # Don't re-read keys on restart
persist-tun                                # Don't close TUN on restart
remote-cert-tls server                     # Verify server certificate
auth-user-pass                            # Prompt for username/password

# DNS Management Scripts (Linux clients)
script-security 2                          # Allow calling external scripts
up /etc/openvpn/update-resolv-conf        # Update DNS on connection
down /etc/openvpn/update-resolv-conf      # Restore DNS on disconnection
```

**Client Configuration Details:**
- **script-security 2**: Enables execution of the DNS update scripts
- **update-resolv-conf**: Automatically manages DNS settings on Linux clients
  - **up**: Called when VPN connection is established - updates `/etc/resolv.conf` with VPN DNS
  - **down**: Called when VPN disconnects - restores original DNS settings
- **Note for Windows/macOS**: These DNS scripts are Linux-specific. Windows and macOS clients handle DNS automatically

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
DOCKER_NETWORK="20.20.0.0/16"

# Custom Routes (allows VPN clients to access Docker containers)
OVPN_CUSTOM_ROUTES="20.20.0.0 255.255.0.0"

# DNS Configuration (for VPN clients)
CUSTOM_DOMAIN="spreezy.in"          # DNS search domain
CUSTOM_DNS_PRIM="172.31.0.2"        # Primary DNS (private)
CUSTOM_DNS_SECO="8.8.8.8"           # Secondary DNS (public)

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
- **Network Conflicts**: Verify the Docker network (`20.20.0.0/16`) and VPN network (`10.8.0.0/24`) don't conflict with existing networks
- **Authentication**: Two-factor auth (certificate + password) is enabled by default for security
- **DNS Configuration**: 
  - Set `CUSTOM_DOMAIN` to your private domain (e.g., "spreezy.in" or "internal.company.com")
  - Set `CUSTOM_DNS_PRIM` to your private DNS server IP (e.g., AWS VPC DNS at "172.31.0.2")
  - Set `CUSTOM_DNS_SECO` to a public DNS server (e.g., "8.8.8.8" for Google or "1.1.1.1" for Cloudflare)
  - If you don't use private DNS, you can omit these variables or set both DNS to public resolvers

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
├── .env                         # Environment variables (create from .env.template)
├── .env.template                # Environment template
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

### DNS and Domain Configuration Variables

| Variable | Default | Description | Example | Use Case |
|----------|---------|-------------|---------|----------|
| `CUSTOM_DOMAIN` | - | DNS search domain suffix pushed to VPN clients | `"spreezy.in"` | Enables short hostname lookup (e.g., "api" → "api.spreezy.in") |
| `CUSTOM_DNS_PRIM` | - | Primary DNS server for VPN clients | `"172.31.0.2"` | Private DNS server for internal domain resolution (Route53 private hosted zone) |
| `CUSTOM_DNS_SECO` | - | Secondary/fallback DNS server for VPN clients | `"8.8.8.8"` | Public DNS for internet domain resolution (Google DNS) |

**DNS Configuration Notes:**

1. **CUSTOM_DOMAIN** (DNS Search Domain):
   - Automatically appended to unqualified hostnames
   - Example: If `CUSTOM_DOMAIN="spreezy.in"`, querying "database" resolves to "database.spreezy.in"
   - Improves user experience by allowing short names
   - Only one domain suffix can be configured

2. **CUSTOM_DNS_PRIM** (Primary DNS Server):
   - **Typical Value**: `172.31.0.2` (AWS VPC DNS resolver)
   - Used for resolving private hosted zones in AWS Route53
   - Resolves internal resources not accessible from public internet
   - Should point to your private DNS infrastructure

3. **CUSTOM_DNS_SECO** (Secondary DNS Server):
   - **Typical Value**: `8.8.8.8` (Google) or `1.1.1.1` (Cloudflare)
   - Provides DNS redundancy if primary DNS fails
   - Resolves public internet domains
   - Ensures VPN clients can access external resources

**Docker Container DNS Configuration:**

The OpenVPN container itself also uses DNS servers configured in `docker-compose.yaml`:
```yaml
dns:
  - 172.31.0.2  # Container uses private DNS
  - 8.8.8.8     # Container uses public DNS for fallback
```

This is **separate** from the DNS pushed to VPN clients but typically uses the same values.

### Global Variables
| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `EASYRSA_CERT_EXPIRY` | `365` | Certificate expiry duration (in days) | `365` (1 year), `1825` (5 years) |

### Configuration Examples

#### Production Configuration with Private DNS
```env
# Security-focused production setup with AWS integration
OVPN_PASSWD_AUTH="true"
OVPN_AUTH="true"
LOG_LEVEL="info"
OVPN_DEBUG="false"
OVPN_SERVER="vpn.yourcompany.com:7777:udp"

# DNS Configuration for private resources
CUSTOM_DOMAIN="internal.company.com"
CUSTOM_DNS_PRIM="172.31.0.2"        # AWS VPC DNS
CUSTOM_DNS_SECO="8.8.8.8"           # Google Public DNS

# Network settings
DOCKER_NETWORK="20.20.0.0/16"
OVPN_CUSTOM_ROUTES="20.20.0.0 255.255.0.0"
```

#### Development Configuration
```env
# Debug-friendly development setup
OVPN_PASSWD_AUTH="false"
OVPN_AUTH="false"
LOG_LEVEL="debug"
OVPN_DEBUG="true"
OVPN_SERVER="192.168.1.100:7777:udp"

# Public DNS only (no private infrastructure)
CUSTOM_DNS_PRIM="8.8.8.8"
CUSTOM_DNS_SECO="1.1.1.1"
```

#### Network Optimization
```env
# Optimized for most networks
OVPN_TUN_MTU="1372"
OVPN_MSSFIX="1332"
OVPN_CUSTOM_ROUTES="20.20.0.0 255.255.0.0"
```

#### Multi-Cloud Setup (AWS + On-Premise)
```env
# VPN server with access to multiple networks
OVPN_SERVER="vpn.example.com:7777:udp"

# DNS Configuration
CUSTOM_DOMAIN="company.local"       # Internal domain
CUSTOM_DNS_PRIM="10.0.0.10"        # On-premise DNS server
CUSTOM_DNS_SECO="172.31.0.2"       # AWS VPC DNS

# Network Routes
DOCKER_NETWORK="20.20.0.0/16"
OVPN_CUSTOM_ROUTES="10.0.0.0 255.0.0.0"  # On-premise network

# Additional routes can be added in configure.sh if needed
```

### Critical Environment Variables

⚠️ **Must Configure Before First Use:**
1. **`OVPN_SERVER`**: Replace with your actual public IP or domain
2. **`DOCKER_NETWORK`**: Ensure no conflicts with existing networks (changed from `172.20.0.0/16` to `20.20.0.0/16`)
3. **`OVPN_PASSWD_AUTH`**: Set to `"true"` for production security
4. **DNS Variables** (if using private infrastructure):
   - **`CUSTOM_DOMAIN`**: Your private domain suffix
   - **`CUSTOM_DNS_PRIM`**: Your private DNS server IP
   - **`CUSTOM_DNS_SECO`**: Public DNS for fallback

### Network Configuration Variables

| Variable | Purpose | Impact | Best Practice |
|----------|---------|--------|---------------|
| `OVPN_CUSTOM_ROUTES` | Routes pushed to VPN clients | Allows access to internal networks | `"20.20.0.0 255.255.0.0"` for Docker access |
| `DOCKER_NETWORK` | Docker container network | Must match docker-compose network | `"20.20.0.0/16"` - verify no IP conflicts |
| `OVPN_TUN_MTU` | Tunnel MTU optimization | Prevents fragmentation | `"1372"` for most networks |
| `OVPN_MSSFIX` | TCP MSS clamping | Prevents TCP fragmentation | `"1332"` (MTU - 40) |
| `CUSTOM_DOMAIN` | DNS search domain suffix | Enables short hostname resolution | `"spreezy.in"` or `"internal.company.com"` |
| `CUSTOM_DNS_PRIM` | Primary DNS server | Resolves private domains | `"172.31.0.2"` for AWS VPC DNS |
| `CUSTOM_DNS_SECO` | Secondary DNS server | Fallback and public DNS | `"8.8.8.8"` or `"1.1.1.1"` |

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

## DNS Configuration Deep Dive

### Overview

The ovpn-admin setup implements a **split-horizon DNS** configuration that enables VPN clients to seamlessly access both internal private resources and public internet services. This section provides detailed information about how DNS works in this OpenVPN setup.

### DNS Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPN Client                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Application queries: "database.spreezy.in"              │  │
│  └────────────────────────┬─────────────────────────────────┘  │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  VPN Client DNS Resolver                                 │  │
│  │  - Domain Suffix: spreezy.in                            │  │
│  │  - Primary DNS: 172.31.0.2                              │  │
│  │  - Secondary DNS: 8.8.8.8                               │  │
│  └──────────────┬──────────────────────┬────────────────────┘  │
└─────────────────┼──────────────────────┼───────────────────────┘
                  │                      │
        ┌─────────▼────────┐   ┌────────▼──────────┐
        │  Private DNS     │   │  Public DNS       │
        │  172.31.0.2      │   │  8.8.8.8          │
        │  (Route53 PHZ)   │   │  (Google DNS)     │
        └──────────────────┘   └───────────────────┘
                │                      │
        ┌───────▼────────┐    ┌────────▼──────────┐
        │ Internal IPs   │    │ Public IPs        │
        │ 10.0.x.x       │    │ Internet          │
        └────────────────┘    └───────────────────┘
```

### DNS Configuration Layers

#### 1. Docker Container DNS (docker-compose.yaml)

```yaml
services:
  openvpn:
    dns:
      - 172.31.0.2  # Private DNS for container itself
      - 8.8.8.8     # Public DNS for container
```

**Purpose**: Configures DNS resolution **for the OpenVPN container itself** (not VPN clients)
- Used when the container needs to resolve hostnames
- Enables the container to access private resources during setup
- Separate from DNS pushed to VPN clients

#### 2. VPN Client DNS Push (configure.sh + Environment Variables)

```bash
# In configure.sh
if [ ! -z "$CUSTOM_DOMAIN" ]; then
    echo 'push "dhcp-option DOMAIN '${CUSTOM_DOMAIN}'"' >> /etc/openvpn/openvpn.conf
fi

if [ ! -z "$CUSTOM_DNS_PRIM" ]; then
    echo 'push "dhcp-option DNS '${CUSTOM_DNS_PRIM}'"' >> /etc/openvpn/openvpn.conf
fi

if [ ! -z "$CUSTOM_DNS_SECO" ]; then
    echo 'push "dhcp-option DNS '${CUSTOM_DNS_SECO}'"' >> /etc/openvpn/openvpn.conf
fi
```

**Purpose**: Configures DNS resolution **for VPN clients** when they connect
- Settings pushed from server to client during VPN connection
- Overwrites client's local DNS settings while VPN is active
- Restored to original when VPN disconnects

### Environment Variables Explained

#### CUSTOM_DOMAIN
```env
CUSTOM_DOMAIN="spreezy.in"
```

**What it does:**
- Sets DNS search domain suffix for VPN clients
- Automatically appends domain to unqualified hostnames
- Simplifies internal resource access

**Examples:**
```bash
# Without CUSTOM_DOMAIN:
ping database              # Fails - not found

# With CUSTOM_DOMAIN="spreezy.in":
ping database              # Success - resolves to "database.spreezy.in"
ping api                   # Success - resolves to "api.spreezy.in"
```

**Use Cases:**
- Internal service discovery in microservices
- Simplified access to AWS resources
- Private hosted zones in Route53
- Corporate intranet resources

#### CUSTOM_DNS_PRIM
```env
CUSTOM_DNS_PRIM="172.31.0.2"
```

**What it does:**
- Sets primary DNS server for VPN clients
- First DNS server queried for all hostnames
- Typically points to private DNS infrastructure

**Common Values:**
| Value | Description | Use Case |
|-------|-------------|----------|
| `172.31.0.2` | AWS VPC DNS Resolver | AWS environments with Route53 private zones |
| `10.0.0.2` | Custom VPC DNS | Alternative AWS VPC DNS |
| `192.168.1.1` | Corporate DNS | On-premise Active Directory/BIND DNS |
| `10.x.x.x` | Private DNS | Any private DNS server in RFC1918 space |

**Why 172.31.0.2?**
- AWS VPC default DNS server
- Located at VPC CIDR base + 2
- Resolves Route53 private hosted zones
- Resolves EC2 instance private DNS names

#### CUSTOM_DNS_SECO
```env
CUSTOM_DNS_SECO="8.8.8.8"
```

**What it does:**
- Sets secondary/fallback DNS server
- Queried if primary DNS fails or times out
- Provides public DNS resolution

**Common Values:**
| Value | Provider | Features |
|-------|----------|----------|
| `8.8.8.8` | Google Public DNS | Fast, reliable, widely used |
| `1.1.1.1` | Cloudflare DNS | Privacy-focused, fastest |
| `9.9.9.9` | Quad9 | Security-focused, malware blocking |
| `208.67.222.222` | OpenDNS | Filtering options |

### DNS Resolution Flow

#### Scenario 1: Querying Internal Resource

```
VPN Client: "Hey, what's the IP of 'database'?"
             ↓
Step 1: Append CUSTOM_DOMAIN
        "database" → "database.spreezy.in"
             ↓
Step 2: Query CUSTOM_DNS_PRIM (172.31.0.2)
        Request: "database.spreezy.in"
             ↓
Step 3: Private DNS checks Route53 private zone
        Found: database.spreezy.in → 10.0.1.25
             ↓
Step 4: Return private IP to VPN client
        Client connects to: 10.0.1.25
```

#### Scenario 2: Querying Public Resource

```
VPN Client: "What's the IP of 'google.com'?"
             ↓
Step 1: Check if matches CUSTOM_DOMAIN
        "google.com" ≠ "*.spreezy.in" → No suffix added
             ↓
Step 2: Query CUSTOM_DNS_PRIM (172.31.0.2)
        Request: "google.com"
             ↓
Step 3: Private DNS forwards to upstream or times out
        Not in private zone → forward to public DNS
             ↓
Step 4: Query CUSTOM_DNS_SECO (8.8.8.8)
        Request: "google.com"
             ↓
Step 5: Public DNS returns public IP
        Found: google.com → 142.250.185.46
             ↓
Step 6: Return public IP to VPN client
        Client connects to internet
```

#### Scenario 3: Private DNS Failure

```
VPN Client: "What's the IP of 'api.spreezy.in'?"
             ↓
Step 1: Query CUSTOM_DNS_PRIM (172.31.0.2)
        Request: "api.spreezy.in"
             ↓
Step 2: Private DNS is down (timeout after 5s)
        ❌ No response
             ↓
Step 3: Fallback to CUSTOM_DNS_SECO (8.8.8.8)
        Request: "api.spreezy.in"
             ↓
Step 4: Public DNS response
        ❌ Not found (private domain)
             ↓
Step 5: Return error to VPN client
        Client cannot resolve hostname
```

### Configuration Best Practices

#### 1. AWS Environment Setup

```env
# Optimal AWS configuration
CUSTOM_DOMAIN="internal.company.com"   # Your Route53 private zone
CUSTOM_DNS_PRIM="172.31.0.2"          # AWS VPC DNS
CUSTOM_DNS_SECO="8.8.8.8"             # Google Public DNS

# docker-compose.yaml DNS (for container)
dns:
  - 172.31.0.2
  - 8.8.8.8
```

**Enables:**
- Access to EC2 instances by private DNS names
- Route53 private hosted zone resolution
- RDS endpoint resolution
- ECS/EKS service discovery
- Internet access for VPN clients

#### 2. Multi-Cloud Environment

```env
# Access to AWS + Azure + On-Premise
CUSTOM_DOMAIN="global.company.com"
CUSTOM_DNS_PRIM="10.0.0.53"           # Central DNS server
CUSTOM_DNS_SECO="1.1.1.1"             # Cloudflare DNS
```

#### 3. Development Environment

```env
# Simple development setup
CUSTOM_DOMAIN=""                       # No domain suffix needed
CUSTOM_DNS_PRIM="8.8.8.8"             # Public DNS only
CUSTOM_DNS_SECO="1.1.1.1"             # Backup public DNS
```

#### 4. High Security Environment

```env
# Restricted DNS with monitoring
CUSTOM_DOMAIN="secure.company.local"
CUSTOM_DNS_PRIM="10.1.1.1"            # Internal DNS with logging
CUSTOM_DNS_SECO="10.1.1.2"            # Backup internal DNS (no public DNS)
```

### Testing DNS Configuration

#### From VPN Client (After Connecting)

```bash
# Check DNS servers being used
cat /etc/resolv.conf
# Should show:
# search spreezy.in
# nameserver 172.31.0.2
# nameserver 8.8.8.8

# Test internal DNS resolution
nslookup database.spreezy.in
# Should return private IP

# Test public DNS resolution
nslookup google.com
# Should return public IP

# Test domain suffix
ping database
# Should resolve to database.spreezy.in

# Verify DNS query path
dig database.spreezy.in +trace
```

#### From OpenVPN Server Container

```bash
# Enter the container
docker exec -it ovpn-admin_openvpn_1 bash

# Check container DNS
cat /etc/resolv.conf
# Should show: nameserver 172.31.0.2, nameserver 8.8.8.8

# Test DNS resolution
nslookup internal-service.spreezy.in
ping google.com
```

#### From Admin Interface

```bash
# Check what's being pushed to clients
docker exec -it ovpn-admin_openvpn_1 cat /etc/openvpn/openvpn.conf | grep "dhcp-option"

# Should show:
# push "dhcp-option DOMAIN spreezy.in"
# push "dhcp-option DNS 172.31.0.2"
# push "dhcp-option DNS 8.8.8.8"
```

### Common DNS Issues and Solutions

#### Issue 1: VPN Clients Can't Resolve Internal Domains

**Symptoms:**
- `ping database.spreezy.in` fails
- Internal services not accessible
- Public internet works fine

**Diagnosis:**
```bash
# Check if DNS settings are pushed
cat /etc/resolv.conf  # On VPN client
nslookup database.spreezy.in 172.31.0.2  # Direct query to private DNS
```

**Solutions:**
1. Verify `CUSTOM_DNS_PRIM` is correct
2. Ensure private DNS server is reachable from VPN network
3. Check VPN routes include private DNS subnet
4. Verify Route53 private zone is associated with VPC

#### Issue 2: Can't Access Internet While Connected

**Symptoms:**
- `ping google.com` fails
- All DNS queries timeout
- VPN connection is active

**Diagnosis:**
```bash
# Check if public DNS is configured
cat /etc/resolv.conf
# Should have secondary DNS (8.8.8.8)

# Test public DNS directly
nslookup google.com 8.8.8.8
```

**Solutions:**
1. Verify `CUSTOM_DNS_SECO` is set
2. Check `redirect-gateway` is working
3. Ensure NAT rules in container are correct

#### Issue 3: Domain Suffix Not Working

**Symptoms:**
- `ping database` fails (without FQDN)
- Must type full domain: `ping database.spreezy.in`

**Diagnosis:**
```bash
# Check search domain
cat /etc/resolv.conf | grep search
# Should show: search spreezy.in
```

**Solutions:**
1. Verify `CUSTOM_DOMAIN` is set in .env
2. Check configure.sh properly adds domain push
3. Restart OpenVPN service
4. Reconnect VPN client

#### Issue 4: DNS Resolution is Slow

**Symptoms:**
- Long delays before websites load
- `nslookup` takes 5+ seconds

**Diagnosis:**
```bash
# Time DNS queries
time nslookup database.spreezy.in
time nslookup google.com

# Check if primary DNS is timing out
tcpdump -i tun0 port 53
```

**Solutions:**
1. Check primary DNS server latency
2. Swap DNS order if private DNS is slow
3. Use geographically closer public DNS
4. Verify firewall doesn't block UDP/53

### Security Considerations

#### DNS Leak Prevention

The configuration ensures **no DNS leaks** by:
1. Overriding client's default DNS servers
2. Routing all DNS queries through VPN tunnel
3. Using controlled DNS servers (not ISP DNS)

**Verify no DNS leaks:**
```bash
# Before connecting VPN
nslookup -type=TXT whoami.akamai.net

# After connecting VPN
nslookup -type=TXT whoami.akamai.net
# Should show VPN server's IP, not your ISP
```

#### Private DNS Security

**Risks:**
- Unauthorized access to private DNS reveals network topology
- DNS queries can be logged and monitored
- Compromised DNS can redirect traffic

**Mitigations:**
1. Restrict private DNS access to VPN network only
2. Use DNS query logging and monitoring
3. Implement DNSSEC where possible
4. Regular audit of DNS records
5. Use DNS firewall rules (AWS Network Firewall)

### Advanced DNS Configurations

#### Multiple DNS Domains

For organizations with multiple private zones:

```bash
# In configure.sh, add custom configuration:
echo 'push "dhcp-option DOMAIN spreezy.in"' >> /etc/openvpn/openvpn.conf
echo 'push "dhcp-option DOMAIN aws.internal"' >> /etc/openvpn/openvpn.conf
echo 'push "dhcp-option DOMAIN azure.local"' >> /etc/openvpn/openvpn.conf
```

#### Conditional DNS Forwarding

For split DNS with multiple DNS servers:

```bash
# Different DNS servers for different domains
# Requires dnsmasq or similar in the VPN network
# Example: Forward *.aws.com to AWS DNS, *.azure.com to Azure DNS
```

### Monitoring DNS

#### Key Metrics to Monitor

1. **DNS Query Success Rate**
   ```bash
   # Monitor DNS failures
   grep "query failed" /var/log/syslog
   ```

2. **DNS Response Time**
   ```bash
   # Measure DNS latency
   dig @172.31.0.2 database.spreezy.in | grep "Query time"
   ```

3. **DNS Server Availability**
   ```bash
   # Check if DNS servers are reachable
   ping -c 1 172.31.0.2
   ping -c 1 8.8.8.8
   ```

#### DNS Logging

Enable DNS query logging for security auditing:

```bash
# In private DNS server (e.g., Route53 query logging)
# Log all DNS queries from VPN subnet
# Alert on suspicious patterns
```

### Summary

The DNS configuration in ovpn-admin provides:

✅ **Split-Horizon DNS**: Access both private and public resources seamlessly  
✅ **Automatic Domain Suffix**: Simplifies internal resource access  
✅ **DNS Redundancy**: Fallback DNS ensures reliability  
✅ **No DNS Leaks**: All DNS queries routed through VPN  
✅ **Flexible Configuration**: Adapts to various network environments  

**Key Takeaways:**
- `CUSTOM_DOMAIN` enables short hostname usage
- `CUSTOM_DNS_PRIM` resolves private infrastructure
- `CUSTOM_DNS_SECO` provides fallback and public resolution
- Docker container DNS is separate from VPN client DNS
- Proper configuration is critical for seamless VPN experience

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
