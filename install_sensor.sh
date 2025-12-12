#!/bin/bash
# Install RockTimer Sensor on Raspberry Pi Zero 2 W

set -e

echo "==================================="
echo "RockTimer Sensor Installation"
echo "==================================="

# Ensure we run as root
if [ "$EUID" -ne 0 ]; then
    echo "Run this script as root (sudo)"
    exit 1
fi

# Ask for device ID
echo ""
echo "Where is this sensor located?"
echo "  1) tee - At the tee line"
echo "  2) hog_far - At the far hog line"
read -p "Choose (1 or 2): " CHOICE

case $CHOICE in
    1) DEVICE_ID="tee" ;;
    2) DEVICE_ID="hog_far" ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

echo "Configuring as: ${DEVICE_ID}"

# Install path
INSTALL_DIR="/opt/rocktimer"
USER="${SUDO_USER:-$(whoami)}"

echo "Installing for user: ${USER}"

echo "[1/5] Installing system dependencies..."
apt-get update
apt-get install -y \
    python3-pip \
    python3-venv \
    python3-lgpio \
    python3-gpiozero

echo "[2/5] Creating install directory..."
mkdir -p ${INSTALL_DIR}
cp -r . ${INSTALL_DIR}/
chown -R ${USER}:${USER} ${INSTALL_DIR}

echo "[3/5] Creating Python virtual environment..."
cd ${INSTALL_DIR}
python3 -m venv --system-site-packages venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-sensor.txt

echo "[4/5] Copying and configuring..."
if [ ! -f ${INSTALL_DIR}/config.yaml ]; then
    cp ${INSTALL_DIR}/config.yaml.example ${INSTALL_DIR}/config.yaml
fi

# Sätt device_id
sed -i "s/device_id: \"tee\"/device_id: \"${DEVICE_ID}\"/" ${INSTALL_DIR}/config.yaml

echo "[5/5] Installing systemd service..."

cat > /etc/systemd/system/rocktimer-sensor.service << EOF
[Unit]
Description=RockTimer Sensor Daemon
After=network.target

[Service]
Type=simple
User=root
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
echo "Installation complete!"
echo "==================================="
echo ""
echo "Device ID: ${DEVICE_ID}"
echo ""
echo "Start the sensor:"
echo "  sudo systemctl start rocktimer-sensor"
echo ""
echo "Check status:"
echo "  sudo systemctl status rocktimer-sensor"
echo ""
echo "View logs:"
echo "  sudo journalctl -u rocktimer-sensor -f"
echo ""
echo "Edit configuration:"
echo "  nano ${INSTALL_DIR}/config.yaml"
echo ""

