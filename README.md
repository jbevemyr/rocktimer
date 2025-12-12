# RockTimer - Curling Timing System

Distributed curling timing system using Raspberry Pi.

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

# Test:
espeak-ng -v en "Test one two three"
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
