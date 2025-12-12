#!/bin/bash
# Install RockTimer Server on Raspberry Pi 4

set -e

echo "==================================="
echo "RockTimer Server Installation"
echo "==================================="

# Ensure we run as root
if [ "$EUID" -ne 0 ]; then
    echo "Run this script as root (sudo)"
    exit 1
fi

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
    python3-gpiozero \
    chromium \
    unclutter \
    espeak-ng

echo "[2/5] Creating install directory..."
mkdir -p ${INSTALL_DIR}
cp -r . ${INSTALL_DIR}/
chown -R ${USER}:${USER} ${INSTALL_DIR}

echo "[3/5] Creating Python virtual environment..."
cd ${INSTALL_DIR}
python3 -m venv --system-site-packages venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-server.txt

echo "[4/5] Copying configuration file..."
if [ ! -f ${INSTALL_DIR}/config.yaml ]; then
    cp ${INSTALL_DIR}/configs/config-pi4-hog-close.yaml ${INSTALL_DIR}/config.yaml
fi

echo "[5/5] Installing systemd services..."

# Server service (runs as root for GPIO access)
cat > /etc/systemd/system/rocktimer-server.service << EOF
[Unit]
Description=RockTimer Central Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/server/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Kiosk mode for touchscreen
cat > /etc/systemd/system/rocktimer-kiosk.service << EOF
[Unit]
Description=RockTimer Kiosk Display
After=graphical.target rocktimer-server.service
Wants=rocktimer-server.service

[Service]
Type=simple
User=${USER}
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/${USER}/.Xauthority
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/chromium --kiosk --noerrdialogs --disable-infobars --no-first-run --start-fullscreen http://localhost:8080
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable rocktimer-server.service

# Disable screen blanking
mkdir -p /home/${USER}/.config/lxsession/LXDE-pi/
cat > /home/${USER}/.config/lxsession/LXDE-pi/autostart << EOF
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xset s off
@xset -dpms
@xset s noblank
@unclutter -idle 0.5 -root
EOF
chown -R ${USER}:${USER} /home/${USER}/.config/

echo ""
echo "==================================="
echo "Installation complete!"
echo "==================================="
echo ""
echo "Start the server:"
echo "  sudo systemctl start rocktimer-server"
echo ""
echo "Start kiosk mode:"
echo "  sudo systemctl enable rocktimer-kiosk"
echo "  sudo systemctl start rocktimer-kiosk"
echo ""
echo "Web UI: http://localhost:8080"
echo ""
echo "Edit configuration:"
echo "  nano ${INSTALL_DIR}/config.yaml"
echo ""
