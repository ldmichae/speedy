# Indoor Cycling

Phase 1 skeleton: BLE connect to a Wahoo KICKR Core (FTMS), live power /
cadence / speed, manual ERG target, plus a simulated trainer for hardware-free
development.

## Set up

This archive contains only the Dart source. Generate the platform folders
first, then overlay it:

    flutter create --platforms=web,windows,macos,android --project-name indoor_cycling indoor_cycling
    # unzip this archive over the new project (overwrite pubspec.yaml, lib/, test/)
    cd indoor_cycling
    flutter pub get
    flutter test
    flutter run -d chrome        # or: -d windows / -d macos

If `pub get` complains about a version, run `flutter pub add universal_ble`
and `flutter pub upgrade --major-versions`.

## Platform config

- **Web:** Chrome/Edge only, HTTPS or localhost. Pairing needs a button click.
- **macOS:** in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
  add `com.apple.security.device.bluetooth` = true, and in `macos/Runner/Info.plist`
  add `NSBluetoothAlwaysUsageDescription`.
- **Windows:** nothing extra (Windows 10 2004+).
- **Android:** in `AndroidManifest.xml` add `BLUETOOTH_SCAN` (with
  `usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, and for
  API 30 and below `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`
  (`maxSdkVersion="30"`). Check universal_ble's README for runtime-permission details.

## Layout

    lib/core/                 BikeData, PowerSmoother
    lib/devices/trainer.dart  Trainer interface (ERG + SIM)
    lib/devices/ble/          BleTransport seam + the one universal_ble file
    lib/devices/ftms/         parser, control point queue, FtmsTrainer
    lib/devices/simulated/    fake trainer
    lib/ui/                   Riverpod controller + screens
    test/                     parser, control point, smoothing, widget smoke test

## First hardware test

1. Close the Wahoo and Zwift apps and anything else connected to the KICKR.
2. Wake the trainer by pedalling, then Find trainer.
3. Once connected it starts ERG at 100 W; use the +/- buttons to move the target.
