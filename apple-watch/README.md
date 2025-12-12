# RockTimer Apple Watch App

Apple Watch app for displaying curling times and arming the timing system.

## Building the app

### Requirements
- macOS med Xcode 15+
- Apple Developer account (to run on a physical watch)

### Steps

1. Open `RockTimer.xcodeproj` in Xcode

2. Configure the server URL in `TimerViewModel.swift`:
   ```swift
   private let serverURL = "http://192.168.50.1:8080"
   ```

3. Select "RockTimer WatchKit App" as the target

4. Run on the simulator or a physical Apple Watch

## Features

- **Display times**: Total time, Tee→Hog, Hog→Hog
- **Arm system**: Start a new measurement
- **Cancel**: Cancel the current measurement
- **Haptic feedback**: Vibrate on new times

## Network configuration

Apple Watch communicates via the paired iPhone when it is not on the same Wi‑Fi.
For best results, ensure the iPhone is connected to the same Wi‑Fi (192.168.50.x).

### Optional: WatchConnectivity

For a more robust solution, the app can be modified to use WatchConnectivity
to communicate via the paired iPhone. This requires a companion iOS app.

## Troubleshooting

### The app can't connect
1. Check that the Pi 4 is running and reachable
2. Verify that the iPhone is on the same Wi‑Fi network
3. Try opening `http://192.168.50.1:8080` in Safari on the iPhone

### Times do not update
- The app polls the server every second
- Check network connectivity

