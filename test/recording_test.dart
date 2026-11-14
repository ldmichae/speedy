import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/ride_export.dart';
import 'package:indoor_cycling/core/ride_recording.dart';
import 'package:indoor_cycling/core/units.dart';
import 'package:indoor_cycling/ui/recorder_controller.dart';
import 'package:indoor_cycling/ui/ride_chart.dart';

void main() {
  test('ridesToCsv leaves missing values blank', () {
    final csv = ridesToCsv(const [
      RideSample(t: 1, target: 150, power: 148, smoothedPower: 147.5, cadence: 90),
      RideSample(t: 2, target: 150),
    ]);
    final lines = csv.trim().split('\n');
    expect(lines[0], startsWith('time_s,target_w'));
    expect(lines[1], '1.0,150,148,147.5,90.0,,');
    expect(lines[2], '2.0,150,,,,,');
  });

  test('ridesToFit has a valid header, size and CRC', () {
    final fit = ridesToFit(const [
      RideSample(t: 0, power: 150, cadence: 90, speed: 30, heartRate: 140),
      RideSample(t: 1, power: 152),
    ], DateTime.utc(2026, 1, 1));
    final d = ByteData.sublistView(fit);
    expect(fit[0], 14);
    expect(String.fromCharCodes(fit.sublist(8, 12)), '.FIT');
    expect(d.getUint32(4, Endian.little), fit.length - 14 - 2);
    // Running the CRC over the whole file including its own CRC yields 0.
    int crc = 0;
    const t = [
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ];
    for (final b in fit) {
      crc = ((crc >> 4) & 0x0FFF) ^ t[crc & 0xF] ^ t[b & 0xF];
      crc = ((crc >> 4) & 0x0FFF) ^ t[crc & 0xF] ^ t[(b >> 4) & 0xF];
    }
    expect(crc, 0);
  });

  group('Recording', () {
    const input = SampleInput(target: 150);
    Duration s(int n) => Duration(seconds: n);

    test('start records a first sample at t=0', () {
      final r = Recording()..start(s(100), DateTime.utc(2026), input);
      expect(r.status, RecStatus.recording);
      expect(r.samples.single.t, 0);
      expect(r.samples.single.target, 150);
    });

    test('paused time is not counted and paused ticks are ignored', () {
      final r = Recording()..start(s(100), DateTime.utc(2026), input);
      r.add(s(101), input);
      r.add(s(102), input);
      r.pause(s(102));
      r.add(s(110), input); // late timer tick while paused
      expect(r.samples, hasLength(3));
      expect(r.elapsed(s(120)), s(2));

      r.resume(s(130));
      r.add(s(131), input);
      expect(r.samples.last.t, 3);
      expect(r.elapsed(s(135)), s(7));
    });

    test('pause, resume and start are no-ops in the wrong state', () {
      final r = Recording()
        ..pause(s(1))
        ..resume(s(2));
      expect(r.status, RecStatus.idle);
      r.start(s(3), DateTime.utc(2026), input);
      r.start(s(9), DateTime.utc(2027), input); // already running
      expect(r.samples, hasLength(1));
      expect(r.startedAt, DateTime.utc(2026));
    });

    test('reset returns to idle with no samples', () {
      final r = Recording()..start(s(0), DateTime.utc(2026), input);
      r.reset();
      expect(r.status, RecStatus.idle);
      expect(r.samples, isEmpty);
      expect(r.elapsed(s(50)), Duration.zero);
    });
  });

  test('recorder notifier wires start/pause/resume/discard', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(recorderProvider.notifier);
    RecStatus status() => container.read(recorderProvider).status;

    c.start();
    expect(status(), RecStatus.recording);
    c.pause();
    expect(status(), RecStatus.paused);
    c.resume();
    expect(status(), RecStatus.recording);
    c.discard();
    expect(status(), RecStatus.idle);
    expect(container.read(recorderProvider).samples, isEmpty);
  });

  testWidgets('chart paints with data, gaps and every metric on', (tester) async {
    final samples = [
      for (var i = 0; i < 120; i++)
        RideSample(
          t: i.toDouble(),
          target: i < 60 ? 150 : 200,
          power: i % 17 == 0 ? null : 140 + i % 30,
          smoothedPower: 150,
          cadence: 85,
          speed: 30,
          heartRate: 140,
        ),
    ];
    for (final settings in [
      ChartSettings(visible: RideMetric.values.toSet()),
      const ChartSettings(window: Duration(minutes: 1)),
      const ChartSettings(visible: {}),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 600,
            height: 300,
            child: RideChart(samples: samples, settings: settings)),
      ));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart paints with imperial speed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 600,
        height: 300,
        child: RideChart(
          samples: [
            for (var i = 0; i < 60; i++) RideSample(t: i.toDouble(), speed: 36, power: 200),
          ],
          settings: const ChartSettings(
              visible: {RideMetric.speed, RideMetric.power}),
          units: UnitSystem.imperial,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
