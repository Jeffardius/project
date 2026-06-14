#!/bin/bash
# Lab 3/4 Relay Setup Script (Ubuntu)
# Requirements: Internal DHCP client, Bridged 192.168.99.80/28, DHCP .82 for Node, Forwarding

set -e

echo "========================================================="
echo "  Lab 3/4: Relay VM Configuration"
echo "========================================================="

# 1. Install Dependencies
echo "[INFO] Checking dependencies..."
if ! dpkg -l | grep -q kea-dhcp4; then
    sudo apt update && sudo apt install -y kea-dhcp4
fi

# 2. Configure Netplan
# enp0s3 = Internal (DHCP from Gateway), enp0s8 = Bridged (Static .81)
cat > /etc/netplan/99_config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp4-overrides:
        use-routes: true
    enp0s8:
      addresses:
        - 192.168.99.81/28
EOF
sudo netplan apply
echo "[SUCCESS] Netplan applied."

# 3. Configure Kea DHCP (Bridged Subnet for Node)
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
        "id": 2,
        "subnet": "192.168.99.80/28",
        "pools": [ { "pool": "192.168.99.82 - 192.168.99.82" } ],
        "option-data": [
          { "name": "routers", "data": "192.168.99.81" },
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
echo "[SUCCESS] Kea DHCP configured for 192.168.99.80/28 -> .82"

# 4. Enable IP Forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# 5. Configure Permissive Nftables for Routing
sudo nft flush ruleset
sudo nft add table ip filter
sudo nft add chain ip filter INPUT '{ type filter hook input priority 0; policy accept; }'
sudo nft add chain ip filter FORWARD '{ type filter hook forward priority 0; policy accept; }'
sudo nft add chain ip filter OUTPUT '{ type filter hook output priority 0; policy accept; }'
sudo nft add rule ip filter INPUT iifname "lo" accept
sudo nft add rule ip filter INPUT ct state established,related accept

# NAT Masquerade toward Gateway (enp0s3)
sudo nft add table ip nat
sudo nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }'
sudo nft add rule ip nat POSTROUTING oifname "enp0s3" counter masquerade

# 6. Save Rules & Create Boot Hook
sudo nft list ruleset > /etc/nftables.ruleset
sudo mkdir -p /etc/networkd-dispatcher/routable.d
printf '#!/bin/sh\n/usr/sbin/nft --file /etc/nftables.ruleset\nexit 0\n' | sudo tee /etc/networkd-dispatcher/routable.d/50-ifup.hooks > /dev/null
sudo chmod +x /etc/networkd-dispatcher/routable.d/50-ifup.hooks
echo "[SUCCESS] Relay routing and firewall rules saved and persistent."

echo "========================================================="
echo "  RELAY SETUP COMPLETE"
echo "  Node VM (Laptop) should now receive 192.168.99.82"
echo "========================================================="
