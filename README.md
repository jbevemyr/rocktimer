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

### Ljud - Förstärkare och högtalare (Pi 4)

Systemet läser upp tider med espeak-ng. Använd en liten förstärkarmodul (t.ex. HW-104/PAM8403) 
och en 3W högtalare för inbyggnad.

**Komponenter:**
- HW-104 eller PAM8403 förstärkarmodul
- B103 potentiometer (10kΩ) för volymkontroll
- 3W högtalare (4-8Ω, ~40mm)
- 3.5mm audiokabel

**Koppling med volymkontroll:**
```
Pi 4                          B103 Potentiometer
────                          ──────────────────
3.5mm TIP (ljud) ──────────►  Ben 1 (ingång)
3.5mm SLEEVE (GND) ────────►  Ben 3 (GND)
                              Ben 2 (utgång) ───┐
                                                │
                              HW-104 Förstärkare│
                              ──────────────────┘
Pi 5V (pin 2) ─────────────►  VCC
Pi GND (pin 6) ────────────►  GND
Potentiometer ben 2 ───────►  L-IN
Potentiometer ben 3 ───────►  GND (gemensam)
                              L+ ──────────────► Högtalare +
                              L- ──────────────► Högtalare -
```

**Kopplingsschema:**
```
┌─────────┐      ┌──────────────┐      ┌────────┐      ┌──────────┐
│  Pi 4   │      │ Potentiometer│      │ HW-104 │      │ Högtalare│
│         │      │    B103      │      │        │      │   3W     │
│  3.5mm ─┼──1───┤►            │      │        │      │          │
│   jack  │      │      2──────┼──────┤► L-IN  │      │          │
│    GND ─┼──────┤► 3          │      │        │      │          │
│         │      └──────────────┘      │   L+ ──┼──────┤► +       │
│   5V ───┼────────────────────────────┤► VCC   │      │          │
│   GND ──┼────────────────────────────┤► GND   │      │          │
│         │                            │   L- ──┼──────┤► -       │
└─────────┘                            └────────┘      └──────────┘
```

**Aktivera analog ljudutgång:**
```bash
sudo raspi-config
# System Options → Audio → Headphones

# Eller direkt:
amixer cset numid=3 1

# Testa:
espeak-ng -v sv "Test ett två tre"
```

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
