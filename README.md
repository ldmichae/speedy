# Indoor Cycling

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-speedymcpuffin-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/speedymcpuffin)

A Flutter app for riding a smart trainer indoors. It connects to a Wahoo KICKR
Core (or any trainer that speaks the standard Fitness Machine Service, FTMS)
over Bluetooth, shows your live numbers, holds an ERG power target or follows a
workout plan, lets you draw routes and multi-stage tours on a map and ride them
(with the trainer simulating the climbs if you like), records rides, and keeps a
history of them. A simulated trainer is built in, so the whole app can be
developed and tried without hardware.

It is designed first for a desktop window in landscape. Narrow and portrait
windows are supported and stack the same content vertically.

## Features

- **Left dock:** every page (Ride, Routes, Tours, Plans, History, Preferences)
  is in a dock on the left. It collapses to an icon rail, and on narrow windows
  it becomes a drawer behind a menu bar. Pages have no top bars, so content
  gets the room.
- **Live data:** power (3 s average and instant), cadence, speed and heart rate.
- **ERG mode:** set a target in watts and nudge it up or down in 5, 10 and 25 W
  steps (arrow keys too).
- **Workout plans:** build a plan from blocks of steps, in watts or as a percent
  of your FTP, with optional ramps (a step can ramp from one value to another)
  and repeats. A live chart of the plan stays on screen while you edit. Starting
  a plan starts recording; the bar on the dashboard lets you pause, skip a step
  or stop, and the plan is drawn on the ride chart. The plan owns the ERG target
  while it runs.
- **Recording:** record, pause, resume and stop. On stop you save or discard
  the ride. Time, distance, average power and an energy estimate update live,
  with a chart of target, power, cadence and more. Hover the chart for a
  crosshair and a tooltip of every visible metric.
- **Routes:** draw a route on an OpenStreetMap map by clicking points; each
  stretch snaps to roads (see *Services* below). Choose **Any road** (motorways
  and tunnels allowed, no cycle paths) or **Bike-friendly** per stretch. Ride a
  route and a blue dot moves along it as you pedal, in a map tile you add to the
  dashboard.
- **Elevation:** routes and tours get an elevation profile (climb, descent,
  steepest grade) in the editor, the routes list and the ride tile.
- **Simulation mode:** ride a route with simulated climbs and the trainer's
  resistance follows the road grade (limited to -10% to +15%). Speed, and so
  your dot, then follows the terrain. The ERG controls lock while it runs.
- **Tours:** a long ride planned as stages. Elevation is loaded per stage, only
  when you ask or when a ride is about to need it (the current stage, then the
  next one from 70% through), so a tour can be as long as you like. Stages are
  ticked off as you ride them, and you can start from any stage.
- **Ride history:** a list of saved rides (time, distance, average power,
  energy) and a detail view with the same chart. Rides can be deleted after a
  confirmation.
- **Power produced:** your total output in Wh across all saved rides, and for
  the ride you are ending, with household comparisons (toast, a desk fan, a
  phone charge, a kettle).
- **Export:** each saved ride is also written as a **FIT** or **CSV** file.
- **Editable dashboard:** tiles for each metric, the ERG target, the chart and
  the route map, in a left and a right side that you arrange yourself (see
  below).
- **Rider profile:** height, weight, age and sex, used to estimate calories.
- **Preferences:** colour palette, export format, FTP, metric or imperial units
  (separately for ride data and body measurements), the rider profile, and
  credits for the map, routing and elevation data. Everything is remembered
  between launches.

### Editing the dashboard

Press **Edit layout** on the dashboard. Each side is its own three-column grid
that fills row by row.

- Drag a tile anywhere on either side, including onto empty space. Tiles in
  the way are shoved on to the next open slots, and the result is previewed
  as you drag.
- The gear on a tile sets its width (1/3, 2/3 or Full of the side) and height,
  chooses which metric it shows (picking one that is already on the dashboard
  swaps the two), or removes it.
- **Add tile** puts a removed tile back (the route map is added this way);
  **Reset to default** restores the standard layout.
- The ride totals, the chart and the route map only appear once you start
  recording, but are shown while editing so you can place them.

## Set up

The platform folders (`web`, `windows`, `macos`, `android`) are in the repo.

    flutter pub get
    flutter test
    flutter run -d windows        # or: -d macos / -d chrome

Choose **Use simulated trainer** on the first screen to try everything without
a trainer. The simulated trainer holds a steady 150 W in simulation mode and
works out speed from the grade (85 kg rider and bike assumed).

If `pub get` complains about a version, run `flutter pub add universal_ble`
and `flutter pub upgrade --major-versions`.

## Platform config

- **Web:** Chrome/Edge only, HTTPS or localhost. Pairing needs a button click.
  Saving rides and ride history are not supported on web yet. Tours are kept in
  browser storage, which is small, and elevation uses Open-Meteo only (the
  terrain tiles cannot be read from a browser).
- **macOS:** in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
  add `com.apple.security.device.bluetooth` = true, and in `macos/Runner/Info.plist`
  add `NSBluetoothAlwaysUsageDescription`. The network client entitlement
  (`com.apple.security.network.client`) is already set for maps and routing.
- **Windows:** nothing extra (Windows 10 2004+).
- **Android:** in `AndroidManifest.xml` add `BLUETOOTH_SCAN` (with
  `usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, and for
  API 30 and below `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`
  (`maxSdkVersion="30"`). Check universal_ble's README for runtime-permission
  details. `INTERNET` is already declared for maps and routing.

## Services it talks to

Maps, routing and elevation come from free public services, so the app is
careful with them. All are for light, personal use; if you distribute the app
widely, swap in your own or a keyed provider (each is behind one constant or
provider).

| Service | Used for | How we treat it |
|---|---|---|
| `tile.openstreetmap.org` | map tiles | identifying User-Agent, disk cache that honours cache headers, no retries, zoom 3-18, no prefetching, "© OpenStreetMap contributors" always visible on the map. See OSM's [tile usage policy](https://operations.osmfoundation.org/policies/tiles/). |
| `routing.openstreetmap.de` (FOSSGIS OSRM) | snapping clicks to roads | one request at a time, at least a second apart, identifying User-Agent. The `routed-car` engine is "Any road", `routed-bike` is "Bike-friendly". |
| AWS Terrain Tiles | elevation (native only) | one PNG per ~7-10 km tile, downloaded once and cached forever, at most 2 at a time. |
| Open-Meteo elevation API | elevation fallback, and on web | billed per coordinate (600 a minute, about 10,000 a day), so lookups are capped at 250 points a route, paced by its rate-limit headers, and never retried on a 429. |

If a service fails, the app degrades instead of stopping: a stretch that cannot
snap is drawn straight, a route without elevation still rides (flat in
simulation mode), and a rate limit shows a "try again in N min" message.

## Where your data goes

- **Exported rides:** `<Documents>/IndoorCycling/ride_YYYYMMDD_HHMMSS.fit` (or
  `.csv`), in the format chosen in Preferences.
- **Ride history:** one JSON file per ride in the app's support folder, under
  `history/`. These keep the ERG target, which FIT cannot, and the energy
  estimate from when the ride was saved. Deleting a ride from history does not
  delete its exported file.
- **Tours:** one JSON file per tour under `tours/` in the same folder (browser
  storage on web). Paths are simplified to about 5 m.
- **Terrain tile cache:** `terrain/` in the same folder.
- **Preferences, FTP, workout plans, single routes and the dashboard layout:**
  stored with `shared_preferences`.

Saved rides, exports and the rider profile are always metric; imperial units
only change what is shown and typed.

## Layout

    lib/core/                  data and rules, no Flutter widgets: BikeData,
                               PowerSmoother, ride samples and the Recording
                               rules, stats and calories, FIT/CSV export,
                               ride history store, rider profile, units,
                               dashboard layout model and tile placement,
                               workout plans, routes and tours, elevation,
                               OSRM / Open-Meteo / terrain-tile clients,
                               power-produced comparisons
    lib/devices/trainer.dart   Trainer interface (ERG + SIM)
    lib/devices/trainer_session.dart   a connected trainer with smoothed readings
    lib/devices/ble/           BleTransport seam, device scanner, and the one
                               universal_ble file
    lib/devices/ftms/          parser, control point queue, FtmsTrainer
    lib/devices/simulated/     simulated trainer (ERG and grade simulation)
    lib/ui/                    Riverpod controllers and screens: the dock and
                               page frame (home_screen.dart, navigation.dart),
                               dashboard and its tile grid, recording bar, ride
                               chart, plans, routes, tours, elevation chart,
                               history, preferences
    test/                      unit and widget tests; test/fakes/ holds
                               in-memory stand-ins for Bluetooth and ride history

## Tests

    flutter test

`test/widget_test.dart` (connect to the simulated trainer, then Disconnect)
currently fails and is not fixed yet: disconnecting never completes under the
test's fake clock, although it works in the app. Everything else passes. Tests
never use the network; the map tiles, routing and elevation sources are
replaced with fakes.

## First hardware test

1. Close the Wahoo and Zwift apps and anything else connected to the KICKR.
2. Wake the trainer by pedalling, then Find trainer.
3. Once connected it starts ERG at 100 W; use the +/- buttons to move the target.
4. For simulation mode, set your weight in the trainer's own app first (Wahoo,
   for a KICKR): the grade command does not carry rider weight, so the trainer
   uses what it has stored.

## Known limits

- **Calories are an estimate:** pedalling work at a typical cycling efficiency
  plus resting metabolism (Mifflin-St Jeor) from your profile. Real efficiency
  varies between riders.
- **FIT export** is a small hand-written encoder (file id, records, session and
  activity). It has not yet been checked against Strava or Garmin Connect, so
  import one ride before relying on it.
- **Distance** is worked out from speed over time, so it works for trainers
  that do not report a distance value. It also moves the dot on a route.
- **Elevation is approximate:** the data is about 30-90 m resolution, so short
  steep ramps and bridges can be wrong, and heights from the two sources differ
  by about 20 m on average in steep country.
- **Routing:** "Any road" ignores cycle paths and may use roads where cycling is
  illegal; fine for an indoor ride, not for planning an outdoor one.
- **History** reads every ride file to build the list, which is fine for dozens
  of rides but would need an index for hundreds.
- **Not yet:** extending a tour while riding, GPX import/export, offline map
  tiles, and showing a ride's route on the history chart.
