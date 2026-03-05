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

## Planned

- **Multi-simulator broadcast** — Send the same location to all booted simulators simultaneously
- **Android emulator support** — Simulate locations on Android emulators via `adb emu geo fix`, with automatic emulator detection
