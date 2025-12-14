# RockTimer - Curling Timing System

RockTimer is a DIY curling stone timing system that measures split times between the **tee line**, the **near hog line**, and the **far hog line** using simple laser trip sensors.

It is designed for a **3‑Pi setup**:
- **Pi 4 (server at near hog line)**: runs the central server + touchscreen UI + optional voice announcements
- **2× Pi Zero 2 W (tee + far hog)**: read sensors and send trigger timestamps over UDP

The goal is to provide a fast, touch-friendly display (and optional voice callouts) for practice and training—without needing external internet or cloud services.

**Credit:** Inspired by Larry Ehnert’s LarryRockTimer (`LarryRockTimer.com`).

## Overview

```
   TEE LINE              HOG LINE (near)         HOG LINE (far)
      │                        │                        │
   [Sensor]                [Sensor]                 [Sensor]
   Pi Zero  ──UDP:5000──►   Pi 4   ◄──UDP:5000──  Pi Zero
                              │
                         Web UI :8080
```

Sensors send triggers to the server. The server ignores them unless the system is armed.

## Network (Pi 4 as Wi‑Fi Access Point)

RockTimer is designed to run on a **local Wi‑Fi network** created by the Pi 4:

- **Pi 4**: runs the server + acts as a **Wi‑Fi Access Point** (AP), typically `192.168.50.1`
- **Pi Zero 2 W** units: connect to the Pi 4 Wi‑Fi and send UDP triggers to the server

This repo includes a helper script to configure the AP on the Pi 4:

```bash
sudo ./setup/setup_network.sh
```

After running it:
- Connect your **Pi Zero 2 W** devices to the SSID shown by the script (default `rocktimer`)
- Verify they get an IP in the `192.168.50.x` range
- Ensure the server IP in the sensor config is set to the Pi 4 address (e.g. `192.168.50.1`)

### Viewing times from a phone

If you have a phone/tablet, you can join the RockTimer Wi‑Fi network and open:

- `http://192.168.50.1` (or `http://192.168.50.1:8080`)

This lets you view live times from your phone and press **Rearm** without using the touchscreen.

### No touchscreen required

The touchscreen is optional. You can build RockTimer without a display and rely on:

- A **phone/tablet** connected to the RockTimer Wi‑Fi network
- An **Apple Watch** companion (future / external app integration)
- Any **laptop/desktop** on the same Wi‑Fi network using a web browser

### Local hostname: http://rocktimer

If you use the provided Wi‑Fi AP setup, dnsmasq can be configured to resolve:

- `rocktimer` → `192.168.50.1`

So you can type `http://rocktimer` in your browser.

Note: RockTimer itself runs on **port 8080** by default. If you want plain port **80**,
use the optional Nginx reverse proxy setup:

```bash
sudo ./setup/setup_nginx_proxy.sh
```

## Boot splash screen (optional)

If you want a simple boot splash during OS startup that shows:

- **RockTimer**
- **jb@bevemyr.com**

…you can enable a custom Plymouth theme:

```bash
sudo ./setup/setup_splash.sh
```

You can also override the text:

```bash
sudo ./setup/setup_splash.sh "RockTimer" "jb@bevemyr.com"
```

This uses Plymouth and generates a simple image-based splash (curling stone + text). If you use a different display resolution than the Pi 7" touchscreen, re-run the script after switching displays so it can regenerate the image at the detected resolution.

### Apple Watch (future)

The idea is to extend the Apple Watch app **“Curling Timer”** so it can display RockTimer times (and optionally arm/rearm).
The repository also contains a simple Apple Watch companion app under `apple-watch/` that can be used as a starting point.

## Time sync (Chrony)

Accurate timing requires the clocks on all devices to be synchronized.
Use **chrony** with the Pi 4 as the local time server.

### 1) Install chrony

On all Pi’s:

```bash
sudo apt-get update
sudo apt-get install -y chrony
```

### 2) Pi 4 (server) configuration

Edit `/etc/chrony/chrony.conf` on the Pi 4 and add something like:

```conf
# Allow LAN clients (RockTimer Wi‑Fi network)
allow 192.168.50.0/24

# Optional: keep stable even without internet
local stratum 10
```

Restart:

```bash
sudo systemctl restart chrony
```

### 3) Pi Zero 2 W (clients) configuration

Edit `/etc/chrony/chrony.conf` on each Pi Zero and add:

```conf
# Use the Pi 4 as the time source
server 192.168.50.1 iburst prefer
```

Restart:

```bash
sudo systemctl restart chrony
```

### 4) Verify sync

On clients:

```bash
chronyc tracking
chronyc sources -v
```

You should see the Pi 4 (`192.168.50.1`) as the preferred source and a small offset.

### Example config files

Copy-ready examples are available in:
- `setup/chrony-server.conf`
- `setup/chrony-client.conf`

## Installation

### Pi 4 (Server)
```bash
sudo ./install_server.sh
```

### Pi Zero 2 W (Sensors)
```bash
sudo ./install_sensor.sh
# Choose: tee or hog_far
```

## Configuration

Sensors only need to know the server IP:

```yaml
# configs/config-zero-tee.yaml
device_id: "tee"
server:
  host: "192.168.50.1"
  port: 5000
```

## Hardware

## Hardware (Bill of Materials)

If you want to build your own RockTimer setup, this is the hardware used in this project.

### Compute + Display
- **1× Raspberry Pi 4 Model B** (central server at the near hog line)
- **2× Raspberry Pi Zero 2 W** (remote sensors: tee line + far hog line)
- **1× Touch display**: Elecrow **RC050** 5-inch HDMI capacitive touch LCD (800×480)

### Sensors (3 trigger points)
- **3× Light sensor modules** (LM393-style “laser trip” sensors), one per line:
  - Tee line (Pi Zero 2 W)
  - Near hog line (Pi 4)
  - Far hog line (Pi Zero 2 W)
- **1× IR proximity sensor module** (used on the Pi 4 as an “arm” trigger)

### Lasers (one per trigger point)
- **3× Red dot laser heads** (3–5V, 650nm, 5mW, 6mm diameter)  
- **3× Battery holders with switch** (one per laser), e.g.:
  - “3 AA Battery Holder with Cover and Switch” (4.5V)

### Power
- **3× Power banks** (one per Raspberry Pi)
  - Pick capacity based on expected runtime; a Pi 4 typically needs a larger bank than a Zero 2 W.

### Audio (for voice announcements)
- **1× Small amplifier module** (e.g. PAM8403 / HW-104)
- **1× Speaker** (recommended: **3W**, **4–8Ω**, small form factor ~40mm)
- **1× Potentiometer for volume**: **B103 (10kΩ)** (thumbwheel or trimmer)
- **1× 3.5mm audio cable** (Pi 4 headphone jack → amplifier input)

### Wiring / mounting (recommended)
- Jumper wires / Dupont cables, screw terminals, heat-shrink, etc.
- Mounting hardware for sensors + lasers (brackets/holders) to keep alignment stable.

### Timing sensor (all Pi's)
```
LM393 Light sensor  →  Raspberry Pi
─────────────────────────────────
VCC               →  3.3V (pin 1)
GND               →  GND (pin 6)
DO                →  GPIO 17 (pin 11)
```

### Arm sensor (Pi 4 only)
```
IR Sensor  →  Raspberry Pi 4
────────────────────────────
VCC        →  3.3V (pin 17)
GND        →  GND (pin 14)
DO         →  GPIO 27 (pin 13)
```
Hold your hand in front of the IR sensor to arm the system.

### Audio - Amplifier and speaker (Pi 4)

The system can announce times using text-to-speech. Use a small amplifier module (e.g. HW-104/PAM8403)
and a 3W speaker for an enclosure build.

RockTimer uses **Piper (Coqui TTS)** for speech. The server calls `/opt/piper/speak.sh`, which pipes Piper audio to `/usr/bin/aplay`.

**Parts:**
- HW-104 or PAM8403 amplifier module
- B103 potentiometer (10kΩ) for volume control
- 3W speaker (4-8Ω, ~40mm)
- 3.5mm audio cable

**Wiring with volume control:**
```
Pi 4                          B103 Potentiometer
────                          ──────────────────
3.5mm TIP (audio) ─────────►  Pin 1 (input)
3.5mm SLEEVE (GND) ────────►  Ben 3 (GND)
                              Pin 2 (output) ───┐
                                                │
                              HW-104 Amplifier  │
                              ──────────────────┘
Pi 5V (pin 2) ─────────────►  VCC
Pi GND (pin 6) ────────────►  GND
Potentiometer pin 2 ───────►  L-IN
Potentiometer pin 3 ───────►  GND (common)
                              L+ ──────────────► Speaker +
                              L- ──────────────► Speaker -
```

**Diagram:**
```
┌─────────┐      ┌──────────────┐      ┌────────┐      ┌──────────┐
│  Pi 4   │      │ Potentiometer│      │ HW-104 │      │ Speaker  │
│         │      │    B103      │      │        │      │   3W     │
│  3.5mm ─┼──1───┤►             │      │        │      │          │
│   jack  │      │       2──────┼──────┤► L-IN  │      │          │
│    GND ─┼──────┤► 3           │      │        │      │          │
│         │      └──────────────┘      │   L+ ──┼──────┤► +       │
│   5V ───┼────────────────────────────┤► VCC   │      │          │
│   GND ──┼────────────────────────────┤► GND   │      │          │
│         │                            │   L- ──┼──────┤► -       │
└─────────┘                            └────────┘      └──────────┘
```

**Enable analog audio output:**
```bash
sudo raspi-config
# System Options → Audio → Headphones

# Or directly:
amixer cset numid=3 1

# Test Piper (Coqui TTS via piper binary):
echo "ready to go" | /opt/piper/piper --model /opt/piper/voices/en_US-lessac-medium.onnx --output-raw | /usr/bin/aplay -r 22050 -f S16_LE -c 1 -D plughw:2,0

# Or test via the helper script used by the server:
/opt/piper/speak.sh "ready to go"
```

## Test

```bash
# Simulate a stone pass
python tools/simulate_triggers.py --simulate

# Single trigger
python tools/simulate_triggers.py --device tee
```

## API

### POST /api/arm
Arm the system.
```json
{"success": true, "state": "armed"}
```

### POST /api/disarm
Cancel the current measurement.
```json
{"success": true, "state": "idle"}
```

### GET /api/status
Get current status.
```json
{
  "state": "completed",
  "session": {
    "tee_time_ns": 1702312345678901234,
    "hog_close_time_ns": 1702312348778901234,
    "hog_far_time_ns": 1702312359078901234,
    "tee_to_hog_close_ms": 3100.0,
    "hog_to_hog_ms": 10300.0,
    "total_ms": 13400.0,
    "has_hog_close": true,
    "has_hog_far": true,
    "started_at": "2024-12-11T18:52:25.678901"
  },
  "sensors": {}
}
```

### GET /api/times
Get history (latest measurements).
```json
[
  {
    "id": 1,
    "timestamp": "2024-12-11T18:52:25.678901",
    "tee_to_hog_close_ms": 3100.0,
    "hog_to_hog_ms": 10300.0,
    "total_ms": 13400.0
  }
]
```

### GET /api/current
Get current measurement (same as session in status).
```json
{
  "tee_to_hog_close_ms": 3100.0,
  "hog_to_hog_ms": null,
  "total_ms": null,
  "has_hog_close": true,
  "has_hog_far": false
}
```

### WebSocket /ws
Real-time updates. Connect and receive `state_update` messages:
```json
{"type": "state_update", "data": {"state": "armed", "session": {...}}}
```

Send commands:
```json
{"type": "arm"}
{"type": "disarm"}
```
