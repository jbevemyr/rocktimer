#!/usr/bin/env python3
"""
StoneTimer Sensor Daemon
Runs on Pi Zero 2 W at the tee line and the far hog line.

Supports two sensor types (set sensor_type in config.yaml):
  - "gpio"   (default) — laser trip sensor via LM393 on a GPIO pin
  - "camera" — Pi Camera + OpenCV frame differencing
"""

import socket
import time
import json
import yaml
import logging
import signal
import sys
import threading
from pathlib import Path
from typing import Optional

# Config path
CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('stonetimer-sensor')


class SensorDaemon:
    """Main sensor daemon class for remote timing sensors.

    Runs on Pi Zero 2 W units at the tee line and far hog line.

    Supports two sensor backends:
      - GPIO (laser trip sensor, LM393)
      - Camera (Pi Camera + OpenCV frame differencing)

    Both backends send the same UDP trigger messages to the server.
    """

    def __init__(self, config_path: Path = CONFIG_PATH):
        self.config = self._load_config(config_path)
        self.config_path = config_path
        self.device_id = self.config['device_id']
        self.running = True
        self.sensor_type = self.config.get('sensor_type', 'gpio')
        self._heartbeat_thread: Optional[threading.Thread] = None

        # UDP socket
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.server_address = (
            self.config['server']['host'],
            self.config['server']['port']
        )

        self.heartbeat_interval_s = float(
            self.config.get('server', {}).get('heartbeat_interval_s', 5.0)
        )

        logger.info(f"Sensor: {self.device_id} (type={self.sensor_type})")
        logger.info(f"Server: {self.server_address}")
        logger.info(f"Heartbeat interval: {self.heartbeat_interval_s:.1f}s")

    def _load_config(self, config_path: Path) -> dict:
        if not config_path.exists():
            raise FileNotFoundError(f"Config file missing: {config_path}")
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)

    # ── UDP helpers (shared by both backends) ────────────────────────────

    def send_trigger(self, device_id: str, timestamp_ns: int):
        """Send a trigger event to the server via UDP."""
        payload = {
            'type': 'trigger',
            'device_id': device_id,
            'timestamp_ns': timestamp_ns
        }
        try:
            data = json.dumps(payload).encode('utf-8')
            self.udp_socket.sendto(data, self.server_address)
        except Exception as e:
            logger.error(f"Could not send UDP: {e}")

    def _send_heartbeat(self):
        next_send = 0.0
        while self.running:
            now = time.time()
            if now >= next_send:
                payload = {
                    'type': 'heartbeat',
                    'device_id': self.device_id,
                    'timestamp_ns': time.time_ns()
                }
                try:
                    data = json.dumps(payload).encode('utf-8')
                    self.udp_socket.sendto(data, self.server_address)
                except Exception as e:
                    logger.error(f"Could not send heartbeat UDP: {e}")
                next_send = now + self.heartbeat_interval_s
            time.sleep(0.2)

    # ── GPIO backend ─────────────────────────────────────────────────────

    def _setup_gpio(self):
        try:
            from gpiozero import Button
            from gpiozero.pins.lgpio import LGPIOFactory
            from gpiozero import Device
            Device.pin_factory = LGPIOFactory()
        except ImportError:
            logger.warning("gpiozero not available - running without GPIO")
            return

        try:
            pin = self.config['gpio']['sensor_pin']
            debounce_s = self.config['gpio']['debounce_ms'] / 1000.0
            self._sensor_button = Button(pin, pull_up=True, bounce_time=debounce_s)
            self._sensor_button.when_pressed = self._gpio_triggered
            logger.info(f"GPIO {pin} configured with debounce {debounce_s*1000:.0f}ms")
        except Exception as e:
            logger.error(f"GPIO error: {e}")
            logger.warning("Continuing without GPIO")

    def _gpio_triggered(self):
        trigger_time = time.time_ns()
        logger.info(f"TRIGGER! {self.device_id}")
        self.send_trigger(self.device_id, trigger_time)

    def _run_gpio(self):
        self._setup_gpio()
        logger.info("GPIO sensor daemon started")
        while self.running:
            time.sleep(1)

    # ── Camera backend ───────────────────────────────────────────────────

    def _run_camera(self):
        from sensor.camera_sensor import CameraSensor
        cam = CameraSensor(self.config, self.config_path, self.send_trigger)
        logger.info("Camera sensor daemon started")
        try:
            cam.start()
        finally:
            cam.stop()

    # ── Main entry point ─────────────────────────────────────────────────

    def _signal_handler(self, signum, frame):
        logger.info("Shutting down...")
        self.running = False
        self.udp_socket.close()
        sys.exit(0)

    def run(self):
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        self._heartbeat_thread = threading.Thread(target=self._send_heartbeat, daemon=True)
        self._heartbeat_thread.start()

        logger.info("Sensor daemon started - sending triggers to server")

        if self.sensor_type == 'camera':
            self._run_camera()
        else:
            self._run_gpio()


def main():
    daemon = SensorDaemon()
    daemon.run()


if __name__ == '__main__':
    main()
