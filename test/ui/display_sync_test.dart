// Display & reading account sync: which copy wins, and how server times are read (display_sync.dart).
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/core/display/display_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 28, 10);
  final t1 = DateTime.utc(2026, 10, 28, 11);
  const big = DisplayPrefs(textScale: 1.3);
  const bold = DisplayPrefs(boldText: true);

  DisplaySyncAction decide(DisplayPrefs local, DateTime? localAt, DisplayPrefs? remote, DateTime? remoteAt) =>
      displaySyncDecision(local: local, localAt: localAt, remote: remote, remoteAt: remoteAt);

  test('nothing on the account: push what the device chose, nothing for an untouched device', () {
    expect(decide(big, t0, null, null), DisplaySyncAction.pushLocal);
    expect(decide(const DisplayPrefs(), null, null, null), DisplaySyncAction.none);
    // reset to the defaults on purpose is still a choice worth keeping
    expect(decide(const DisplayPrefs(), t0, null, null), DisplaySyncAction.pushLocal);
  });

  test('the newer copy wins; a fresh device takes the account', () {
    expect(decide(big, t1, bold, t0), DisplaySyncAction.pushLocal);
    expect(decide(big, t0, bold, t1), DisplaySyncAction.applyRemote);
    expect(decide(const DisplayPrefs(), null, bold, t0), DisplaySyncAction.applyRemote);
    expect(decide(big, t0, big, t1), DisplaySyncAction.none);
    expect(decide(big, t0, bold, null), DisplaySyncAction.pushLocal); // an account copy without a time is older
  });

  test('server times are naive UTC', () {
    expect(parseServerUtc('2026-10-28T10:00:00'), t0);
    expect(parseServerUtc('2026-10-28T12:00:00+02:00'), t0);
    expect(parseServerUtc('2026-10-28T10:00:00Z'), t0);
    expect(parseServerUtc(null), isNull);
    expect(parseServerUtc('null'), isNull);
  });

  test('the wire payload survives a round trip', () {
    const p = DisplayPrefs(arabicFont: 'baloo', latinFont: 'lexend', textScale: 1.1, spacing: 2, reduceMotion: true);
    expect(DisplayPrefs.fromJson(Map<String, dynamic>.from(p.toJson())), p);
  });
}
