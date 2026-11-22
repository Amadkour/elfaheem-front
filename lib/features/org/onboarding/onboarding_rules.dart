// lib/features/org/onboarding/onboarding_rules.dart — the pure rules of member onboarding (D-1200..D-1207).
//
// The Dart mirror of the back end's `features/org/onboarding/validation.py` (contract §5): what the wizard checks
// while the person types, so a mistake is shown before the server is asked. The server stays the judge.
//   parseEgyptianNid    14-digit national ID → birth date, gender, governorate (or an error code)
//   normalizeDigits     Arabic-Indic / Persian digits → Latin, spaces and dashes dropped
//   normalizeNidPhone   an Egyptian mobile or an E.164 number, else null
//   validPassport       5–20 letters / digits
//   normalizeArName     the search form of a name (alef / ta marbuta / ya unified, tatweel and marks dropped)
//   whenMatches         the `when` evaluator of fields and documents
//   ageOn               full years on a day
//   onbIsRequired       is a field / document required for these values?
//   computeMissing      which required fields and documents are still empty
library;

import 'onboarding_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Digits and national ID
// ═════════════════════════════════════════════════════════════════════════════

/// Arabic-Indic (٠-٩) and Persian (۰-۹) digits as Latin ones.
String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 0x30);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 0x30);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// The governorate codes of an Egyptian national ID (digits 8-9).
const egyptGovernorates = <String, ({String ar, String en})>{
  '01': (ar: 'القاهرة', en: 'Cairo'),
  '02': (ar: 'الإسكندرية', en: 'Alexandria'),
  '03': (ar: 'بورسعيد', en: 'Port Said'),
  '04': (ar: 'السويس', en: 'Suez'),
  '11': (ar: 'دمياط', en: 'Damietta'),
  '12': (ar: 'الدقهلية', en: 'Dakahlia'),
  '13': (ar: 'الشرقية', en: 'Sharqia'),
  '14': (ar: 'القليوبية', en: 'Qalyubia'),
  '15': (ar: 'كفر الشيخ', en: 'Kafr El Sheikh'),
  '16': (ar: 'الغربية', en: 'Gharbia'),
  '17': (ar: 'المنوفية', en: 'Monufia'),
  '18': (ar: 'البحيرة', en: 'Beheira'),
  '19': (ar: 'الإسماعيلية', en: 'Ismailia'),
  '21': (ar: 'الجيزة', en: 'Giza'),
  '22': (ar: 'بني سويف', en: 'Beni Suef'),
  '23': (ar: 'الفيوم', en: 'Faiyum'),
  '24': (ar: 'المنيا', en: 'Minya'),
  '25': (ar: 'أسيوط', en: 'Asyut'),
  '26': (ar: 'سوهاج', en: 'Sohag'),
  '27': (ar: 'قنا', en: 'Qena'),
  '28': (ar: 'أسوان', en: 'Aswan'),
  '29': (ar: 'الأقصر', en: 'Luxor'),
  '31': (ar: 'البحر الأحمر', en: 'Red Sea'),
  '32': (ar: 'الوادي الجديد', en: 'New Valley'),
  '33': (ar: 'مطروح', en: 'Matrouh'),
  '34': (ar: 'شمال سيناء', en: 'North Sinai'),
  '35': (ar: 'جنوب سيناء', en: 'South Sinai'),
  '88': (ar: 'خارج الجمهورية', en: 'Born abroad'),
};

/// What a valid national ID says: the birth day, `m` | `f` and the governorate code.
class NidInfo {
  const NidInfo(this.birthDate, this.gender, this.governorate);
  final DateTime birthDate;
  final String gender;
  final String governorate;

  /// `yyyy-MM-dd`, the form the server takes.
  String get birthIso => isoDate(birthDate);
}

/// The result of [parseEgyptianNid]: [info] on success, else [error] = `nid_format` | `nid_date` | `nid_gov`.
class NidResult {
  const NidResult.ok(NidInfo this.info) : error = null;
  const NidResult.fail(String this.error) : info = null;
  final NidInfo? info;
  final String? error;
  bool get ok => info != null;
}

/// The digits of a typed ID: Latin digits only, spaces / dashes dropped.
String cleanNid(String raw) => normalizeDigits(raw).replaceAll(RegExp(r'[\s\-‎‏]'), '');

/// Contract §5: 14 digits; the century digit 2 → 1900, 3 → 2000; YYMMDD a real day not in the future; a known
/// governorate; gender from digit 13 (odd → m). The check digit is NOT enforced (D-1206). [now] is for tests.
NidResult parseEgyptianNid(String raw, {DateTime? now}) {
  final s = cleanNid(raw);
  if (!RegExp(r'^\d{14}$').hasMatch(s)) return const NidResult.fail('nid_format');
  final century = s[0];
  if (century != '2' && century != '3') return const NidResult.fail('nid_format');
  final year = (century == '2' ? 1900 : 2000) + int.parse(s.substring(1, 3));
  final month = int.parse(s.substring(3, 5));
  final day = int.parse(s.substring(5, 7));
  final d = DateTime(year, month, day);
  if (d.year != year || d.month != month || d.day != day) return const NidResult.fail('nid_date');
  final today = now ?? DateTime.now();
  if (d.isAfter(DateTime(today.year, today.month, today.day))) return const NidResult.fail('nid_date');
  final gov = s.substring(7, 9);
  if (!egyptGovernorates.containsKey(gov)) return const NidResult.fail('nid_gov');
  final gender = int.parse(s[12]).isOdd ? 'm' : 'f';
  return NidResult.ok(NidInfo(d, gender, gov));
}

/// The bilingual text of a national-ID error code.
({String ar, String en}) nidErrorText(String code) => switch (code) {
      'nid_date' => (ar: 'تاريخ الميلاد داخل الرقم القومي غير صحيح', en: 'The birth date inside the national ID is not valid'),
      'nid_gov' => (ar: 'كود المحافظة داخل الرقم القومي غير صحيح', en: 'The governorate code inside the national ID is not valid'),
      _ => (ar: 'الرقم القومي يتكون من 14 رقماً', en: 'A national ID has 14 digits'),
    };

/// A passport number: 5–20 letters or digits.
bool validPassport(String raw) => RegExp(r'^[A-Za-z0-9]{5,20}$').hasMatch(raw.trim());

// ═════════════════════════════════════════════════════════════════════════════
//  Phone, e-mail, names
// ═════════════════════════════════════════════════════════════════════════════

/// An Egyptian mobile (`01[0125]` + 8 digits, with +20 / 0020 / 20 accepted) as typed locally (`01xxxxxxxxx`), or an
/// international number as `+digits` (8–15 digits); null when it is neither.
String? normalizeContactPhone(String raw) {
  var s = normalizeDigits(raw).replaceAll(RegExp(r'[\s\-().‎‏]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('0020')) {
    s = '+${s.substring(2)}';
  } else if (s.startsWith('00')) {
    s = '+${s.substring(2)}';
  }
  if (s.startsWith('+20') && RegExp(r'^\+20\d{10}$').hasMatch(s)) s = '0${s.substring(3)}';
  if (RegExp(r'^1[0125]\d{8}$').hasMatch(s)) s = '0$s';
  if (RegExp(r'^01[0125]\d{8}$').hasMatch(s)) return s;
  if (RegExp(r'^\+\d{8,15}$').hasMatch(s)) return s;
  return null;
}

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// A plausible e-mail address (the server re-checks).
bool validEmail(String raw) => _emailRe.hasMatch(raw.trim());

/// The search form of an Arabic name (the same steps as the server's `normalize_ar_name`): أإآٱ → ا, ة → ه, ى → ي,
/// ؤ → و, ئ → ي; tatweel and diacritics dropped; spaces collapsed; `عبد ال…` → `عبدال…`; Latin lower-cased.
String normalizeArName(String raw) {
  var s = raw.replaceAll(RegExp('[ً-ٰٟـ]'), '');
  s = s
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp('عبد ال'), 'عبدال');
  return s.toLowerCase();
}

// ═════════════════════════════════════════════════════════════════════════════
//  Dates and age
// ═════════════════════════════════════════════════════════════════════════════

/// `yyyy-MM-dd`.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A `yyyy-MM-dd` (or longer ISO) string as a calendar day; null when it is not one.
DateTime? parseIsoDay(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Full years between [birth] and [on] (today by default).
int ageOn(DateTime birth, {DateTime? on}) {
  final d = on ?? DateTime.now();
  var a = d.year - birth.year;
  if (d.month < birth.month || (d.month == birth.month && d.day < birth.day)) a--;
  return a;
}

// ═════════════════════════════════════════════════════════════════════════════
//  `when`, required, missing
// ═════════════════════════════════════════════════════════════════════════════

/// Does [v] hold a value? `false` and 0 count as empty only for text / lists; a checkbox counts when true.
bool hasValue(Object? v) {
  if (v == null) return false;
  if (v is String) return v.trim().isNotEmpty;
  if (v is Iterable) return v.isNotEmpty;
  if (v is bool) return v;
  return true;
}

/// Every key of [when] must match [values] (contract §2). `gender` and `nationality` compare as strings
/// (`nationality: "!EG"` = anyone not Egyptian); `age_min` / `age_max` use `birth_date` and do not match without it;
/// any other key is a plain equality. An empty or null [when] always matches.
bool whenMatches(Map<String, dynamic>? when, Map<String, dynamic> values, {DateTime? now}) {
  if (when == null || when.isEmpty) return true;
  for (final e in when.entries) {
    final k = e.key, want = e.value;
    switch (k) {
      case 'age_min':
      case 'age_max':
        final b = parseIsoDay(values['birth_date']);
        if (b == null) return false;
        final a = ageOn(b, on: now);
        final lim = want is num ? want.toInt() : int.tryParse('$want');
        if (lim == null) return false;
        if (k == 'age_min' ? a < lim : a > lim) return false;
      default:
        final have = '${values[k] ?? ''}';
        final w = '$want';
        if (w.startsWith('!')) {
          if (have.isEmpty || have.toUpperCase() == w.substring(1).toUpperCase()) return false;
        } else if (have.toUpperCase() != w.toUpperCase()) {
          return false;
        }
    }
  }
  return true;
}

/// Is a field or document of this [required] level and [when] required for [values]?
/// mandatory → yes (unless its `when` says it does not apply); conditional → only when its `when` matches;
/// optional → never.
bool onbIsRequired(String required, Map<String, dynamic>? when, Map<String, dynamic> values, {DateTime? now}) {
  switch (required) {
    case 'mandatory':
      return whenMatches(when, values, now: now);
    case 'conditional':
      return when != null && when.isNotEmpty && whenMatches(when, values, now: now);
    default:
      return false;
  }
}

/// Is the field shown for [values]? A field with a `when` shows only while it matches.
bool fieldVisible(OnbField f, Map<String, dynamic> values, {DateTime? now}) => whenMatches(f.when, values, now: now);

/// Is the document asked for these [values]?
bool docVisible(OnbDocReq d, Map<String, dynamic> values, {DateTime? now}) => whenMatches(d.when, values, now: now);

/// What is still empty: the required fields, the required documents with no usable file, and which of those
/// documents may be brought later (`allow_later`).
class OnbMissing {
  const OnbMissing({this.fields = const [], this.documents = const [], this.later = const []});
  final List<String> fields;
  final List<String> documents;

  /// The subset of [documents] whose requirement has `allow_later`.
  final List<String> later;

  /// Documents that block a submission (missing and not allowed later).
  List<String> get blockingDocuments => documents.where((k) => !later.contains(k)).toList();

  bool get isEmpty => fields.isEmpty && documents.isEmpty;

  /// Nothing blocks a submission: only `allow_later` documents may be missing.
  bool get canSubmit => fields.isEmpty && blockingDocuments.isEmpty;
}

/// A document counts as present when a file is on record that was not rejected (`waived` and `deferred` count:
/// somebody decided it may wait or is not needed).
bool docPresent(OnbDocRecord? r) => r != null && r.status != 'rejected';

/// The missing items of a case: required (and visible) fields with no value, required documents with no usable
/// file. [docs] are the current records; [laterKeys] are documents the person said they will bring later.
OnbMissing computeMissing(OnbType type, Map<String, dynamic> values, List<OnbDocRecord> docs,
    {Set<String> laterKeys = const {}, DateTime? now}) {
  final fields = <String>[];
  for (final f in type.fields) {
    if (!fieldVisible(f, values, now: now)) continue;
    if (onbIsRequired(f.required, f.when, values, now: now) && !hasValue(values[f.key])) fields.add(f.key);
  }
  final byKey = <String, OnbDocRecord>{for (final d in docs) d.reqKey: d};
  final missing = <String>[], later = <String>[];
  for (final d in type.documents) {
    if (!onbIsRequired(d.required, d.when, values, now: now)) continue;
    if (docPresent(byKey[d.key])) continue;
    missing.add(d.key);
    if (d.allowLater) later.add(d.key);
  }
  return OnbMissing(fields: fields, documents: missing, later: later);
}

/// What the national ID fills in on the form: `birth_date` and `gender` (system fields), and the governorate for
/// display. Empty for an invalid ID.
Map<String, String> prefillFromNid(String raw, {DateTime? now}) {
  final r = parseEgyptianNid(raw, now: now);
  final i = r.info;
  if (i == null) return const {};
  return {'birth_date': i.birthIso, 'gender': i.gender, 'governorate': i.governorate};
}
