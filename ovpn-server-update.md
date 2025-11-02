# OpenVPN Server Update / Rollback / Access Process

This document describes the step-by-step process for updating the OpenVPN server.

## Overview

The update process involves temporarily redirecting traffic to ensure zero downtime while updating the server components and Docker images.

## Prerequisites

- Access to AWS Route53 for DNS record management
- Access to the server hosting the OpenVPN service
- Necessary permissions to pull Docker images from Nexus (or your image registry)
- Backup of current configuration (recommended)

## Update Steps

### Step 1: Prepare Docker Compose Configuration and Backup
Create a backup of your current working `docker-compose.yml` file:
```bash
cp docker-compose.yml docker-compose-backup.yml
```
Update docker-compose.yml for new images or configurations as needed.

Ensure your `docker-compose.yml` file is properly configured and ready for the update.

You should at OpenVPN server directory (/home/ubuntu/docker/ovpn):

```bash
# Review the docker-compose.yml file
cat docker-compose.yml
```

### Step 2: Update Route53 Private DNS Record of Nexus 

Update the Route53 DNS record to point to the public IP address instead of the private IP.

**Change:**
- **From:** Private IP `20.20.0.10`
- **To:** Public IP `13.200.51.3`

This ensures that download of new Docker images from Nexus is routed correctly during the update process (vpn is down).

(Why this works: By updating the DNS record to the public IP, we ensure that any requests for Docker images are sent to the correct location, even when the VPN is not available. and nexus has access from nginx server (13.200.51.3) without vpn)

**Steps:**
1. Log in to AWS Console
2. Navigate to Route53
3. Select the private hosted zone
4. Update the A record for the nexus server
5. Change the IP from `20.20.0.10` to `13.200.51.3`
6. Save the changes and wait for DNS propagation (typically 60 seconds with low TTL)

### Step 3: Update OpenVPN Server

Now you can safely update the OpenVPN server and pull new Docker images.

Go to the OpenVPN server directory (/home/ubuntu/docker/ovpn):

```bash
# Pull the latest images from Nexus (or your registry)
docker-compose -f docker-compose.yml pull

# Stop the current containers
docker-compose -f docker-compose.yml down

# Start the updated containers
docker-compose -f docker-compose.yml up -d

# Verify the containers are running
docker ps

# Check logs for any errors
docker logs <container-id> -f 
```

**Alternative update methods:**
- Pull specific image versions from Nexus
- Update individual services
- Apply configuration changes

### Step 4: Revert Route53 Private DNS Record of Nexus

After the update is complete and verified, revert the Route53 record back to the private IP.

**Change:**
- **From:** Public IP `13.200.51.3`
- **To:** Private IP `20.20.0.10`

**Steps:**
1. Log in to AWS Console
2. Navigate to Route53
3. Select the private hosted zone
4. Update the A record for the Nexus server
5. Change the IP from `13.200.51.3` back to `20.20.0.10`
6. Save the changes

### Step 5: Verification

Verify that the update was successful:

```bash
# Check container status
docker-compose ps

# Verify OpenVPN service is running
# Test VPN connectivity
# (Connect with a test client)

# Monitor for any issues
docker-compose logs <container-id-of-openvpn> -f
```

## Update Complete! ✅

The OpenVPN server update process is now complete.

## Troubleshooting

If issues occur during the update:

1. **Check container logs:**
   ```bash
   docker-compose logs <container-id-of-openvpn>
   ```

2. **Verify DNS propagation:**
   ```bash
   nslookup jenkins.spreezy.in
   ```

3. **Rollback if necessary:**
   ```bash
   docker-compose -f docker-compose.yml down
   # Restore previous docker-compose.yml if needed
   docker-compose -f docker-compose-backup.yml up -d
   ```

4. **Check network connectivity:**
   ```bash
   docker network ls
   docker network inspect <network-name>
   ```
5. **Packet routing issues:**
   ```bash
   traceroute jenkins.spreezy.in
   ```

## Rollback Steps
If the update fails, follow these steps to rollback:
1. Stop the updated containers:
   ```bash
   docker-compose -f docker-compose.yml down
   ```
2. Restore the previous `docker-compose.yml` configuration if you have a backup.
3. Start the previous version of the containers:
   ```bash
   docker-compose -f docker-compose-backup.yml up -d
   ```
4. Revert the Route53 DNS record back to the private IP if it was changed.

## OVPN Admin Access

Access to the OVPN Admin interface is secured at two levels:

### 1. EC2 Security Group Level

At the EC2 instance level, configure the security group to allow access only from the Nginx server:

- **Custom IP Access:** `13.200.51.3` (Nginx IP only)
- **Port:** `8080` (OVPN Admin page port)

This ensures that the OVPN Admin interface is only accessible through the Nginx reverse proxy.

### 2. Nginx Access Control Level

At the Nginx level, configure IP-based access control for the server `ovpn.spreezy.in`.

**Configuration File:** `/home/ubuntu/docker/nginx-ovpn/config/conf.d/ovpn-admin-access.conf`

Add the following entries in the `ovpn-admin-access.conf` file located in the `conf.d` folder:

```nginx
allow 103.105.111.78;      # admin
allow 106.192.113.163;     # testing for DevOps Team (change as per your IP)
deny all;
```

**Steps to update Nginx access control:**

1. Edit the access control file:
   ```bash
   nano /home/ubuntu/docker/nginx-ovpn/config/conf.d/ovpn-admin-access.conf
   ```

2. Add or update the allowed IP addresses as shown above

3. Restart Nginx to apply changes:
   ```bash
   docker-compose -f /home/ubuntu/docker/nginx-ovpn/nginx-docker-compose.yml restart
   ```
**Note:** Remember to update the allowed IPs whenever team members' IP addresses change or when granting access to new administrators.

## Important Notes

- Always backup your configuration before updates
- Test the update in a staging environment if possible
- Monitor the service closely after updates
- Keep a log of all changes made during the update
- Ensure you have a rollback plan

---

**Last Updated:** Nov 2, 2025
