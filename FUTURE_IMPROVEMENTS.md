# Future Improvements

## High Impact

1. ~~**Location search** — Add a search bar that geocodes addresses/place names (MapKit's `MKLocalSearch`). Way faster than clicking or typing coordinates.~~ **Done**

2. ~~**Saved presets** — Save/load favorite locations and routes within the app. A sidebar list of "My Office", "Test Route A", etc. that you can apply with one click.~~ **Done**

3. ~~**Road-based routing** — Instead of straight-line waypoints, use MapKit's `MKDirections` API to generate a realistic driving/walking route between two points that follows actual roads.~~ **Done**

4. ~~**Import/export JSON configs** — Import existing `location.json` and `examples/*.json` files directly, and export routes from the app back to JSON (keeps compatibility with the CLI tool).~~ **Done**

## Medium Impact

5. ~~**Drag waypoints on the map** — Reposition waypoints by dragging pins instead of delete + re-add.~~ **Done**

6. ~~**GPX import** — GPX is the standard GPS exchange format. Many tools export GPX, and Xcode itself uses it.~~ **Done**

9. ~~**Geofence visualization** — Draw a circle overlay on the map to visualize geofence regions you're testing against.~~ **Done**

## Nice to Have

11. ~~**Coordinate format options** — Toggle between decimal degrees and DMS (degrees/minutes/seconds).~~ **Done**

12. **Multi-simulator broadcast** — Send the same location to all booted simulators at once.

13. **Android emulator support** — Simulate locations on Android emulators via `adb emu geo fix`. Detect running emulators with `adb devices` and let users pick between iOS/Android targets.
