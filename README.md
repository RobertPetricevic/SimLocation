# SimLocation

A macOS app for iOS developers that lets you simulate GPS locations on iOS Simulators — without touching Xcode's clunky location simulation menu. Pick a simulator, set coordinates (or search for a place), and the location is injected instantly via `simctl`.

## Features

| Feature | Description |
|---|---|
| **Single location simulation** | Set any GPS coordinate on a running iOS Simulator with one click |
| **Location search** | Search for places/addresses by name using MapKit geocoding — no need to look up coordinates manually |
| **Saved presets** | Save favorite locations and routes ("My Office", "Test Route A") and apply them instantly |
| **Road-based routing** | Generate realistic driving/walking routes that follow actual roads (via `MKDirections`), not just straight lines between waypoints |
| **Route simulation** | Define multi-waypoint routes and simulate movement along them |
| **Drag waypoints on map** | Reposition route waypoints by dragging pins directly on the map |
| **GPX import** | Import standard `.gpx` GPS files — compatible with many GPS tools and Xcode |
| **JSON import/export** | Import/export location configs as JSON for sharing and CLI tool compatibility |
| **Geofence visualization** | Draw circle overlays on the map to visualize geofence regions you're testing |
| **Coordinate format options** | Toggle between decimal degrees and DMS (degrees/minutes/seconds) |
| **Simulator picker** | Detect and select from all booted iOS Simulators |
| **Multi-simulator broadcast** | Send the same location to all booted simulators simultaneously |
| **Android emulator support** | Simulate locations on Android emulators via `adb emu geo fix`, with automatic emulator detection |
| **Scenario mode** | Pre-built test scenarios (City Run, City Bicycle Ride, Freeway Drive) with realistic movement |
| **Speed presets** | Walk, Run, Bicycle, Drive, Highway, or custom speed for route simulation |

## Future Improvements

### High Impact

- **Input validation** — Add bounds checking for coordinates (lat -90–90, lon -180–180), custom speed, and route interval fields
- **Unit tests** — Add test coverage for coordinate parsing, GPX import, and service layers
- **Map annotation diffing** — Diff and update only changed annotations instead of removing and re-adding all on every update
- **Undo/redo** — Support undo/redo for waypoint additions, deletions, and geofence changes

### Medium Impact

- **Recent locations history** — Track recently used locations for quick access
- **Route ETA display** — Show estimated arrival time based on distance and selected speed
- **Altitude/elevation support** — Support 3D coordinates for apps that need altitude testing
- **Location accuracy simulation** — Simulate GPS accuracy radius for testing location-sensitive apps
- **Custom scenarios** — Allow users to create and save custom scenarios beyond the hardcoded Apple ones
- **Preset management** — Add rename, drag-to-reorder, and folder/category support for presets
- **Confirmation dialogs** — Add confirmation prompts when deleting presets or geofences
- **Route speed profiles** — Vary speed along a route (e.g., slow at turns, fast on straightaways)
