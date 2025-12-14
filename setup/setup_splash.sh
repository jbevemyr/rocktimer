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

echo "[1/5] Installing Plymouth..."
apt-get update
apt-get install -y plymouth plymouth-themes

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

# Write the script (we substitute TITLE/SUBTITLE below, so do not quote EOF)
cat > "${THEME_DIR}/rocktimer.script" <<EOF
# RockTimer Plymouth script theme

title = "${TITLE}";
subtitle = "${SUBTITLE}";

Plymouth.SetBackgroundTopColor(0.0, 0.0, 0.0);
Plymouth.SetBackgroundBottomColor(0.0, 0.0, 0.0);

title_sprite = Sprite();
title_sprite.SetImage(Image.Text(title, 1.0, 1.0, 1.0));

subtitle_sprite = Sprite();
subtitle_sprite.SetImage(Image.Text(subtitle, 0.75, 0.75, 0.75));

sw = Window.GetWidth();
sh = Window.GetHeight();

title_x = (sw - title_sprite.GetWidth()) / 2;
title_y = (sh / 2) - title_sprite.GetHeight();

subtitle_x = (sw - subtitle_sprite.GetWidth()) / 2;
subtitle_y = title_y + title_sprite.GetHeight() + 10;

title_sprite.SetX(title_x);
title_sprite.SetY(title_y);

subtitle_sprite.SetX(subtitle_x);
subtitle_sprite.SetY(subtitle_y);

# Optional: if Plymouth status changes, you could update text here.
fun status_callback(status) {
  # no-op
}

Plymouth.SetUpdateStatusFunction(status_callback);
EOF

chmod 0644 "${THEME_DIR}/rocktimer.plymouth" "${THEME_DIR}/rocktimer.script"

echo "[3/5] Enabling 'splash' in kernel cmdline (if missing)..."
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

echo "[4/5] Setting default Plymouth theme to 'rocktimer'..."
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

echo "[5/5] Done."
echo ""
echo "Reboot to see the splash screen:"
echo "  sudo reboot"


