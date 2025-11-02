# Client-Side Setup
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
![screeshot2.jpg](/screeshot2.jpg)
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
```