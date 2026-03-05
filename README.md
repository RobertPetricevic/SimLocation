# SimLocation

A macOS app for iOS developers that lets you simulate GPS locations on iOS Simulators — without touching Xcode's clunky location simulation menu. Pick a simulator, set coordinates (or search for a place), and the location is injected instantly via `simctl`.

## Installation

### Download

Download the latest `.dmg` from [GitHub Releases](../../releases), open it, and drag **SimLocation** to your Applications folder.

### Build from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/RobertPetricevic/SimLocation.git
cd SimLocation/SimLocation
xcodegen generate
open SimLocation.xcodeproj
```

Build and run with `Cmd+R`.

### First Launch

Since the app is not notarized, macOS will block it on first open. To allow it:

1. Click **Done** on the warning dialog
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the SimLocation message
4. Enter your password — the app will now open normally going forward

### Requirements

- macOS 14.0 (Sonoma) or later
- Xcode with iOS Simulator (for iOS location simulation)
- Android SDK with `adb` (optional, for Android emulator support)

## Features

| Feature                        | Description                                                                                                                        |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Single location simulation** | Set any GPS coordinate on a running iOS Simulator with one click                                                                   |
| **Location search**            | Search for places/addresses by name using MapKit geocoding — no need to look up coordinates manually                               |
| **Saved presets**              | Save favorite locations and routes ("My Office", "Test Route A") and apply them instantly                                          |
| **Road-based routing**         | Generate realistic driving/walking routes that follow actual roads (via `MKDirections`), not just straight lines between waypoints |
| **Route simulation**           | Define multi-waypoint routes and simulate movement along them                                                                      |
| **Drag waypoints on map**      | Reposition route waypoints by dragging pins directly on the map                                                                    |
| **GPX import**                 | Import standard `.gpx` GPS files — compatible with many GPS tools and Xcode                                                        |
| **JSON import/export**         | Import/export location configs as JSON for sharing and CLI tool compatibility                                                      |
| **Geofence visualization**     | Draw circle overlays on the map to visualize geofence regions you're testing                                                       |
| **Coordinate format options**  | Toggle between decimal degrees and DMS (degrees/minutes/seconds)                                                                   |
| **Simulator picker**           | Detect and select from all booted iOS Simulators                                                                                   |
| **Multi-simulator broadcast**  | Send the same location to all booted simulators simultaneously                                                                     |
| **Android emulator support**   | Simulate locations on Android emulators via `adb emu geo fix`, with automatic emulator detection                                   |
| **Scenario mode**              | Pre-built test scenarios (City Run, City Bicycle Ride, Freeway Drive) with realistic movement                                      |
| **Speed presets**              | Walk, Run, Bicycle, Drive, Highway, or custom speed for route simulation                                                           |

## Privacy

SimLocation does not collect, store, or transmit any personal data. All location data stays on your Mac. Network access is used solely for MapKit geocoding (place name search).

## License

MIT License — see [LICENSE](LICENSE) for details.
