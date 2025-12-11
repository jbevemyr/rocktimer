#!/bin/bash
# Nätverkskonfiguration för RockTimer
# Körs på Pi 4 för att sätta upp WiFi Access Point

set -e

echo "==================================="
echo "RockTimer Nätverkskonfiguration"
echo "==================================="

# Kontrollera root
if [ "$EUID" -ne 0 ]; then
    echo "Kör som root (sudo)"
    exit 1
fi

# Variabler
SSID="RockTimer"
PASSWORD="curling123"
IP_ADDRESS="192.168.50.1"

echo "[1/4] Installerar hostapd och dnsmasq..."
apt-get update
apt-get install -y hostapd dnsmasq

echo "[2/4] Stoppar tjänster..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true

echo "[3/4] Konfigurerar dhcpcd..."
cat >> /etc/dhcpcd.conf << EOF

# RockTimer Access Point
interface wlan0
    static ip_address=${IP_ADDRESS}/24
    nohook wpa_supplicant
EOF

echo "[4/4] Konfigurerar hostapd..."
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

# Aktivera hostapd
sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

echo "Konfigurerar dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
cat > /etc/dnsmasq.conf << EOF
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h
domain=rocktimer.local
address=/rocktimer.local/${IP_ADDRESS}
EOF

echo "Aktiverar tjänster..."
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

echo ""
echo "==================================="
echo "Konfiguration klar!"
echo "==================================="
echo ""
echo "WiFi SSID: ${SSID}"
echo "Lösenord: ${PASSWORD}"
echo "Server IP: ${IP_ADDRESS}"
echo ""
echo "Starta om för att aktivera:"
echo "  sudo reboot"
echo ""

