import 'dart:convert';
import 'dart:typed_data';

import '../ble/uuids.dart';

/// Zwift Click, Play and Ride shifters. Click v1 and Play expose the custom
/// service; Ride and Click v2 expose the same characteristics under 0xFC82.
const zwiftCustomService = '00000001-19ca-4651-86e5-fa29dcdd09d1';
final zwiftRideService = uuid16(0xFC82);
const zwiftAsyncChar = '00000002-19ca-4651-86e5-fa29dcdd09d1'; // notify: buttons
const zwiftSyncRxChar = '00000003-19ca-4651-86e5-fa29dcdd09d1'; // write
const zwiftSyncTxChar = '00000004-19ca-4651-86e5-fa29dcdd09d1'; // indicate

/// Written to [zwiftSyncRxChar] to start button notifications.
// shortcut: plain handshake only; Click/Play on pre-2024 firmware want an
// encrypted one. Upgrade if users can't update firmware via Zwift Companion.
final zwiftRideOn = Uint8List.fromList(ascii.encode('RideOn'));

const _clickMsg = 0x37, _playMsg = 0x07, _rideMsg = 0x23;

/// Which shift buttons are held in one async notification; null for
/// battery, keep-alive and anything unreadable. A button reads 0 when held.
({bool up, bool down})? parseZwiftShift(Uint8List b) {
  if (b.isEmpty) return null;
  try {
    final f = _varints(b, 1);
    switch (b[0]) {
      case _clickMsg: // field 1 plus, field 2 minus
        return (up: f[1] == 0, down: f[2] == 0);
      case _playMsg: // field 1 says which hand (0 = right), field 6 shoulder
        final shoulder = f[6] == 0;
        final right = f[1] == 0;
        return (up: shoulder && right, down: shoulder && !right);
      // Ride and Click v2: field 1 is a bitmap, a cleared bit a held button.
      // Right-hand shift buttons (0x1000, 0x2000) are harder, left-hand ones
      // (0x0100, 0x0200) easier; confirmed on a Click v2 (0x1000 / 0x0100).
      case _rideMsg:
        final m = f[1];
        if (m == null) return null;
        bool held(int mask) => m & mask == 0;
        return (
          up: held(0x1000) || held(0x2000),
          down: held(0x0100) || held(0x0200),
        );
    }
  } on RangeError {
    // Truncated packet.
  }
  return null;
}

/// The first value of each top-level varint field of a protobuf message.
Map<int, int> _varints(Uint8List b, int i) {
  final out = <int, int>{};
  int read() {
    var v = 0, shift = 0;
    while (true) {
      final x = b[i++];
      v |= (x & 0x7f) << shift;
      if (x < 0x80) return v;
      shift += 7;
    }
  }

  while (i < b.length) {
    final tag = read();
    switch (tag & 7) {
      case 0:
        final v = read();
        out.putIfAbsent(tag >> 3, () => v);
      case 1:
        i += 8;
      case 2:
        final len = read();
        i += len;
      case 5:
        i += 4;
      default:
        return out;
    }
  }
  return out;
}
