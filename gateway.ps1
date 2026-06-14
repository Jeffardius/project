#!/bin/bash
# Lab 4 Gateway Setup Script (Ubuntu)
# Requirements: Internal 192.168.99.0/29, DHCP .2 for Relay, Strict Firewall, NAT

set -e

echo "========================================================="
echo "  Lab 4: Gateway VM Configuration"
echo "========================================================="

# 1. Install Dependencies
echo "[INFO] Checking dependencies..."
if ! dpkg -l | grep -q openssh-server; then
    sudo apt update && sudo apt install -y openssh-server
fi
if ! dpkg -l | grep -q kea-dhcp4; then
    sudo apt update && sudo apt install -y kea-dhcp4
fi

# 2. Configure Netplan
# enp0s3 = NAT/Bridged (Auto IP), enp0s8 = Internal (Static .1)
cat > /etc/netplan/99_config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      addresses:
        - 192.168.99.1/29
EOF
sudo netplan apply
echo "[SUCCESS] Netplan applied."

# 3. Configure Kea DHCP (Internal Subnet)
cat > /etc/kea/kea-dhcp4.conf << 'EOF'
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": [ "enp0s8" ] },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv"
    },
    "valid-lifetime": 3600,
    "subnet4": [
      {
        "id": 1,
        "subnet": "192.168.99.0/29",
        "pools": [ { "pool": "192.168.99.2 - 192.168.99.2" } ],
        "option-data": [
          { "name": "routers", "data": "192.168.99.1" },
          { "name": "domain-name-servers", "data": "1.1.1.1" }
        ]
      }
    ]
  }
}
EOF
sudo -u _kea kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
sudo rm -f /var/lib/kea/kea-leases4.csv
sudo systemctl restart kea-dhcp4-server
sudo systemctl enable kea-dhcp4-server
echo "[SUCCESS] Kea DHCP configured for 192.168.99.0/29 -> .2"

# 4. Enable IP Forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p
echo "[SUCCESS] IP Forwarding enabled."

# 5. Get Host IP for Firewall
read -p "Enter your Host OS (Physical PC) IP address: " HOST_IP

# 6. Configure Strict Firewall (Nftables)
sudo nft flush ruleset
sudo nft add table ip filter
sudo nft add chain ip filter INPUT '{ type filter hook input priority 0; policy drop; }'
sudo nft add chain ip filter FORWARD '{ type filter hook forward priority 0; policy accept; }'
sudo nft add chain ip filter OUTPUT '{ type filter hook output priority 0; policy accept; }'
sudo nft add rule ip filter INPUT iifname "lo" accept
sudo nft add rule ip filter INPUT ct state established,related accept
sudo nft add rule ip filter INPUT iifname "enp0s3" ip saddr "$HOST_IP" tcp dport 22 accept

# NAT Masquerade for Internet (Lab 3 continuity)
sudo nft add table ip nat
sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }'
sudo nft add rule ip nat POSTROUTING oifname "enp0s3" counter masquerade

# 7. Save Rules & Create Boot Hook
sudo nft list ruleset > /etc/nftables.ruleset
sudo mkdir -p /etc/networkd-dispatcher/routable.d
printf '#!/bin/sh\n/usr/sbin/nft --file /etc/nftables.ruleset\nexit 0\n' | sudo tee /etc/networkd-dispatcher/routable.d/50-ifup.hooks > /dev/null
sudo chmod +x /etc/networkd-dispatcher/routable.d/50-ifup.hooks
echo "[SUCCESS] Strict firewall saved and made persistent."

# 8. Install Persistent Switches (fwon / fwoff)
mkdir -p /usr/local/bin
cat > /usr/local/bin/fwon << 'EOF'
#!/bin/bash
sudo nft -f /etc/nftables.ruleset
echo "Firewall is now ON and persistent."
EOF
cat > /usr/local/bin/fwoff << 'EOF'
#!/bin/bash
sudo nft flush ruleset
sudo rm -f /etc/nftables.ruleset
echo "Firewall is now OFF permanently. Reboot will keep it OFF until fwon is run."
EOF
chmod +x /usr/local/bin/fwon /usr/local/bin/fwoff
echo "[SUCCESS] fwon and fwoff commands installed globally."

echo "========================================================="
echo "  GATEWAY SETUP COMPLETE"
echo "  Run 'ssh ubuntu@<Gateway-Bridged-IP>' from your Host"
echo "========================================================="
