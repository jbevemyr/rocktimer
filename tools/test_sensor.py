#!/usr/bin/env python3
"""
Test utility for the light sensor.
Run on the Pi to verify the sensor works.
"""

import time
import sys

try:
    import RPi.GPIO as GPIO
except ImportError:
    print("RPi.GPIO is required. Install with: pip install RPi.GPIO")
    sys.exit(1)

SENSOR_PIN = 17

def sensor_callback(channel):
    """Callback when the sensor triggers."""
    timestamp = time.time_ns()
    print(f"TRIGGER! Time: {timestamp} ns ({time.strftime('%H:%M:%S')})")

def main():
    print("=================================")
    print("RockTimer Sensor Test")
    print("=================================")
    print(f"Monitoring GPIO pin {SENSOR_PIN}")
    print("Break the beam to test")
    print("Press Ctrl+C to exit")
    print()
    
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SENSOR_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    
    # Show current state
    current = GPIO.input(SENSOR_PIN)
    print(f"Current state: {'HIGH (light)' if current else 'LOW (blocked)'}")
    print()
    
    GPIO.add_event_detect(
        SENSOR_PIN,
        GPIO.FALLING,
        callback=sensor_callback,
        bouncetime=50
    )
    
    try:
        while True:
            # Show state continuously
            state = GPIO.input(SENSOR_PIN)
            status = "■ LIGHT" if state else "□ BLOCKED"
            print(f"\rSensor: {status}  ", end="", flush=True)
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\n\nExiting...")
    finally:
        GPIO.cleanup()

if __name__ == '__main__':
    main()

