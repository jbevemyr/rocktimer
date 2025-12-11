#!/usr/bin/env python3
"""
RockTimer Sensor Daemon
Körs på Pi Zero 2 W vid tee-linjen och avlägsna hog-linjen.
Övervakar ljussensorn och skickar tidsstämplar via UDP.
"""

import socket
import time
import json
import yaml
import logging
import signal
import sys
from pathlib import Path

# Försök importera gpiozero
try:
    from gpiozero import Button
    from gpiozero.pins.lgpio import LGPIOFactory
    from gpiozero import Device
    Device.pin_factory = LGPIOFactory()
    GPIO_AVAILABLE = True
except ImportError:
    GPIO_AVAILABLE = False
    print("WARNING: gpiozero not available, running in simulation mode")

# Konfigurationsväg
CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('rocktimer-sensor')


class SensorDaemon:
    """Huvudklass för sensordaemon."""
    
    def __init__(self, config_path: Path = CONFIG_PATH):
        self.config = self._load_config(config_path)
        self.device_id = self.config['device_id']
        self.running = True
        self.sensor_button = None
        
        # UDP socket
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.server_address = (
            self.config['server']['host'],
            self.config['server']['port']
        )
        
        logger.info(f"Sensor: {self.device_id}")
        logger.info(f"Server: {self.server_address}")
        
    def _load_config(self, config_path: Path) -> dict:
        """Ladda konfiguration från YAML-fil."""
        if not config_path.exists():
            raise FileNotFoundError(f"Konfigurationsfil saknas: {config_path}")
        
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def _setup_gpio(self):
        """Konfigurera GPIO för ljussensorn."""
        if not GPIO_AVAILABLE:
            logger.warning("GPIO ej tillgängligt - simuleringsläge")
            return
        
        try:
            pin = self.config['gpio']['sensor_pin']
            debounce_s = self.config['gpio']['debounce_ms'] / 1000.0
            
            self.sensor_button = Button(
                pin,
                pull_up=True,
                bounce_time=debounce_s
            )
            self.sensor_button.when_pressed = self._sensor_triggered
            
            logger.info(f"GPIO {pin} konfigurerad med debounce {debounce_s*1000:.0f}ms")
            
        except Exception as e:
            logger.error(f"GPIO-fel: {e}")
            logger.warning("Fortsätter utan GPIO")
    
    def _sensor_triggered(self):
        """Callback när sensorn triggas (ljusstrålen bryts)."""
        # Ta tidsstämpel direkt
        trigger_time = time.time_ns()
        
        logger.info(f"TRIGGER! {self.device_id}")
        
        # Skicka via UDP - servern avgör om den bryr sig
        payload = {
            'type': 'trigger',
            'device_id': self.device_id,
            'timestamp_ns': trigger_time
        }
        
        try:
            data = json.dumps(payload).encode('utf-8')
            self.udp_socket.sendto(data, self.server_address)
        except Exception as e:
            logger.error(f"Kunde inte skicka UDP: {e}")
    
    def _signal_handler(self, signum, frame):
        """Hantera shutdown-signaler."""
        logger.info("Avslutar...")
        self.running = False
        self.udp_socket.close()
        # gpiozero hanterar cleanup automatiskt
        sys.exit(0)
    
    def run(self):
        """Starta sensor daemon."""
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        self._setup_gpio()
        
        logger.info("Sensor daemon startad - skickar triggers till servern")
        
        # Håll processen igång
        while self.running:
            time.sleep(1)


def main():
    daemon = SensorDaemon()
    daemon.run()


if __name__ == '__main__':
    main()
