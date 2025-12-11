#!/usr/bin/env python3
"""
RockTimer Central Server
Körs på Pi 4 vid närmaste hog-linjen.
Samlar in tidsstämplar, beräknar tider och serverar webb-UI.
"""

import asyncio
import socket
import json
import time
import os
import yaml
import logging
import threading
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager
from enum import Enum
from dataclasses import dataclass

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, FileResponse
import uvicorn

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
logger = logging.getLogger('rocktimer-server')


class SystemState(str, Enum):
    IDLE = "idle"
    ARMED = "armed"
    MEASURING = "measuring"
    COMPLETED = "completed"


@dataclass
class TimingRecord:
    id: int
    timestamp: datetime
    tee_to_hog_close_ms: float
    hog_to_hog_ms: Optional[float]  # None om stenen inte nådde hog_far
    total_ms: Optional[float]


class TimingSession:
    """Håller reda på en mätsession."""
    
    def __init__(self):
        self.reset()
    
    def reset(self):
        self.tee_time_ns: Optional[int] = None
        self.hog_close_time_ns: Optional[int] = None
        self.hog_far_time_ns: Optional[int] = None
        self.started_at: Optional[datetime] = None
    
    @property
    def tee_to_hog_close_ms(self) -> Optional[float]:
        if self.tee_time_ns and self.hog_close_time_ns:
            return (self.hog_close_time_ns - self.tee_time_ns) / 1_000_000
        return None
    
    @property
    def hog_to_hog_ms(self) -> Optional[float]:
        if self.hog_close_time_ns and self.hog_far_time_ns:
            return (self.hog_far_time_ns - self.hog_close_time_ns) / 1_000_000
        return None
    
    @property
    def total_ms(self) -> Optional[float]:
        if self.tee_time_ns and self.hog_far_time_ns:
            return (self.hog_far_time_ns - self.tee_time_ns) / 1_000_000
        return None
    
    @property
    def has_hog_close(self) -> bool:
        """True om stenen passerat första hog-linjen."""
        return self.tee_time_ns is not None and self.hog_close_time_ns is not None
    
    @property
    def has_hog_far(self) -> bool:
        """True om stenen passerat andra hog-linjen."""
        return self.hog_far_time_ns is not None
    
    def to_dict(self) -> dict:
        return {
            'tee_time_ns': self.tee_time_ns,
            'hog_close_time_ns': self.hog_close_time_ns,
            'hog_far_time_ns': self.hog_far_time_ns,
            'tee_to_hog_close_ms': self.tee_to_hog_close_ms,
            'hog_to_hog_ms': self.hog_to_hog_ms,
            'total_ms': self.total_ms,
            'has_hog_close': self.has_hog_close,
            'has_hog_far': self.has_hog_far,
            'started_at': self.started_at.isoformat() if self.started_at else None
        }


class RockTimerServer:
    """Huvudklass för RockTimer-servern."""
    
    def __init__(self, config_path: Path = CONFIG_PATH):
        self.config = self._load_config(config_path)
        self.state = SystemState.IDLE
        self.session = TimingSession()
        self.websocket_clients: list[WebSocket] = []
        self._loop = None  # Sätts när servern startar
        
        # In-memory historik
        self.history: list[TimingRecord] = []
        self._next_id = 1
        
        # UDP socket för att ta emot triggers
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp_socket.bind(('0.0.0.0', self.config['server']['udp_port']))
        
        self._udp_thread = None
        self._running = False
        
        logger.info(f"RockTimer Server - UDP port {self.config['server']['udp_port']}")
    
    def _load_config(self, config_path: Path) -> dict:
        if not config_path.exists():
            raise FileNotFoundError(f"Konfigurationsfil saknas: {config_path}")
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def setup_gpio(self):
        """Konfigurera GPIO för sensorer."""
        if not GPIO_AVAILABLE:
            logger.warning("GPIO ej tillgängligt - kör utan lokal sensor")
            return
        
        try:
            # Hog close sensor (tidtagning)
            sensor_pin = self.config['gpio']['sensor_pin']
            debounce_s = self.config['gpio']['debounce_ms'] / 1000.0
            
            self.sensor_button = Button(
                sensor_pin, 
                pull_up=True, 
                bounce_time=debounce_s
            )
            self.sensor_button.when_pressed = self._local_sensor_triggered
            logger.info(f"Tidtagningssensor på GPIO {sensor_pin}")
            
            # Arm-sensor (IR-sensor för att arma systemet)
            arm_pin = self.config['gpio'].get('arm_pin')
            if arm_pin:
                self.arm_button = Button(
                    arm_pin, 
                    pull_up=True, 
                    bounce_time=0.5
                )
                self.arm_button.when_pressed = self._arm_sensor_triggered
                logger.info(f"Arm-sensor (IR) på GPIO {arm_pin}")
                
        except Exception as e:
            logger.error(f"GPIO-fel: {e}")
            logger.warning("Fortsätter utan lokal GPIO - använd endast nätverkssensorer")
    
    def _local_sensor_triggered(self):
        """Callback för lokal sensor (hog_close)."""
        trigger_time = time.time_ns()
        self._handle_trigger('hog_close', trigger_time)
    
    def _arm_sensor_triggered(self):
        """Callback för arm-sensor (IR)."""
        logger.info("Arm-sensor triggad!")
        self.arm()
    
    def start_udp_listener(self):
        """Starta UDP-lyssnare i egen tråd."""
        self._running = True
        self._udp_thread = threading.Thread(target=self._udp_listener_loop, daemon=True)
        self._udp_thread.start()
        logger.info("UDP-lyssnare startad")
    
    def stop_udp_listener(self):
        self._running = False
        self.udp_socket.close()
    
    def _udp_listener_loop(self):
        """Lyssna på UDP-meddelanden."""
        while self._running:
            try:
                data, addr = self.udp_socket.recvfrom(1024)
                payload = json.loads(data.decode('utf-8'))
                
                if payload.get('type') == 'trigger':
                    device_id = payload.get('device_id')
                    timestamp_ns = payload.get('timestamp_ns')
                    
                    if device_id and timestamp_ns:
                        self._handle_trigger(device_id, timestamp_ns)
                        
            except OSError:
                break
            except json.JSONDecodeError as e:
                logger.error(f"Ogiltigt JSON: {e}")
    
    def _handle_trigger(self, device_id: str, timestamp_ns: int):
        """Hantera trigger från sensor."""
        logger.info(f"Trigger: {device_id}")
        
        # hog_far kan komma efter COMPLETED - uppdatera senaste mätning
        if device_id == 'hog_far' and self.state == SystemState.COMPLETED:
            if not self.session.hog_far_time_ns:
                self.session.hog_far_time_ns = timestamp_ns
                self._update_last_record()
                self.broadcast_state()
            return
        
        # Annars ignorera om vi inte är redo att mäta
        if self.state not in [SystemState.ARMED, SystemState.MEASURING]:
            logger.debug(f"Ignorerar trigger från {device_id} - ej armat")
            return
        
        # Första triggern startar mätningen
        if self.state == SystemState.ARMED:
            self.state = SystemState.MEASURING
            self.session.started_at = datetime.now()
        
        # Registrera tidpunkt (endast första för varje sensor, i rätt ordning)
        if device_id == 'tee' and not self.session.tee_time_ns:
            self.session.tee_time_ns = timestamp_ns
            
        elif device_id == 'hog_close' and not self.session.hog_close_time_ns:
            # Ignorera om hog_close kommer före tee (felaktig ordning)
            if self.session.tee_time_ns and timestamp_ns > self.session.tee_time_ns:
                self.session.hog_close_time_ns = timestamp_ns
                # Mätningen är "klar" efter hog_close - spara direkt
                self._complete_measurement()
            else:
                logger.debug(f"Ignorerar hog_close - kom före tee")
            
        elif device_id == 'hog_far' and not self.session.hog_far_time_ns:
            # Ignorera om hog_far kommer före hog_close (felaktig ordning)
            if self.session.hog_close_time_ns and timestamp_ns > self.session.hog_close_time_ns:
                self.session.hog_far_time_ns = timestamp_ns
                self._update_last_record()
            else:
                logger.debug(f"Ignorerar hog_far - kom före hog_close")
        
        self.broadcast_state()
    
    def _complete_measurement(self):
        """Slutför mätning efter hog_close."""
        self.state = SystemState.COMPLETED
        
        record = TimingRecord(
            id=self._next_id,
            timestamp=self.session.started_at,
            tee_to_hog_close_ms=self.session.tee_to_hog_close_ms,
            hog_to_hog_ms=None,  # Fylls i om stenen når hog_far
            total_ms=None
        )
        self._next_id += 1
        self.history.insert(0, record)
        
        if len(self.history) > 100:
            self.history = self.history[:100]
        
        logger.info(f"Klar: TEE→HOG={self.session.tee_to_hog_close_ms:.1f}ms")
        
        # Läs upp tiden
        self._speak_time(self.session.tee_to_hog_close_ms)
    
    def _update_last_record(self):
        """Uppdatera senaste mätning med hog_far-tid."""
        if self.history:
            self.history[0].hog_to_hog_ms = self.session.hog_to_hog_ms
            self.history[0].total_ms = self.session.total_ms
            hog_hog = self.session.hog_to_hog_ms
            total = self.session.total_ms
            if hog_hog and total:
                logger.info(f"Uppdaterad: HOG→HOG={hog_hog:.1f}ms, Total={total:.1f}ms")
    
    def _speak_time(self, time_ms: float):
        """Läs upp tiden med text-to-speech."""
        if not self.config['server'].get('enable_speech', False):
            logger.debug("Speech är avstängt i config")
            return
            
        if time_ms is None or time_ms <= 0:
            return
            
        try:
            # Konvertera till sekunder
            seconds = time_ms / 1000.0
            
            # Formatera för uppläsning (t.ex. "3 point 1 0")
            whole = int(seconds)
            decimals = int((seconds - whole) * 100)
            text = f"{whole} point {decimals // 10} {decimals % 10}"
            
            logger.info(f"Speaking: '{text}'")
            
            # Försök Piper-script först, sedan espeak-ng
            speak_script = '/opt/piper/speak.sh'
            
            if os.path.exists(speak_script):
                subprocess.Popen(
                    [speak_script, text],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True
                )
            else:
                # Fallback till espeak-ng
                subprocess.Popen(
                    ['/usr/bin/espeak-ng', '-v', 'en', '-s', '150', text],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env={'ALSA_CARD': '2', 'HOME': '/root'}
                )
        except FileNotFoundError:
            logger.warning("TTS ej installerat")
        except Exception as e:
            logger.error(f"TTS-fel: {e}")
    
    def arm(self):
        """Arma systemet."""
        if self.state not in [SystemState.IDLE, SystemState.COMPLETED]:
            return False
        
        self.session.reset()
        self.state = SystemState.ARMED
        logger.info("ARMAT")
        self.broadcast_state()
        return True
    
    def disarm(self):
        """Avaktivera."""
        self.state = SystemState.IDLE
        self.session.reset()
        logger.info("AVARMAT")
        self.broadcast_state()
        return True
    
    def get_history(self, limit: int = 50) -> list[dict]:
        return [
            {
                'id': r.id,
                'timestamp': r.timestamp.isoformat(),
                'tee_to_hog_close_ms': r.tee_to_hog_close_ms,
                'hog_to_hog_ms': r.hog_to_hog_ms,
                'total_ms': r.total_ms
            }
            for r in self.history[:limit]
        ]
    
    def delete_record(self, record_id: int) -> bool:
        for i, r in enumerate(self.history):
            if r.id == record_id:
                self.history.pop(i)
                return True
        return False
    
    def clear_history(self):
        self.history.clear()
        self._next_id = 1
    
    def get_state(self) -> dict:
        return {
            'state': self.state.value,
            'session': self.session.to_dict(),
            'sensors': {}
        }
    
    def broadcast_state(self):
        """Skicka state till alla klienter (thread-safe)."""
        if self._loop and self._loop.is_running():
            asyncio.run_coroutine_threadsafe(self._broadcast_state(), self._loop)
    
    async def _broadcast_state(self):
        state = self.get_state()
        message = json.dumps({'type': 'state_update', 'data': state})
        
        for ws in self.websocket_clients:
            try:
                await ws.send_text(message)
            except Exception:
                pass


# Global server-instans
server = RockTimerServer()


@asynccontextmanager
async def lifespan(app: FastAPI):
    server._loop = asyncio.get_running_loop()
    server.setup_gpio()
    server.start_udp_listener()
    yield
    server.stop_udp_listener()
    # gpiozero hanterar cleanup automatiskt


app = FastAPI(title="RockTimer", version="1.0.0", lifespan=lifespan)


@app.post("/api/arm")
async def arm_system():
    success = server.arm()
    return {"success": success, "state": server.state.value}


@app.post("/api/disarm")
async def disarm_system():
    success = server.disarm()
    return {"success": success, "state": server.state.value}


@app.get("/api/status")
async def get_status():
    return server.get_state()


@app.get("/api/current")
async def get_current():
    return server.session.to_dict()


@app.get("/api/times")
async def get_times(limit: int = 50):
    return server.get_history(limit)


@app.post("/api/clear")
async def clear_times():
    server.clear_history()
    return {"success": True}


@app.delete("/api/times/{record_id}")
async def delete_time(record_id: int):
    return {"success": server.delete_record(record_id)}


@app.delete("/api/times")
async def clear_times():
    server.clear_history()
    return {"success": True}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    server.websocket_clients.append(websocket)
    
    try:
        await websocket.send_text(json.dumps({'type': 'state_update', 'data': server.get_state()}))
        
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get('type') == 'arm':
                server.arm()
            elif message.get('type') == 'disarm':
                server.disarm()
                
    except WebSocketDisconnect:
        server.websocket_clients.remove(websocket)


static_path = Path(__file__).parent / "static"
if static_path.exists():
    app.mount("/static", StaticFiles(directory=static_path), name="static")


@app.get("/", response_class=HTMLResponse)
async def root():
    index_path = static_path / "index.html"
    if index_path.exists():
        return FileResponse(index_path)
    return HTMLResponse("<h1>RockTimer</h1>")


def main():
    uvicorn.run(
        app,
        host=server.config['server']['host'],
        port=server.config['server']['http_port'],
        log_level="info"
    )


if __name__ == '__main__':
    main()
