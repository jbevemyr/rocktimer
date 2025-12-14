#!/bin/bash
# Boot splash screen setup for RockTimer (Plymouth)
# Run on the Pi 4 (or any Debian-based system using Plymouth).
#
# This installs Plymouth, creates a simple RockTimer theme, enables "splash"
# on the kernel cmdline, and sets the default Plymouth theme.

set -euo pipefail

TITLE_DEFAULT="RockTimer"
SUBTITLE_DEFAULT="jb@bevemyr.com"

TITLE="${1:-$TITLE_DEFAULT}"
SUBTITLE="${2:-$SUBTITLE_DEFAULT}"

echo "==================================="
echo "RockTimer Boot Splash (Plymouth)"
echo "==================================="

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root (sudo)"
  exit 1
fi

echo "[1/5] Installing Plymouth (and SVG renderer)..."
apt-get update
apt-get install -y plymouth plymouth-themes librsvg2-bin

THEME_DIR="/usr/share/plymouth/themes/rocktimer"
mkdir -p "${THEME_DIR}"

echo "[2/5] Writing RockTimer Plymouth theme..."
cat > "${THEME_DIR}/rocktimer.plymouth" <<'EOF'
[Plymouth Theme]
Name=RockTimer
Description=RockTimer boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/rocktimer
ScriptFile=/usr/share/plymouth/themes/rocktimer/rocktimer.script
EOF

echo "[3/5] Generating splash image (curling stone + text)..."

# Try to detect the current framebuffer resolution. Default is the Pi 7" touchscreen (800x480).
SPLASH_W=800
SPLASH_H=480
if command -v fbset >/dev/null 2>&1; then
  GEOM="$(fbset -s 2>/dev/null | awk '/geometry/ {print $2" "$3; exit}')"
  if [ -n "${GEOM}" ]; then
    SPLASH_W="$(echo "${GEOM}" | awk '{print $1}')"
    SPLASH_H="$(echo "${GEOM}" | awk '{print $2}')"
  fi
fi

# Render everything into one image to avoid text-overlap quirks in Plymouth text rendering.
cat > "${THEME_DIR}/splash.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="${SPLASH_W}" height="${SPLASH_H}" viewBox="0 0 ${SPLASH_W} ${SPLASH_H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0b1220"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
    <radialGradient id="iceGlow" cx="50%" cy="70%" r="60%">
      <stop offset="0%" stop-color="#1f3b66" stop-opacity="0.35"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity="0.55"/>
    </filter>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="0.6"/>
    </filter>
  </defs>

  <!-- Background -->
  <rect x="0" y="0" width="${SPLASH_W}" height="${SPLASH_H}" fill="url(#bg)"/>
  <rect x="0" y="0" width="${SPLASH_W}" height="${SPLASH_H}" fill="url(#iceGlow)"/>

  <!-- Subtle ice lines -->
  <g opacity="0.12">
    <path d="M 0 ${SPLASH_H*0.74} C ${SPLASH_W*0.25} ${SPLASH_H*0.70}, ${SPLASH_W*0.55} ${SPLASH_H*0.80}, ${SPLASH_W} ${SPLASH_H*0.72}" stroke="#b7d6ff" stroke-width="2" fill="none"/>
    <path d="M 0 ${SPLASH_H*0.80} C ${SPLASH_W*0.30} ${SPLASH_H*0.75}, ${SPLASH_W*0.60} ${SPLASH_H*0.88}, ${SPLASH_W} ${SPLASH_H*0.80}" stroke="#b7d6ff" stroke-width="2" fill="none"/>
  </g>

  <!-- Curling stone (simple illustration) -->
  <g filter="url(#shadow)" transform="translate(${SPLASH_W/2}, ${SPLASH_H*0.40})">
    <!-- stone base shadow -->
    <ellipse cx="0" cy="${SPLASH_H*0.18}" rx="${SPLASH_W*0.16}" ry="${SPLASH_H*0.045}" fill="#000" opacity="0.35"/>

    <!-- stone body -->
    <ellipse cx="0" cy="${SPLASH_H*0.10}" rx="${SPLASH_W*0.17}" ry="${SPLASH_H*0.055}" fill="#1a1a1a"/>
    <ellipse cx="0" cy="${SPLASH_H*0.08}" rx="${SPLASH_W*0.15}" ry="${SPLASH_H*0.045}" fill="#2a2a2a"/>

    <!-- running band -->
    <ellipse cx="0" cy="${SPLASH_H*0.12}" rx="${SPLASH_W*0.12}" ry="${SPLASH_H*0.03}" fill="#111"/>
    <ellipse cx="0" cy="${SPLASH_H*0.12}" rx="${SPLASH_W*0.10}" ry="${SPLASH_H*0.024}" fill="#0a0a0a"/>

    <!-- top highlight -->
    <ellipse cx="${-SPLASH_W*0.03}" cy="${SPLASH_H*0.06}" rx="${SPLASH_W*0.06}" ry="${SPLASH_H*0.02}" fill="#ffffff" opacity="0.10" filter="url(#soft)"/>

    <!-- handle -->
    <g transform="translate(0, ${-SPLASH_H*0.01})">
      <rect x="${-SPLASH_W*0.06}" y="${-SPLASH_H*0.11}" width="${SPLASH_W*0.12}" height="${SPLASH_H*0.06}" rx="${SPLASH_H*0.02}" fill="#c8102e"/>
      <rect x="${-SPLASH_W*0.02}" y="${-SPLASH_H*0.16}" width="${SPLASH_W*0.04}" height="${SPLASH_H*0.06}" rx="${SPLASH_H*0.015}" fill="#a20e25"/>
      <ellipse cx="0" cy="${-SPLASH_H*0.16}" rx="${SPLASH_W*0.055}" ry="${SPLASH_H*0.02}" fill="#e21a3b"/>
      <ellipse cx="${-SPLASH_W*0.015}" cy="${-SPLASH_H*0.165}" rx="${SPLASH_W*0.02}" ry="${SPLASH_H*0.012}" fill="#ffffff" opacity="0.18"/>
    </g>
  </g>

  <!-- Text -->
  <g text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif">
    <text x="${SPLASH_W/2}" y="${SPLASH_H*0.70}" font-size="${SPLASH_H*0.12}" fill="#ffffff" font-weight="700">${TITLE}</text>
    <text x="${SPLASH_W/2}" y="${SPLASH_H*0.82}" font-size="${SPLASH_H*0.055}" fill="#c8d7ff" opacity="0.95">${SUBTITLE}</text>
  </g>
</svg>
EOF

if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w "${SPLASH_W}" -h "${SPLASH_H}" "${THEME_DIR}/splash.svg" -o "${THEME_DIR}/splash.png"
else
  echo "WARNING: rsvg-convert not found; splash image will not be generated."
fi

echo "[4/5] Writing Plymouth script (shows splash.png)..."
cat > "${THEME_DIR}/rocktimer.script" <<'EOF'
# RockTimer Plymouth script theme (image-based)

Plymouth.SetBackgroundTopColor(0.0, 0.0, 0.0);
Plymouth.SetBackgroundBottomColor(0.0, 0.0, 0.0);

sw = Window.GetWidth();
sh = Window.GetHeight();

img = Image("splash.png");
sprite = Sprite();
sprite.SetImage(img);

x = (sw - img.GetWidth()) / 2;
y = (sh - img.GetHeight()) / 2;
sprite.SetX(x);
sprite.SetY(y);

fun status_callback(status) {
  # no-op
}

Plymouth.SetUpdateStatusFunction(status_callback);
EOF

chmod 0644 "${THEME_DIR}/rocktimer.plymouth" "${THEME_DIR}/rocktimer.script"

echo "[5/5] Enabling 'splash' in kernel cmdline (if missing)..."
CMDLINE_FILE=""
if [ -f /boot/firmware/cmdline.txt ]; then
  CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
  CMDLINE_FILE="/boot/cmdline.txt"
else
  echo "WARNING: Could not find cmdline.txt in /boot/firmware/ or /boot/"
  echo "         You may need to add 'quiet splash' manually."
fi

if [ -n "${CMDLINE_FILE}" ]; then
  # cmdline.txt must be a single line
  CURRENT="$(cat "${CMDLINE_FILE}")"
  UPDATED="${CURRENT}"

  if ! echo "${CURRENT}" | grep -qE '(^| )quiet( |$)'; then
    UPDATED="${UPDATED} quiet"
  fi
  if ! echo "${CURRENT}" | grep -qE '(^| )splash( |$)'; then
    UPDATED="${UPDATED} splash"
  fi
  if ! echo "${CURRENT}" | grep -qE '(^| )plymouth\.ignore-serial-consoles( |$)'; then
    UPDATED="${UPDATED} plymouth.ignore-serial-consoles"
  fi

  if [ "${UPDATED}" != "${CURRENT}" ]; then
    echo "${UPDATED}" > "${CMDLINE_FILE}"
    echo "Updated: ${CMDLINE_FILE}"
  else
    echo "cmdline already contains splash settings."
  fi
fi

echo "Setting default Plymouth theme to 'rocktimer'..."
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  # -R rebuilds initramfs when applicable
  plymouth-set-default-theme -R rocktimer || true
else
  mkdir -p /etc/plymouth
  cat > /etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=rocktimer
EOF
  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u || true
  fi
fi

echo "Done."
echo ""
echo "Reboot to see the splash screen:"
echo "  sudo reboot"


