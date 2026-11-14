# Indoor Cycling

A Flutter app for riding a smart trainer indoors. It connects to a Wahoo KICKR
Core (or any trainer that speaks the standard Fitness Machine Service, FTMS)
over Bluetooth, shows your live numbers, holds an ERG power target, records
rides, and keeps a history of them. A simulated trainer is built in, so the
whole app can be developed and tried without hardware.

It is designed first for a desktop window in landscape. Narrow and portrait
windows are supported and stack the same content vertically.

## Features

- **Live data:** power (3 s average and instant), cadence, speed and heart rate.
- **ERG mode:** set a target in watts and nudge it up or down in 5, 10 and 25 W steps.
- **Recording:** record, pause, resume and stop. On stop you save or discard
  the ride. Time, distance, average power and an energy estimate update live,
  with a chart of target, power, cadence and more. Hover the chart for a
  crosshair and a tooltip of every visible metric.
- **Ride history:** a list of saved rides (time, distance, average power,
  energy) and a detail view with the same chart. Rides can be deleted after a
  confirmation.
- **Export:** each saved ride is also written as a **FIT** or **CSV** file.
- **Editable dashboard:** tiles for each metric, the ERG target and the chart,
  in a left and a right side that you arrange yourself (see below).
- **Rider profile:** height, weight, age and sex, used to estimate calories.
- **Preferences:** colour palette, export format, metric or imperial units
  (separately for ride data and body measurements), and the rider profile.
  Everything is remembered between launches.

### Editing the dashboard

Press **Edit layout** on the dashboard. Each side is its own three-column grid
that fills row by row.

- Drag a tile anywhere on either side, including onto empty space. Tiles in
  the way are shoved on to the next open slots, and the result is previewed
  as you drag.
- The gear on a tile sets its width (1/3, 2/3 or Full of the side) and height,
  chooses which metric it shows (picking one that is already on the dashboard
  swaps the two), or removes it.
- **Add tile** puts a removed tile back; **Reset to default** restores the
  standard layout.
- The ride totals and the chart only appear once you start recording, but are
  shown while editing so you can place them.

## Set up

The platform folders (`web`, `windows`, `macos`, `android`) are in the repo.

    flutter pub get
    flutter test
    flutter run -d windows        # or: -d macos / -d chrome

Choose **Use simulated trainer** on the first screen to try everything without
a trainer.

If `pub get` complains about a version, run `flutter pub add universal_ble`
and `flutter pub upgrade --major-versions`.

## Platform config

- **Web:** Chrome/Edge only, HTTPS or localhost. Pairing needs a button click.
  Saving rides and ride history are not supported on web yet.
- **macOS:** in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
  add `com.apple.security.device.bluetooth` = true, and in `macos/Runner/Info.plist`
  add `NSBluetoothAlwaysUsageDescription`.
- **Windows:** nothing extra (Windows 10 2004+).
- **Android:** in `AndroidManifest.xml` add `BLUETOOTH_SCAN` (with
  `usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, and for
  API 30 and below `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`
  (`maxSdkVersion="30"`). Check universal_ble's README for runtime-permission details.

## Where your data goes

- **Exported rides:** `<Documents>/IndoorCycling/ride_YYYYMMDD_HHMMSS.fit` (or
  `.csv`), in the format chosen in Preferences.
- **Ride history:** one JSON file per ride in the app's support folder, under
  `history/`. These keep the ERG target, which FIT cannot, and the energy
  estimate from when the ride was saved. Deleting a ride from history does not
  delete its exported file.
- **Preferences and the dashboard layout:** stored with `shared_preferences`.

Saved rides, exports and the rider profile are always metric; imperial units
only change what is shown and typed.

## Layout

    lib/core/                  data and rules, no Flutter widgets: BikeData,
                               PowerSmoother, ride samples and the Recording
                               rules, stats and calories, FIT/CSV export,
                               ride history store, rider profile, units,
                               dashboard layout model and tile placement
    lib/devices/trainer.dart   Trainer interface (ERG + SIM)
    lib/devices/trainer_session.dart   a connected trainer with smoothed readings
    lib/devices/ble/           BleTransport seam, device scanner, and the one
                               universal_ble file
    lib/devices/ftms/          parser, control point queue, FtmsTrainer
    lib/devices/simulated/     simulated trainer
    lib/ui/                    Riverpod controllers and screens: dashboard
                               and its tile grid, recording bar, ride chart,
                               history, preferences
    test/                      unit and widget tests; test/fakes/ holds
                               in-memory stand-ins for Bluetooth and ride history

## Tests

    flutter test

`test/widget_test.dart` (connect to the simulated trainer, then Disconnect)
currently fails and is not fixed yet; everything else passes.

## First hardware test

1. Close the Wahoo and Zwift apps and anything else connected to the KICKR.
2. Wake the trainer by pedalling, then Find trainer.
3. Once connected it starts ERG at 100 W; use the +/- buttons to move the target.

## Known limits

- **Calories are an estimate:** pedalling work at a typical cycling efficiency
  plus resting metabolism (Mifflin-St Jeor) from your profile. Real efficiency
  varies between riders.
- **FIT export** is a small hand-written encoder (file id, records, session and
  activity). It has not yet been checked against Strava or Garmin Connect, so
  import one ride before relying on it.
- **Distance** is worked out from speed over time, so it works for trainers
  that do not report a distance value.
- **History** reads every ride file to build the list, which is fine for dozens
  of rides but would need an index for hundreds.
