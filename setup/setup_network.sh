#!/bin/bash
# Network configuration for RockTimer
# Run on Pi 4 to set up a WiFi Access Point

set -e

echo "==================================="
echo "RockTimer Network Configuration"
echo "==================================="

# Ensure root
if [ "$EUID" -ne 0 ]; then
    echo "Run as root (sudo)"
    exit 1
fi

# Variables
SSID="RockTimer"
PASSWORD="curling123"
IP_ADDRESS="192.168.50.1"

echo "[1/4] Installing hostapd and dnsmasq..."
apt-get update
apt-get install -y hostapd dnsmasq

echo "[2/4] Stopping services..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "[3/4] Configuring dhcpcd..."
cat >> /etc/dhcpcd.conf << EOF

# RockTimer Access Point
interface wlan0
    static ip_address=${IP_ADDRESS}/24
    nohook wpa_supplicant
EOF

echo "[4/4] Configuring hostapd..."
cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASSWORD}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Enable hostapd
sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

echo "Configuring dnsmasq (DHCP + DNS)..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
cat > /etc/dnsmasq.conf << EOF
interface=wlan0
domain-needed
bogus-priv
expand-hosts

# DHCP range for RockTimer network
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h

# Make the hostname 'rocktimer' resolve to the Pi 4 (this server)
address=/rocktimer/${IP_ADDRESS}

# Optional: also support rocktimer.local
address=/rocktimer.local/${IP_ADDRESS}

# Provide a search domain so some clients can type http://rocktimer
dhcp-option=option:domain-name,rocktimer
dhcp-option=option:domain-search,rocktimer
EOF

echo "Enabling services..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

echo ""
echo "==================================="
echo "Configuration complete!"
echo "==================================="
echo ""
echo "WiFi SSID: ${SSID}"
echo "Password: ${PASSWORD}"
echo "Server IP: ${IP_ADDRESS}"
echo ""
echo "Reboot to apply:"
echo "  sudo reboot"
echo ""

