// The Downloads page exists in the phone / desktop app only: every way a link can name it is recognised, so the
// web can refuse it (lib/core/offline/downloads_availability.dart).
import 'package:flutter_education_app/core/offline/downloads_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a route, a module or a link with a query all name the Downloads page', () {
    for (final s in ['/downloads', 'downloads', ' /downloads/ ', '/downloads?tab=attendance', 'downloads#x', '//downloads']) {
      expect(isDownloadsLink(s), isTrue, reason: s);
    }
    for (final s in [null, '', '/', '/download', '/downloads-old', '/profile', 'calendar', '/c/12?ref=downloads']) {
      expect(isDownloadsLink(s), isFalse, reason: '$s');
    }
  });

  test('on the web (no downloads) only the Downloads link is refused', () {
    expect(linkAvailableHere('/downloads', downloadsAvailable: false), isFalse);
    expect(linkAvailableHere('downloads', downloadsAvailable: false), isFalse);
    expect(linkAvailableHere('/notifications', downloadsAvailable: false), isTrue);
    expect(linkAvailableHere(null, downloadsAvailable: false), isTrue);
    expect(linkAvailableHere('/downloads', downloadsAvailable: true), isTrue);
  });

  test('the test VM is not the web: downloads exist here', () {
    expect(kDownloadsAvailable, isTrue);
  });
}
