#!/bin/bash
# Installation av RockTimer Sensor på Raspberry Pi Zero 2 W

set -e

echo "==================================="
echo "RockTimer Sensor Installation"
echo "==================================="

# Kontrollera att vi kör som root
if [ "$EUID" -ne 0 ]; then
    echo "Kör detta skript som root (sudo)"
    exit 1
fi

# Fråga efter enhets-ID
echo ""
echo "Vilken position har denna sensor?"
echo "  1) tee - Vid tee-linjen"
echo "  2) hog_far - Vid avlägsna hog-linjen"
read -p "Välj (1 eller 2): " CHOICE

case $CHOICE in
    1) DEVICE_ID="tee" ;;
    2) DEVICE_ID="hog_far" ;;
    *) echo "Ogiltigt val"; exit 1 ;;
esac

echo "Konfigurerar som: ${DEVICE_ID}"

# Installationsväg
INSTALL_DIR="/opt/rocktimer"
USER="pi"

echo "[1/5] Installerar systemberoenden..."
apt-get update
apt-get install -y \
    python3-pip \
    python3-venv

echo "[2/5] Skapar installationskatalog..."
mkdir -p ${INSTALL_DIR}
cp -r . ${INSTALL_DIR}/
chown -R ${USER}:${USER} ${INSTALL_DIR}

echo "[3/5] Skapar Python virtual environment..."
cd ${INSTALL_DIR}
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-sensor.txt

echo "[4/5] Kopierar och konfigurerar..."
if [ ! -f ${INSTALL_DIR}/config.yaml ]; then
    cp ${INSTALL_DIR}/config.yaml.example ${INSTALL_DIR}/config.yaml
fi

# Sätt device_id
sed -i "s/device_id: \"tee\"/device_id: \"${DEVICE_ID}\"/" ${INSTALL_DIR}/config.yaml

echo "[5/5] Installerar systemd-tjänst..."

cat > /etc/systemd/system/rocktimer-sensor.service << EOF
[Unit]
Description=RockTimer Sensor Daemon
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/sensor/sensor_daemon.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rocktimer-sensor.service

echo ""
echo "==================================="
echo "Installation klar!"
echo "==================================="
echo ""
echo "Enhets-ID: ${DEVICE_ID}"
echo ""
echo "Starta sensorn:"
echo "  sudo systemctl start rocktimer-sensor"
echo ""
echo "Kontrollera status:"
echo "  sudo systemctl status rocktimer-sensor"
echo ""
echo "Visa loggar:"
echo "  sudo journalctl -u rocktimer-sensor -f"
echo ""
echo "Redigera konfigurationen:"
echo "  nano ${INSTALL_DIR}/config.yaml"
echo ""

