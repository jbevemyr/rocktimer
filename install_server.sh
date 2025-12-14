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
    alsa-utils \
    chromium \
    unclutter \
    wget \
    tar

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

echo "[4b/5] Installing Piper TTS..."
PIPER_DIR="/opt/piper"
PIPER_VOICE_DIR="${PIPER_DIR}/voices"
PIPER_BIN="${PIPER_DIR}/piper"
PIPER_MODEL="${PIPER_VOICE_DIR}/en_US-lessac-medium.onnx"

mkdir -p "${PIPER_VOICE_DIR}"

# Download piper binary (arm64)
if [ ! -x "${PIPER_BIN}" ]; then
    tmpdir="$(mktemp -d)"
    wget -q -O "${tmpdir}/piper_arm64.tar.gz" "https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_arm64.tar.gz"
    tar -xzf "${tmpdir}/piper_arm64.tar.gz" -C "${PIPER_DIR}"
    rm -rf "${tmpdir}"
fi

# Download voice model
if [ ! -f "${PIPER_MODEL}" ]; then
    wget -q -O "${PIPER_MODEL}" "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
    wget -q -O "${PIPER_MODEL}.json" "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
fi

# Install the helper script the server uses
cat > "${PIPER_DIR}/speak.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Simple, robust Piper TTS helper:
# - Generates raw audio once
# - Prefers the Pi analog jack if present (bcm2835 Headphones)
# - Tries a few ALSA output devices until one works
# - Logs errors to /var/log/rocktimer-tts.log

TEXT="${*:-}"
if [ -z "${TEXT}" ]; then
  exit 0
fi

PIPER="/opt/piper/piper"
MODEL="/opt/piper/voices/en_US-lessac-medium.onnx"
APLAY="/usr/bin/aplay"
LOG="/var/log/rocktimer-tts.log"

RATE="22050"
FMT="S16_LE"
CH="1"

log() { echo "$(date -Is) $*" >> "${LOG}"; }

if [ ! -x "${PIPER}" ]; then
  log "ERROR: piper not found at ${PIPER}"
  exit 1
fi
if [ ! -f "${MODEL}" ]; then
  log "ERROR: model not found at ${MODEL}"
  exit 1
fi
if [ ! -x "${APLAY}" ]; then
  log "ERROR: aplay not found at ${APLAY}"
  exit 1
fi

tmp="$(mktemp /tmp/rocktimer-tts.XXXXXX.raw)"
trap 'rm -f "$tmp"' EXIT

if ! echo "${TEXT}" | "${PIPER}" --model "${MODEL}" --output-raw > "${tmp}" 2>> "${LOG}"; then
  log "ERROR: piper failed"
  exit 1
fi

# If ALSA_DEVICE is set, try it first.
devices=()
if [ -n "${ALSA_DEVICE:-}" ]; then
  devices+=("${ALSA_DEVICE}")
fi

# Prefer analog jack if present (bcm2835 Headphones)
hp_card="$("${APLAY}" -l 2>/dev/null | awk -F'[: ]+' '/card [0-9]+:.*Headphones/ {print $2; exit}')"
if [ -n "${hp_card}" ]; then
  devices+=("hw:${hp_card},0" "plughw:${hp_card},0")
fi

# Common fallbacks (card numbering can change across reboots)
devices+=(
  # Prefer named devices that often route via dmix (non-exclusive)
  "default:CARD=Headphones"
  "sysdefault:CARD=Headphones"
  "dmix:CARD=Headphones,DEV=0"
  "default"
  # Numeric fallbacks (can be exclusive)
  "hw:0,0" "plughw:0,0"
  "hw:1,0" "plughw:1,0"
  "hw:2,0" "plughw:2,0"
)

for dev in "${devices[@]}"; do
  log "Trying device: ${dev}"
  if "${APLAY}" -q -D "${dev}" -r "${RATE}" -f "${FMT}" -c "${CH}" "${tmp}" 2>> "${LOG}"; then
    log "OK device: ${dev}"
    exit 0
  fi
done

log "ERROR: no working ALSA device (tried: ${devices[*]})"
exit 1
EOF
chmod +x "${PIPER_DIR}/speak.sh"

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
