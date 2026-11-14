/// Expands a 16/32-bit Bluetooth UUID to the full lowercase 128-bit form.
String normalizeUuid(String uuid) {
  final s = uuid.toLowerCase().replaceAll('0x', '');
  if (s.length == 4) return '0000$s-0000-1000-8000-00805f9b34fb';
  if (s.length == 8) return '$s-0000-1000-8000-00805f9b34fb';
  return s;
}

String uuid16(int short) =>
    normalizeUuid(short.toRadixString(16).padLeft(4, '0'));

final ftmsService = uuid16(0x1826);
final cyclingPowerService = uuid16(0x1818);
final heartRateService = uuid16(0x180D);

final indoorBikeDataChar = uuid16(0x2AD2);
final ftmsControlPointChar = uuid16(0x2AD9);
final ftmsStatusChar = uuid16(0x2ADA);
final heartRateMeasurementChar = uuid16(0x2A37);
