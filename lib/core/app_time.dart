// lib/core/app_time.dart
//
// ONE place that decides how a time is shown in the app (point 13):
//   • the super admin sets the platform default timezone + 12h/24h (theme response → [AppTime.configurePlatform]);
//   • an organization admin may override both for their organization ([AppTime.configureOrg] while an org is open,
//     `configureOrg(null, null)` when leaving it).
// The effective setting is org override → platform default → Africa/Cairo, 12-hour.
//
// The server stores naive UTC; read with orgParseUtc()/DateTime.parse(...).toUtc() and show with [AppTime.time],
// [AppTime.date], [AppTime.dateTime]. Timetable periods are wall-clock "HH:MM" strings of the organization — they
// are NOT converted, only formatted ([AppTime.clock] / [AppTime.clockMinutes]).
//
// Digits (M24): ONE system app-wide, the Western digits 0-9, in Arabic too — the clocks, counts, prices and codes
// were already written with them; only intl's Arabic DATES (the symbols flutter_localizations registers) came out
// in Arabic-Indic (أكتوبر ٢٠٢٦ beside 29 30 31). [AppTime.useLatinDigits] switches every DateFormat to ASCII
// digits (main() calls it at start-up; [AppTime.date] makes sure), and [latinDigits] turns a string that already
// holds Arabic-Indic / Persian digits (a server-made title, a pasted value) into the same system.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';
import 'tz_database_io.dart' if (dart.library.js_interop) 'tz_database_web.dart';

/// A selectable timezone. [region] orders the picker: Egypt, Saudi Arabia, UAE, other Arab countries, the world.
class AppZone {
  const AppZone(this.id, this.ar, this.en, this.region);
  final String id; // IANA name
  final String ar;
  final String en;
  final int region; // 0 Egypt · 1 KSA · 2 UAE · 3 Arab world · 4 other
  String get label => AppConfig.lang == 'ar' ? ar : en;
}

class AppTime {
  AppTime._();

  static const String fallbackZone = 'Africa/Cairo';

  /// Picker order is the business rule: Egypt → Saudi Arabia → UAE → other Arab countries → others.
  static const List<AppZone> zones = [
    AppZone('Africa/Cairo', 'مصر (القاهرة)', 'Egypt (Cairo)', 0),
    AppZone('Asia/Riyadh', 'السعودية (الرياض)', 'Saudi Arabia (Riyadh)', 1),
    AppZone('Asia/Dubai', 'الإمارات (دبي)', 'UAE (Dubai)', 2),
    AppZone('Asia/Kuwait', 'الكويت', 'Kuwait', 3),
    AppZone('Asia/Qatar', 'قطر', 'Qatar', 3),
    AppZone('Asia/Bahrain', 'البحرين', 'Bahrain', 3),
    AppZone('Asia/Muscat', 'عُمان', 'Oman', 3),
    AppZone('Asia/Amman', 'الأردن', 'Jordan', 3),
    AppZone('Asia/Beirut', 'لبنان', 'Lebanon', 3),
    AppZone('Asia/Damascus', 'سوريا', 'Syria', 3),
    AppZone('Asia/Baghdad', 'العراق', 'Iraq', 3),
    AppZone('Asia/Gaza', 'فلسطين', 'Palestine', 3),
    AppZone('Asia/Aden', 'اليمن', 'Yemen', 3),
    AppZone('Africa/Khartoum', 'السودان', 'Sudan', 3),
    AppZone('Africa/Tripoli', 'ليبيا', 'Libya', 3),
    AppZone('Africa/Tunis', 'تونس', 'Tunisia', 3),
    AppZone('Africa/Algiers', 'الجزائر', 'Algeria', 3),
    AppZone('Africa/Casablanca', 'المغرب', 'Morocco', 3),
    AppZone('Africa/Nouakchott', 'موريتانيا', 'Mauritania', 3),
    AppZone('Africa/Mogadishu', 'الصومال', 'Somalia', 3),
    AppZone('Africa/Djibouti', 'جيبوتي', 'Djibouti', 3),
    AppZone('Indian/Comoro', 'جزر القمر', 'Comoros', 3),
    AppZone('Europe/Istanbul', 'تركيا', 'Turkey', 4),
    AppZone('Europe/London', 'المملكة المتحدة', 'United Kingdom', 4),
    AppZone('Europe/Berlin', 'وسط أوروبا', 'Central Europe', 4),
    AppZone('America/New_York', 'شرق أمريكا', 'US Eastern', 4),
    AppZone('America/Los_Angeles', 'غرب أمريكا', 'US Pacific', 4),
    AppZone('Asia/Karachi', 'باكستان', 'Pakistan', 4),
    AppZone('Asia/Kolkata', 'الهند', 'India', 4),
    AppZone('Asia/Kuala_Lumpur', 'ماليزيا', 'Malaysia', 4),
    AppZone('UTC', 'التوقيت العالمي (UTC)', 'UTC', 4),
  ];

  static String? _platformZone;
  static bool? _platform24h;
  static String? _orgZone;
  static bool? _org24h;

  /// Bumped whenever the effective setting changes — listen to rebuild time labels.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String get zoneId => _orgZone ?? _platformZone ?? fallbackZone;
  static bool get use24h => _org24h ?? _platform24h ?? false;
  static String get platformZoneId => _platformZone ?? fallbackZone;
  static bool get platformUse24h => _platform24h ?? false;

  static AppZone zoneInfo(String id) =>
      zones.firstWhere((z) => z.id == id, orElse: () => AppZone(id, id, id, 4));

  /// Super-admin default (from the theme / platform settings response). Null keeps the current value.
  static void configurePlatform({String? zone, String? timeFormat}) {
    final z = _valid(zone) ?? _platformZone;
    final f = timeFormat == null ? _platform24h : timeFormat == '24h';
    if (z == _platformZone && f == _platform24h) return;
    _platformZone = z;
    _platform24h = f;
    version.value++;
  }

  /// Organization override while that organization is open. Pass nulls to clear.
  static void configureOrg(String? zone, String? timeFormat) {
    final z = _valid(zone);
    final f = timeFormat == null || timeFormat.isEmpty ? null : timeFormat == '24h';
    if (z == _orgZone && f == _org24h) return;
    _orgZone = z;
    _org24h = f;
    version.value++;
  }

  static String? _valid(String? zone) {
    if (zone == null || zone.isEmpty) return null;
    _ensureDb();
    if (!_tzReady) return zone; // web, data still on its way: checked again in [_tzLoaded]
    try {
      tz.getLocation(zone);
      return zone;
    } catch (_) {
      return null;
    }
  }

  static bool _db = false, _tzReady = false;
  static Future<void>? _tzLoad;

  /// Starts loading the timezone database (a no-op once started). Phone / desktop / tests have it at once; on the
  /// web it is read from `assets/tz/latest.tzf` (see tz_database_web.dart) and every listener of [version] is told
  /// when it lands, so a label drawn before that (device clock) is redrawn in the platform zone.
  static Future<void> loadDatabase() {
    _ensureDb();
    return _tzLoad ??= tzInitAsync().then((_) => _tzLoaded(), onError: (Object _) {
      _tzLoad = null; // retried on the next use
    });
  }

  static void _tzLoaded() {
    final wasReady = _tzReady;
    _tzReady = true;
    if (wasReady) return;
    // zones set before the data arrived were accepted unchecked
    if (_platformZone != null && _valid(_platformZone) == null) _platformZone = null;
    if (_orgZone != null && _valid(_orgZone) == null) _orgZone = null;
    version.value++;
  }

  static void _ensureDb() {
    if (_db) return;
    _db = true;
    try {
      tzInitSync();
      if (!kTzDataIsAsync) _tzReady = true;
      initializeDateFormatting(); // local symbol data loads synchronously; enables Arabic month names
    } catch (_) {}
    useLatinDigits();
    if (kTzDataIsAsync) loadDatabase().ignore();
  }

  /// Every DateFormat made from now on writes Western digits for the Arabic locales (M24). Idempotent.
  static void useLatinDigits() {
    if (!_db) _ensureDb(); // start-up: also starts the timezone data load on the web
    for (final l in const ['ar', 'ar_EG', 'ar_SA', 'ar_AR', 'fa', 'ur']) {
      DateFormat.useNativeDigitsByDefaultFor(l, false);
    }
  }

  /// UTC instant → wall clock of the effective zone (DST aware). Naive input is taken as UTC.
  static DateTime toZone(DateTime utc) {
    _ensureDb();
    final u = utc.isUtc ? utc : DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
    try {
      final t = tz.TZDateTime.from(u, tz.getLocation(zoneId));
      return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    } catch (_) {
      return u.toLocal();
    }
  }

  /// Wall clock of the effective zone → UTC (for sending a picked local time to the server).
  static DateTime fromZone(DateTime wall) {
    _ensureDb();
    try {
      final t = tz.TZDateTime(tz.getLocation(zoneId), wall.year, wall.month, wall.day, wall.hour, wall.minute,
          wall.second);
      return t.toUtc();
    } catch (_) {
      return wall.toUtc();
    }
  }

  static String get _am => AppConfig.lang == 'ar' ? 'ص' : 'AM';
  static String get _pm => AppConfig.lang == 'ar' ? 'م' : 'PM';

  /// Minutes after midnight → "8:30 AM" / "08:30" (follows the effective 12h/24h setting).
  static String clockMinutes(int minutes, {bool? h24}) {
    final m = ((minutes % 1440) + 1440) % 1440;
    final h = m ~/ 60, mm = (m % 60).toString().padLeft(2, '0');
    if (h24 ?? use24h) return '${h.toString().padLeft(2, '0')}:$mm';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$mm ${h < 12 ? _am : _pm}';
  }

  /// "HH:MM" (or "HH:MM:SS") wall-clock string → display. Unparseable input is returned as is.
  static String clock(String? hhmm, {bool? h24}) {
    if (hhmm == null || hhmm.isEmpty) return '';
    final p = hhmm.split(':');
    final h = int.tryParse(p[0].trim());
    final m = p.length > 1 ? int.tryParse(p[1].trim().substring(0, p[1].trim().length.clamp(0, 2))) : 0;
    if (h == null || m == null) return hhmm;
    return clockMinutes(h * 60 + m, h24: h24);
  }

  /// "8:00 – 9:30 AM" style range (drops the repeated AM/PM in 12h mode).
  static String clockRange(String? from, String? to) {
    final a = clock(from), b = clock(to);
    if (a.isEmpty || b.isEmpty) return a.isEmpty ? b : a;
    if (!use24h) {
      final sa = a.split(' '), sb = b.split(' ');
      if (sa.length == 2 && sb.length == 2 && sa[1] == sb[1]) return '${sa[0]} – $b';
    }
    return '$a – $b';
  }

  /// UTC instant → time of day in the effective zone.
  static String time(DateTime utc) {
    final w = toZone(utc);
    return clockMinutes(w.hour * 60 + w.minute);
  }

  /// UTC instant → date in the effective zone ("23 Oct 2026" / "23 أكتوبر 2026").
  static String date(DateTime utc, {String pattern = 'd MMM y'}) {
    final w = toZone(utc); // also loads the timezone + date-symbol data
    try {
      return (DateFormat(pattern, AppConfig.lang)..useNativeDigits = false).format(w);
    } catch (_) {
      return DateFormat(pattern).format(w);
    }
  }

  /// UTC instant → "23 Oct 2026 · 8:30 AM".
  static String dateTime(DateTime utc) => '${date(utc)} · ${time(utc)}';
}

/// [s] with every Arabic-Indic (٠-٩) and Persian (۰-۹) digit written as 0-9: the app's one digit system (M24).
String latinDigits(String s) {
  if (s.isEmpty) return s;
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}
