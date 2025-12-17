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
    chrony \
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
MKTEMP="/usr/bin/mktemp"
RM="/bin/rm"
DATE="/usr/bin/date"
AWK="/usr/bin/awk"

RATE="22050"
FMT="S16_LE"
CH="1"

log() { echo "$("${DATE}" -Is) $*" >> "${LOG}"; }

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
if [ ! -x "${MKTEMP}" ]; then
  log "ERROR: mktemp not found at ${MKTEMP} (PATH may be restricted under systemd)"
  exit 1
fi
if [ ! -x "${AWK}" ]; then
  log "ERROR: awk not found at ${AWK}"
  exit 1
fi

tmp="$("${MKTEMP}" /tmp/rocktimer-tts.XXXXXX.raw)"
trap '"${RM}" -f "$tmp"' EXIT

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
hp_card="$("${APLAY}" -l 2>/dev/null | "${AWK}" -F'[: ]+' '/card [0-9]+:.*Headphones/ {print $2; exit}')"
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

echo "[4c/5] Optional: configuring time sync (chrony)..."
CHRONY_CONF="/etc/chrony/chrony.conf"
CHRONY_MARKER_BEGIN="# RockTimer chrony begin"
CHRONY_MARKER_END="# RockTimer chrony end"
CHRONY_CIDR_DEFAULT="192.168.50.0/24"
CHRONY_CIDR="${ROCKTIMER_CHRONY_CIDR:-${CHRONY_CIDR_DEFAULT}}"
CONFIGURE_CHRONY="${ROCKTIMER_CONFIGURE_CHRONY:-}"

if [ "${CONFIGURE_CHRONY}" = "1" ]; then
    configure_chrony="y"
elif [ "${CONFIGURE_CHRONY}" = "0" ]; then
    configure_chrony="n"
else
    read -r -p "Configure chrony time sync (recommended)? [Y/n] " configure_chrony
    configure_chrony="${configure_chrony:-y}"
fi

if [[ "${configure_chrony}" =~ ^[Yy]$ ]]; then
    if [ ! -f "${CHRONY_CONF}" ]; then
        echo "WARNING: ${CHRONY_CONF} not found; skipping chrony config"
    else
        CHRONY_MAKESTEP_THRESHOLD_DEFAULT="1.0"
        CHRONY_MAKESTEP_LIMIT_DEFAULT="3"
        CHRONY_MAKESTEP_THRESHOLD="${ROCKTIMER_CHRONY_MAKESTEP_THRESHOLD:-${CHRONY_MAKESTEP_THRESHOLD_DEFAULT}}"
        CHRONY_MAKESTEP_LIMIT="${ROCKTIMER_CHRONY_MAKESTEP_LIMIT:-${CHRONY_MAKESTEP_LIMIT_DEFAULT}}"

        tmp="$(mktemp)"
        # Remove any previous RockTimer chrony block
        awk -v b="${CHRONY_MARKER_BEGIN}" -v e="${CHRONY_MARKER_END}" '
          $0==b {skip=1; next}
          $0==e {skip=0; next}
          !skip {print}
        ' "${CHRONY_CONF}" > "${tmp}"
        cat "${tmp}" > "${CHRONY_CONF}"
        rm -f "${tmp}"

        cat >> "${CHRONY_CONF}" << EOF

${CHRONY_MARKER_BEGIN}
# Allow clients from the RockTimer subnet
allow ${CHRONY_CIDR}
# Optional: act as a local time source even if internet is unavailable
local stratum 10
# Allow stepping the clock at boot if offset is large (helps if devices were powered off for a long time)
makestep ${CHRONY_MAKESTEP_THRESHOLD} ${CHRONY_MAKESTEP_LIMIT}
${CHRONY_MARKER_END}
EOF

        systemctl enable chrony >/dev/null 2>&1 || true
        systemctl restart chrony >/dev/null 2>&1 || systemctl start chrony >/dev/null 2>&1 || true
        echo "Chrony configured (server). Allowed subnet: ${CHRONY_CIDR}"
    fi
else
    echo "Skipping chrony configuration."
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
USER_UID="$(id -u "${USER}")"

# Local loading page (covers the screen immediately, then redirects when the UI is ready)
cat > ${INSTALL_DIR}/kiosk_loading.html << 'EOF'
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>RockTimer</title>
  <style>
    html, body { height: 100%; margin: 0; background: #000; color: #fff; font-family: sans-serif; }
    .wrap { height: 100%; display: flex; align-items: center; justify-content: center; flex-direction: column; gap: 12px; }
    .title { font-size: 40px; font-weight: 700; letter-spacing: 0.5px; }
    .sub { font-size: 18px; opacity: 0.75; }
    .dot { display:inline-block; width:10px; height:10px; border-radius:50%; background:#fff; opacity:.2; animation: pulse 1s infinite; }
    @keyframes pulse { 0%{opacity:.2} 50%{opacity:1} 100%{opacity:.2} }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="title">RockTimer</div>
    <div class="sub">Startar… <span class="dot"></span></div>
  </div>
  <script>
    const TARGET = "http://localhost:8080";
    function tryRedirect() {
      // Detect when the server is reachable.
      // Use fetch(no-cors) from file:// so we do not get stuck on missing assets.
      fetch(TARGET + "/api/status?ts=" + Date.now(), { mode: "no-cors", cache: "no-store" })
        .then(() => window.location.replace(TARGET))
        .catch(() => setTimeout(tryRedirect, 250));
    }
    tryRedirect();
  </script>
</body>
</html>
EOF
chown ${USER}:${USER} ${INSTALL_DIR}/kiosk_loading.html

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
Environment=XDG_RUNTIME_DIR=/run/user/${USER_UID}
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus
Environment=NO_AT_BRIDGE=1

# Wait for X to exist (Wayland session typically starts Xwayland as :0)
ExecStartPre=/bin/sh -c "i=0; while [ \$i -lt 200 ]; do test -S /tmp/.X11-unix/X0 && exit 0; i=\$((i+1)); sleep 0.05; done; exit 1"

# Avoid keyring prompts / password store on kiosk
ExecStart=/usr/bin/chromium --kiosk --noerrdialogs --disable-infobars --no-first-run --start-fullscreen --disable-background-networking --disable-sync --disable-features=TranslateUI --password-store=basic --use-mock-keychain file://${INSTALL_DIR}/kiosk_loading.html
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable rocktimer-server.service

# Disable screen blanking
mkdir -p /home/${USER}/.config/lxsession/LXDE-pi/
cat > /home/${USER}/.config/lxsession/LXDE-pi/autostart << EOF
@xset s off
@xset -dpms
@xset s noblank
@unclutter -idle 0.5 -root
EOF
chown -R ${USER}:${USER} /home/${USER}/.config/

# If running the default Raspberry Pi OS Wayland session (labwc),
# override its autostart so we don't briefly show panel/desktop before Chromium.
mkdir -p /home/${USER}/.config/labwc/
cat > /home/${USER}/.config/labwc/autostart << 'EOF'
# RockTimer kiosk: override Raspberry Pi OS default labwc autostart
# (prevents panel + desktop icons + keyring prompts during boot)
/bin/true
EOF
chown -R ${USER}:${USER} /home/${USER}/.config/labwc/

# Also disable the system default labwc autostart (wf-panel/pcmanfm) to avoid any desktop flash.
if [ -f /etc/xdg/labwc/autostart ]; then
  cp -n /etc/xdg/labwc/autostart /etc/xdg/labwc/autostart.rocktimer.bak || true
  cat > /etc/xdg/labwc/autostart << 'EOF'
# RockTimer kiosk: minimal labwc autostart
# (disables panel + desktop icons to avoid showing a desktop before the kiosk)
/usr/bin/kanshi &
EOF
fi

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
