# RockTimer - Curling Tidtagningssystem

Distribuerat tidtagningssystem för curling med Raspberry Pi.

## Översikt

```
   TEE LINE              HOG LINE (nära)         HOG LINE (avlägsen)
      │                        │                        │
   [Sensor]                [Sensor]                 [Sensor]
   Pi Zero  ──UDP:5000──►   Pi 4   ◄──UDP:5000──  Pi Zero
                              │
                         Webb-UI :8080
```

Sensorerna skickar triggers till servern. Servern ignorerar dem om systemet inte är armat.

## Installation

### Pi 4 (Server)
```bash
sudo ./install_server.sh
```

### Pi Zero 2 W (Sensorer)
```bash
sudo ./install_sensor.sh
# Välj: tee eller hog_far
```

## Konfiguration

Sensorerna behöver bara veta serverns IP:

```yaml
# configs/config-zero-tee.yaml
device_id: "tee"
server:
  host: "192.168.50.1"
  port: 5000
```

## Hårdvara

### Tidtagningssensor (alla Pi:er)
```
LM393 Ljussensor  →  Raspberry Pi
─────────────────────────────────
VCC               →  3.3V (pin 1)
GND               →  GND (pin 6)
DO                →  GPIO 17 (pin 11)
```

### Arm-sensor (endast Pi 4)
```
IR Sensor  →  Raspberry Pi 4
────────────────────────────
VCC        →  3.3V (pin 17)
GND        →  GND (pin 14)
DO         →  GPIO 27 (pin 13)
```
Håll handen framför IR-sensorn för att arma systemet.

## Test

```bash
# Simulera stenpassage
python tools/simulate_triggers.py --simulate

# Enskild trigger
python tools/simulate_triggers.py --device tee
```

## API

| Endpoint | Metod | Beskrivning |
|----------|-------|-------------|
| `/api/arm` | POST | Arma systemet |
| `/api/disarm` | POST | Avbryt |
| `/api/status` | GET | Status |
| `/api/times` | GET | Historik |
