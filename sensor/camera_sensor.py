#!/usr/bin/env python3
"""
StoneTimer Camera Sensor

Alternative to the laser+photodiode GPIO sensor. Uses a Pi Camera and OpenCV
frame differencing to detect when a curling stone crosses a line.

Also exposes a small HTTP server for remote calibration:
  GET  /stream       — MJPEG live view (ROI overlay)
  GET  /stream?diff=1 — MJPEG with frame-diff visualization
  GET  /config       — current camera config (JSON)
  POST /config       — update ROI / threshold / cooldown (saves to config.yaml)
"""

import time
import json
import logging
import threading
import struct
import yaml
from io import BytesIO
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, Tuple

import cv2
import numpy as np

logger = logging.getLogger('stonetimer-sensor.camera')

# Try picamera2 first (native Pi Camera), fall back to OpenCV VideoCapture
try:
    from picamera2 import Picamera2
    PICAMERA2_AVAILABLE = True
except ImportError:
    PICAMERA2_AVAILABLE = False
    logger.info("picamera2 not available, will use OpenCV VideoCapture")


class CameraSensor:
    """Detects a curling stone crossing a line using frame differencing."""

    def __init__(self, config: dict, config_path: Path, trigger_callback):
        """
        Args:
            config: full parsed config.yaml dict
            config_path: path to config.yaml (for saving calibration changes)
            trigger_callback: called with (device_id, timestamp_ns) on detection
        """
        self.config = config
        self.config_path = config_path
        self.device_id = config['device_id']
        self.trigger_callback = trigger_callback
        self.running = False

        cam_cfg = config.get('camera', {})
        self.resolution: Tuple[int, int] = tuple(cam_cfg.get('resolution', [320, 240]))
        self.fps: int = cam_cfg.get('fps', 60)
        self.roi: list = list(cam_cfg.get('roi', [0, 0, self.resolution[0], self.resolution[1]]))
        self.threshold: int = cam_cfg.get('threshold', 30)
        self.min_pixel_count: int = cam_cfg.get('min_pixel_count', 500)
        self.cooldown_ms: int = cam_cfg.get('cooldown_ms', 2000)
        self.http_port: int = cam_cfg.get('http_port', 8081)

        self._camera = None
        self._prev_gray: Optional[np.ndarray] = None
        self._last_trigger_ns: int = 0
        self._lock = threading.Lock()

        # Shared frames for HTTP streaming
        self._latest_frame: Optional[bytes] = None
        self._latest_diff_frame: Optional[bytes] = None
        self._frame_event = threading.Event()

    def start(self):
        """Start capture loop and HTTP server."""
        self.running = True
        self._init_camera()
        self._start_http_server()
        self._capture_loop()

    def stop(self):
        self.running = False
        if self._camera is not None:
            if PICAMERA2_AVAILABLE and isinstance(self._camera, Picamera2):
                self._camera.stop()
            else:
                self._camera.release()

    def _init_camera(self):
        w, h = self.resolution
        if PICAMERA2_AVAILABLE:
            self._camera = Picamera2()
            cam_config = self._camera.create_video_configuration(
                main={"size": (w, h), "format": "RGB888"},
                controls={"FrameRate": self.fps}
            )
            self._camera.configure(cam_config)
            self._camera.start()
            logger.info(f"picamera2 started: {w}x{h} @ {self.fps}fps")
        else:
            self._camera = cv2.VideoCapture(0)
            self._camera.set(cv2.CAP_PROP_FRAME_WIDTH, w)
            self._camera.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
            self._camera.set(cv2.CAP_PROP_FPS, self.fps)
            if not self._camera.isOpened():
                raise RuntimeError("Could not open camera via OpenCV VideoCapture")
            logger.info(f"OpenCV VideoCapture started: {w}x{h} @ {self.fps}fps")

    def _grab_frame(self) -> Optional[np.ndarray]:
        if PICAMERA2_AVAILABLE and isinstance(self._camera, Picamera2):
            frame = self._camera.capture_array()
            return frame
        else:
            ret, frame = self._camera.read()
            return frame if ret else None

    def _capture_loop(self):
        """Main loop: grab frames, detect motion in ROI, fire trigger."""
        logger.info("Capture loop started")
        while self.running:
            frame = self._grab_frame()
            if frame is None:
                time.sleep(0.01)
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if len(frame.shape) == 3 else frame

            triggered = False
            diff_vis = None

            if self._prev_gray is not None:
                diff = cv2.absdiff(gray, self._prev_gray)
                _, thresh = cv2.threshold(diff, self.threshold, 255, cv2.THRESH_BINARY)

                rx, ry, rw, rh = self.roi
                rx = max(0, min(rx, gray.shape[1] - 1))
                ry = max(0, min(ry, gray.shape[0] - 1))
                rw = max(1, min(rw, gray.shape[1] - rx))
                rh = max(1, min(rh, gray.shape[0] - ry))

                roi_mask = thresh[ry:ry+rh, rx:rx+rw]
                pixel_count = cv2.countNonZero(roi_mask)

                now_ns = time.time_ns()
                cooldown_ns = self.cooldown_ms * 1_000_000
                if pixel_count >= self.min_pixel_count and (now_ns - self._last_trigger_ns) > cooldown_ns:
                    triggered = True
                    self._last_trigger_ns = now_ns
                    logger.info(f"TRIGGER! {self.device_id} (pixels={pixel_count})")
                    self.trigger_callback(self.device_id, now_ns)

                diff_vis = cv2.cvtColor(thresh, cv2.COLOR_GRAY2BGR)
                cv2.rectangle(diff_vis, (rx, ry), (rx+rw, ry+rh), (0, 255, 0), 2)

            self._prev_gray = gray

            # Build annotated frame for streaming
            annotated = frame.copy() if len(frame.shape) == 3 else cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
            rx, ry, rw, rh = self.roi
            color = (0, 0, 255) if triggered else (0, 255, 0)
            cv2.rectangle(annotated, (rx, ry), (rx+rw, ry+rh), color, 2)

            with self._lock:
                _, buf = cv2.imencode('.jpg', annotated, [cv2.IMWRITE_JPEG_QUALITY, 70])
                self._latest_frame = buf.tobytes()
                if diff_vis is not None:
                    _, dbuf = cv2.imencode('.jpg', diff_vis, [cv2.IMWRITE_JPEG_QUALITY, 70])
                    self._latest_diff_frame = dbuf.tobytes()
                self._frame_event.set()

    # ── HTTP server for calibration ──────────────────────────────────────

    def _start_http_server(self):
        sensor = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                pass  # suppress default access logs

            def do_GET(self):
                if self.path.startswith('/stream'):
                    self._handle_stream()
                elif self.path == '/config':
                    self._handle_get_config()
                else:
                    self.send_error(404)

            def do_POST(self):
                if self.path == '/config':
                    self._handle_post_config()
                else:
                    self.send_error(404)

            def _handle_stream(self):
                use_diff = 'diff=1' in self.path
                self.send_response(200)
                self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=--frame')
                self.send_header('Cache-Control', 'no-cache')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                try:
                    while sensor.running:
                        sensor._frame_event.wait(timeout=1.0)
                        sensor._frame_event.clear()
                        with sensor._lock:
                            data = sensor._latest_diff_frame if use_diff else sensor._latest_frame
                        if data is None:
                            continue
                        try:
                            self.wfile.write(b'--frame\r\n')
                            self.wfile.write(b'Content-Type: image/jpeg\r\n')
                            self.wfile.write(f'Content-Length: {len(data)}\r\n'.encode())
                            self.wfile.write(b'\r\n')
                            self.wfile.write(data)
                            self.wfile.write(b'\r\n')
                            self.wfile.flush()
                        except BrokenPipeError:
                            break
                except Exception:
                    pass

            def _handle_get_config(self):
                payload = {
                    'device_id': sensor.device_id,
                    'resolution': list(sensor.resolution),
                    'fps': sensor.fps,
                    'roi': sensor.roi,
                    'threshold': sensor.threshold,
                    'min_pixel_count': sensor.min_pixel_count,
                    'cooldown_ms': sensor.cooldown_ms,
                }
                body = json.dumps(payload).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _handle_post_config(self):
                length = int(self.headers.get('Content-Length', 0))
                raw = self.rfile.read(length)
                try:
                    data = json.loads(raw)
                except (json.JSONDecodeError, ValueError):
                    self.send_error(400, 'Invalid JSON')
                    return

                if 'roi' in data and isinstance(data['roi'], list) and len(data['roi']) == 4:
                    sensor.roi = [int(v) for v in data['roi']]
                if 'threshold' in data:
                    sensor.threshold = int(data['threshold'])
                if 'min_pixel_count' in data:
                    sensor.min_pixel_count = int(data['min_pixel_count'])
                if 'cooldown_ms' in data:
                    sensor.cooldown_ms = int(data['cooldown_ms'])

                sensor._save_camera_config()

                body = b'{"success": true}'
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_OPTIONS(self):
                self.send_response(204)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', 'Content-Type')
                self.end_headers()

        server = HTTPServer(('0.0.0.0', self.http_port), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        logger.info(f"Calibration HTTP server on port {self.http_port}")

    def _save_camera_config(self):
        """Persist current camera settings back to config.yaml."""
        try:
            with open(self.config_path, 'r') as f:
                full_config = yaml.safe_load(f) or {}

            cam = full_config.setdefault('camera', {})
            cam['roi'] = self.roi
            cam['threshold'] = self.threshold
            cam['min_pixel_count'] = self.min_pixel_count
            cam['cooldown_ms'] = self.cooldown_ms

            tmp = self.config_path.with_suffix('.tmp')
            with open(tmp, 'w') as f:
                yaml.dump(full_config, f, default_flow_style=False, sort_keys=False)
            tmp.replace(self.config_path)
            logger.info(f"Camera config saved to {self.config_path}")
        except Exception as e:
            logger.error(f"Failed to save camera config: {e}")
