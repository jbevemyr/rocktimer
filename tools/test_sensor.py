#!/usr/bin/env python3
"""
Testverktyg för ljussensorn.
Kör på Pi för att verifiera att sensorn fungerar.
"""

import time
import sys

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("RPi.GPIO krävs. Installera med: pip install RPi.GPIO")
    sys.exit(1)

SENSOR_PIN = 17

def sensor_callback(channel):
    """Callback när sensorn triggas."""
    timestamp = time.time_ns()
    print(f"TRIGGER! Tid: {timestamp} ns ({time.strftime('%H:%M:%S')})")

def main():
    print("=================================")
    print("RockTimer Sensortest")
    print("=================================")
    print(f"Övervakar GPIO pin {SENSOR_PIN}")
    print("Bryt ljusstrålen för att testa")
    print("Tryck Ctrl+C för att avsluta")
    print()
    
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SENSOR_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    # Visa aktuellt tillstånd
    current = GPIO.input(SENSOR_PIN)
    print(f"Aktuellt tillstånd: {'HIGH (ljus)' if current else 'LOW (blockerad)'}")
    print()
    
    GPIO.add_event_detect(
        SENSOR_PIN,
        GPIO.FALLING,
        callback=sensor_callback,
        bouncetime=50
    )
    
    try:
        while True:
            # Visa tillstånd kontinuerligt
            state = GPIO.input(SENSOR_PIN)
            status = "■ LJUS" if state else "□ BLOCKERAD"
            print(f"\rSensor: {status}  ", end="", flush=True)
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n\nAvslutar...")
    finally:
        GPIO.cleanup()

if __name__ == '__main__':
    main()

