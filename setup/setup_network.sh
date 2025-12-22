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
SSID="${ROCKTIMER_SSID:-rocktimer}"
PASSWORD="${ROCKTIMER_PASSWORD:-rocktimer}"
IP_ADDRESS="${ROCKTIMER_IP_ADDRESS:-192.168.50.1}"
SUBNET_CIDR="${ROCKTIMER_SUBNET_CIDR:-192.168.50.0/24}"
AP_INTERFACE="${ROCKTIMER_AP_INTERFACE:-wlan0}"
CH_DHCPCD_BEGIN="# RockTimer AP begin"
CH_DHCPCD_END="# RockTimer AP end"

echo "[1/4] Installing hostapd and dnsmasq..."
apt-get update
apt-get install -y hostapd dnsmasq

echo "[2/4] Stopping services..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "[3/4] Configuring dhcpcd..."
tmp="$(mktemp)"
awk -v b="${CH_DHCPCD_BEGIN}" -v e="${CH_DHCPCD_END}" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' /etc/dhcpcd.conf > "${tmp}"
cat "${tmp}" > /etc/dhcpcd.conf
rm -f "${tmp}"

cat >> /etc/dhcpcd.conf << EOF

${CH_DHCPCD_BEGIN}
# RockTimer Access Point
interface ${AP_INTERFACE}
    static ip_address=${IP_ADDRESS}/24
    nohook wpa_supplicant
${CH_DHCPCD_END}
EOF

echo "[4/4] Configuring hostapd..."
cat > /etc/hostapd/hostapd.conf << EOF
interface=${AP_INTERFACE}
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
rsn_pairwise=CCMP
EOF

# Enable hostapd
sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

echo "Configuring dnsmasq (DHCP + DNS)..."
cp -n /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
cat > /etc/dnsmasq.conf << EOF
interface=${AP_INTERFACE}
domain-needed
bogus-priv
expand-hosts

# DHCP range for RockTimer network
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h

# Make the hostname 'rocktimer' resolve to the Pi 4 (this server)
address=/rocktimer/${IP_ADDRESS}

# Optional: also support rocktimer.local
address=/rocktimer.local/${IP_ADDRESS}

# Help phones accept this Wi-Fi even without internet by answering common
# captive-portal / connectivity check domains locally.
# (They will resolve to the Pi 4, and nginx on port 80 can respond.)
address=/connectivitycheck.gstatic.com/${IP_ADDRESS}
address=/clients3.google.com/${IP_ADDRESS}
address=/connectivitycheck.android.com/${IP_ADDRESS}
address=/captive.apple.com/${IP_ADDRESS}
address=/www.msftconnecttest.com/${IP_ADDRESS}
address=/msftconnecttest.com/${IP_ADDRESS}
address=/www.msftncsi.com/${IP_ADDRESS}
address=/msftncsi.com/${IP_ADDRESS}

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

