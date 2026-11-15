import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/update.dart';

void main() {
  test('isNewer compares x.y.z numerically and ignores +build', () {
    expect(isNewer('0.3.1', '0.3.0'), isTrue);
    expect(isNewer('0.10.0', '0.9.9'), isTrue);
    expect(isNewer('0.3.1', '0.3.1+4'), isFalse);
    expect(isNewer('0.3.0', '0.3.1'), isFalse);
  });

  test('parseRelease picks the windows zip and strips the v', () {
    final u = parseRelease({
      'tag_name': 'v0.3.1',
      'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
        {
          'name': 'indoor_cycling-v0.3.1-windows.zip',
          'browser_download_url': 'https://x/w.zip'
        },
      ],
    })!;
    expect(u.version, '0.3.1');
    expect(u.zip.toString(), 'https://x/w.zip');
    expect(parseRelease({'tag_name': 'v1.0.0', 'assets': []}), isNull);
  });
}
