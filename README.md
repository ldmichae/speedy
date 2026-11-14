# Indoor Cycling

<p align="center">
  <a href="https://buymeacoffee.com/speedymcpuffin">
    <img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=speedymcpuffin&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff" alt="Buy me a coffee" height="60">
  </a>
  <br>
  <sub>Enjoying the app? A coffee helps keep it going.</sub>
</p>

Ride a smart trainer from your desktop. Connect a Wahoo KICKR (or any trainer
that supports Bluetooth FTMS), follow a workout, or ride a route you drew on a
map with the trainer's resistance following the climbs. Rides are recorded and
exported as FIT or CSV.

No trainer? Pick **Use simulated trainer** on the first screen and try
everything.

## What you can do

- **Ride with live numbers:** power (3 s average and instant), cadence, speed,
  heart rate, distance and energy, with a live chart.
- **ERG mode:** hold a target wattage and nudge it with the buttons or arrow
  keys (5 W, or 25 W with Shift). Space starts, pauses and resumes recording.
- **Workout plans:** build plans from steps in watts or % of FTP, with ramps
  and repeats. A plan drives the ERG target and draws itself on the ride chart.
- **Routes and tours:** draw a route on a map (snapped to roads) or split one
  into stages for a long tour. Each gets an elevation profile.
- **Simulation mode:** the trainer's resistance follows the road grade
  (-10% to +15%) as you ride your route.
- **History:** saved rides with the same chart, and your total power output
  compared with toast, a kettle and a phone charge.
- **Three ride views:** a customisable **Dashboard** of tiles, a **Map** view
  (full-width map with the elevation profile along its bottom edge), or a
  **Chart** view (full-width chart with a resizable map in the corner). Map and
  Chart keep the key metrics in a fixed strip and never scroll.
- **Make it yours:** colour palette, metric or imperial units, FTP and a rider
  profile for calorie estimates. Everything is remembered between launches.

Built for a landscape desktop window; narrow and portrait windows stack the
same content.

## Run it

    flutter pub get
    flutter run -d windows        # or: -d macos / -d chrome

If `pub get` complains about a version, run `flutter pub add universal_ble`
then `flutter pub upgrade --major-versions`.

**First ride with a real trainer:** close the Wahoo and Zwift apps, wake the
trainer by pedalling, then choose Find trainer. For simulation mode, set your
weight in the trainer's own app first, since the grade command does not carry
it.

### Platform notes

- **Web:** Chrome or Edge on HTTPS or localhost. Saving rides and history are
  not supported yet, and elevation comes from Open-Meteo only.
- **Windows:** nothing extra (Windows 10 2004 or later).
- **macOS:** add the `com.apple.security.device.bluetooth` entitlement (Debug
  and Release) and `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
- **Android:** add the Bluetooth permissions (`BLUETOOTH_SCAN` with
  `neverForLocation`, `BLUETOOTH_CONNECT`, and the legacy ones for API 30 and
  below). See [universal_ble](https://pub.dev/packages/universal_ble).

## Your data

- **Exported rides:** `<Documents>/IndoorCycling/ride_YYYYMMDD_HHMMSS.fit` (or
  `.csv`).
- **History, tours and the terrain cache:** JSON files in the app's support
  folder (browser storage on web). Deleting a ride from history leaves its
  exported file alone.
- **Settings, FTP, plans and the dashboard layout:** `shared_preferences`.

Saved rides and exports are always metric; imperial only changes what you see.

## Online services

Maps, routing and elevation use free public services, so the app is gentle with
them: cached, rate-limited and never retried on a rate limit. They are meant for
light personal use. If you distribute the app widely, swap in your own or a
keyed provider (each is behind one constant or provider).

| Service | Used for |
|---|---|
| OpenStreetMap tiles | map ([tile policy](https://operations.osmfoundation.org/policies/tiles/)) |
| FOSSGIS OSRM | snapping clicks to roads |
| AWS Terrain Tiles | elevation (native only) |
| Open-Meteo | elevation fallback, and on web |

If a service fails the app carries on: a stretch that cannot snap is drawn
straight, and a route without elevation still rides (flat).

## Known limits

- Calories are an estimate from your profile and typical cycling efficiency.
- FIT export is a small hand-written encoder, not yet checked against Strava or
  Garmin Connect. Import one ride before relying on it.
- Elevation is approximate (30-90 m resolution): short steep ramps and bridges
  can be wrong.
- "Any road" routing ignores cycle paths and may use roads closed to bikes. Fine
  for an indoor ride, not for planning an outdoor one.
- Not yet: extending a tour while riding, offline map tiles, and showing a
  ride's route on the history chart.

## For developers

    flutter test

Tests never touch the network or Bluetooth; both are replaced with fakes.
`test/widget_test.dart` (connect to the simulated trainer, then Disconnect)
currently fails: disconnecting never completes under the test's fake clock,
though it works in the app. Everything else passes.

    lib/core/       data and rules, no widgets: ride recording, stats, FIT/CSV
                    export, plans, routes, tours, elevation, service clients
    lib/devices/    trainer interface, FTMS parser, Bluetooth seam, simulated
                    trainer
    lib/ui/         Riverpod controllers and screens
    test/           unit and widget tests, with fakes in test/fakes/
