import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/devices/ble/universal_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('writes with a response when the characteristic takes one', () async {
    final tries = <bool>[];
    await writeWithFallback(
        (withoutResponse) async => tries.add(withoutResponse));
    expect(tries, [false]);
  });

  test('falls back to no response when that is all it takes (Zwift Click)',
      () async {
    final tries = <bool>[];
    await writeWithFallback((withoutResponse) async {
      tries.add(withoutResponse);
      if (!withoutResponse) {
        throw UniversalBleException(
            code: UniversalBleErrorCode.characteristicDoesNotSupportWrite,
            message: 'Characteristic does not support write withResponse',
            details: 38);
      }
    });
    expect(tries, [false, true]);
  });

  test('other write failures are reported, not retried', () async {
    final tries = <bool>[];
    final failure = UniversalBleException(
        code: UniversalBleErrorCode.deviceDisconnected, message: 'gone');
    await expectLater(writeWithFallback((withoutResponse) async {
      tries.add(withoutResponse);
      throw failure;
    }), throwsA(same(failure)));
    expect(tries, [false]);
  });
}
