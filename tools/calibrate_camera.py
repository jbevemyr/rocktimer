#!/usr/bin/env python3
"""
StoneTimer Camera Calibration Tool

Opens a live camera preview with ROI overlay and frame-diff visualization.
Use the mouse to drag/resize the ROI rectangle, then press 's' to save
the ROI coordinates to config.yaml.

Requires a display (run directly on the Pi with a monitor, or via X-forwarding).

Keys:
  s     — save ROI to config.yaml
  d     — toggle diff view
  +/-   — adjust threshold
  q/Esc — quit
"""

import sys
import cv2
import yaml
import numpy as np
from pathlib import Path

CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"

try:
    from picamera2 import Picamera2
    PICAMERA2_AVAILABLE = True
except ImportError:
    PICAMERA2_AVAILABLE = False


def load_config(path):
    with open(path, 'r') as f:
        return yaml.safe_load(f)


def save_config(path, config):
    tmp = path.with_suffix('.tmp')
    with open(tmp, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    tmp.replace(path)


class Calibrator:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.config = load_config(config_path)
        cam_cfg = self.config.get('camera', {})

        self.resolution = tuple(cam_cfg.get('resolution', [320, 240]))
        self.fps = cam_cfg.get('fps', 60)
        self.roi = list(cam_cfg.get('roi', [0, 0, self.resolution[0], self.resolution[1]]))
        self.threshold = cam_cfg.get('threshold', 30)
        self.min_pixel_count = cam_cfg.get('min_pixel_count', 500)

        self.show_diff = False
        self.dragging = False
        self.drag_start = None
        self.prev_gray = None

    def _open_camera(self):
        w, h = self.resolution
        if PICAMERA2_AVAILABLE:
            cam = Picamera2()
            cam_config = cam.create_video_configuration(
                main={"size": (w, h), "format": "RGB888"},
                controls={"FrameRate": self.fps}
            )
            cam.configure(cam_config)
            cam.start()
            return cam
        else:
            cap = cv2.VideoCapture(0)
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
            cap.set(cv2.CAP_PROP_FPS, self.fps)
            if not cap.isOpened():
                print("ERROR: Could not open camera")
                sys.exit(1)
            return cap

    def _grab_frame(self, cam):
        if PICAMERA2_AVAILABLE and isinstance(cam, Picamera2):
            return cam.capture_array()
        else:
            ret, frame = cam.read()
            return frame if ret else None

    def _mouse_callback(self, event, x, y, flags, param):
        if event == cv2.EVENT_LBUTTONDOWN:
            self.dragging = True
            self.drag_start = (x, y)
        elif event == cv2.EVENT_MOUSEMOVE and self.dragging:
            sx, sy = self.drag_start
            self.roi = [min(sx, x), min(sy, y), abs(x - sx), abs(y - sy)]
        elif event == cv2.EVENT_LBUTTONUP:
            self.dragging = False

    def run(self):
        cam = self._open_camera()
        window = 'StoneTimer Calibration'
        cv2.namedWindow(window)
        cv2.setMouseCallback(window, self._mouse_callback)

        print("Camera calibration started.")
        print("  Drag to set ROI | d=toggle diff | +/-=threshold | s=save | q=quit")

        while True:
            frame = self._grab_frame(cam)
            if frame is None:
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if len(frame.shape) == 3 else frame
            display = frame.copy() if len(frame.shape) == 3 else cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)

            rx, ry, rw, rh = self.roi
            pixel_count = 0

            if self.prev_gray is not None:
                diff = cv2.absdiff(gray, self.prev_gray)
                _, thresh = cv2.threshold(diff, self.threshold, 255, cv2.THRESH_BINARY)

                rx_c = max(0, min(rx, gray.shape[1] - 1))
                ry_c = max(0, min(ry, gray.shape[0] - 1))
                rw_c = max(1, min(rw, gray.shape[1] - rx_c))
                rh_c = max(1, min(rh, gray.shape[0] - ry_c))
                roi_mask = thresh[ry_c:ry_c+rh_c, rx_c:rx_c+rw_c]
                pixel_count = cv2.countNonZero(roi_mask)

                if self.show_diff:
                    display = cv2.cvtColor(thresh, cv2.COLOR_GRAY2BGR)

            self.prev_gray = gray

            color = (0, 0, 255) if pixel_count >= self.min_pixel_count else (0, 255, 0)
            cv2.rectangle(display, (rx, ry), (rx + rw, ry + rh), color, 2)

            info = f"ROI: {self.roi}  thr: {self.threshold}  px: {pixel_count}/{self.min_pixel_count}"
            cv2.putText(display, info, (5, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

            cv2.imshow(window, display)

            key = cv2.waitKey(1) & 0xFF
            if key in (ord('q'), 27):
                break
            elif key == ord('d'):
                self.show_diff = not self.show_diff
            elif key == ord('s'):
                self._save()
                print(f"Saved ROI={self.roi}, threshold={self.threshold}")
            elif key == ord('+') or key == ord('='):
                self.threshold = min(255, self.threshold + 5)
                print(f"Threshold: {self.threshold}")
            elif key == ord('-'):
                self.threshold = max(1, self.threshold - 5)
                print(f"Threshold: {self.threshold}")

        cv2.destroyAllWindows()
        if PICAMERA2_AVAILABLE and isinstance(cam, Picamera2):
            cam.stop()
        else:
            cam.release()

    def _save(self):
        config = load_config(self.config_path)
        cam = config.setdefault('camera', {})
        cam['roi'] = self.roi
        cam['threshold'] = self.threshold
        cam['min_pixel_count'] = self.min_pixel_count
        save_config(self.config_path, config)


def main():
    config_path = CONFIG_PATH
    if len(sys.argv) > 1:
        config_path = Path(sys.argv[1])
    if not config_path.exists():
        print(f"Config not found: {config_path}")
        sys.exit(1)
    Calibrator(config_path).run()


if __name__ == '__main__':
    main()
