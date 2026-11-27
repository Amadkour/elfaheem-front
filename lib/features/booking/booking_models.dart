// lib/features/booking/booking_models.dart
//
// Plain values of the booking flow (BookFlow, docs/redesign/api/booking.md and payments.md). Parsed by hand, every
// field optional: an older server answers with fewer keys and nothing breaks. Instants are UTC (`…Z`); the screens
// format them through AppTime. Privacy: a group carries a seat LEVEL (open / few / full), never a count or a name.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';

Map<String, dynamic> bkMap(Object? raw) => raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

List<Map<String, dynamic>> bkMaps(Object? raw) => [
      if (raw is List)
        for (final m in raw)
          if (m is Map) Map<String, dynamic>.from(m),
    ];

int? bkInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? bkNum(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

String? bkStr(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

DateTime? bkUtc(Object? v) {
  final s = bkStr(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
}

/// A name in both languages; [label] picks the app language.
class BkName {
  const BkName({this.id, this.ar, this.en});

  factory BkName.fromJson(Object? raw) {
    final m = bkMap(raw);
    return BkName(id: bkInt(m['id']), ar: bkStr(m['name_ar']), en: bkStr(m['name_en']));
  }

  final int? id;
  final String? ar, en;

  String get label => (AppConfig.lang == 'ar' ? (ar ?? en) : (en ?? ar)) ?? '';
}

/// The list separator of the app language: "، " in Arabic, ", " in English (no Arabic comma in an English line).
String get bkComma => AppConfig.lang == 'ar' ? '، ' : ', ';

/// "199 ريال" / "SAR 199". The currency comes from the server; nothing here assumes one.
String bkMoney(num amount, String? currency) {
  final n = amount == amount.truncate() ? '${amount.toInt()}' : amount.toStringAsFixed(2);
  final code = (currency ?? '').trim().toUpperCase();
  if (AppConfig.lang == 'ar') {
    final word = switch (code) {
      'SAR' => 'ريال',
      'EGP' => 'جنيه',
      'AED' => 'درهم',
      'KWD' => 'دينار',
      'BHD' => 'دينار',
      'QAR' => 'ريال قطري',
      'OMR' => 'ريال عماني',
      'JOD' => 'دينار',
      '' => '',
      _ => code,
    };
    return appDigits(word.isEmpty ? n : '$n $word');
  }
  if (code == 'USD') return '\$$n';
  return code.isEmpty ? n : '$code $n';
}

class BkTeacher {
  const BkTeacher({required this.userId, required this.name, this.gender, this.avatarUrl});

  static BkTeacher? fromJson(Object? raw) {
    final m = bkMap(raw);
    if (m.isEmpty) return null;
    return BkTeacher(
      userId: bkInt(m['user_id'] ?? m['id']) ?? 0,
      name: bkStr(m['name']) ?? '',
      gender: bkStr(m['gender']),
      avatarUrl: bkStr(m['avatar_url']),
    );
  }

  final int userId;
  final String name;
  final String? gender, avatarUrl;
}

/// `remote` | `in_person`, `group` | `individual`: available or not, and why.
class BkChoice {
  const BkChoice({required this.key, this.available = true, this.reason, this.prices = const {}});

  factory BkChoice.fromJson(Map<String, dynamic> m) => BkChoice(
        key: bkStr(m['key']) ?? '',
        available: m['available'] != false,
        reason: bkStr(m['reason']),
        prices: {
          for (final e in bkMap(m['prices']).entries)
            if (bkNum(e.value) != null) e.key: bkNum(e.value)!,
        },
      );

  final String key;
  final bool available;
  final String? reason;

  /// kinds only: mode → monthly price.
  final Map<String, double> prices;
}

/// GET /booking/options.
class BkOptions {
  const BkOptions({
    this.subject = const BkName(),
    this.grade = const BkName(),
    this.classMinutes = 50,
    this.groupMin = 5,
    this.groupMax = 10,
    this.gender,
    this.currency,
    this.modes = const [],
    this.kinds = const [],
    this.proposals = false,
    this.proposalHours = 24,
  });

  factory BkOptions.fromJson(Object? raw) {
    final m = bkMap(raw);
    final size = bkMap(m['group_size']);
    return BkOptions(
      subject: BkName.fromJson(m['subject']),
      grade: BkName.fromJson(m['grade']),
      classMinutes: bkInt(m['class_minutes']) ?? 50,
      groupMin: bkInt(size['min']) ?? 5,
      groupMax: bkInt(size['max']) ?? 10,
      gender: bkStr(m['gender']),
      currency: bkStr(m['currency']),
      modes: [for (final x in bkMaps(m['modes'])) BkChoice.fromJson(x)],
      kinds: [for (final x in bkMaps(m['kinds'])) BkChoice.fromJson(x)],
      proposals: m['proposals'] == true,
      proposalHours: bkInt(m['proposal_hours']) ?? 24,
    );
  }

  final BkName subject, grade;
  final int classMinutes, groupMin, groupMax;

  /// `boys` | `girls`; null = unknown (asked before the groups are listed).
  final String? gender;
  final String? currency;
  final List<BkChoice> modes, kinds;
  final bool proposals;
  final int proposalHours;

  BkChoice? mode(String key) => modes.where((m) => m.key == key).firstOrNull;
  BkChoice? kind(String key) => kinds.where((k) => k.key == key).firstOrNull;

  /// The modes the student can pick (an unavailable one is hidden, RULES §3 "Location").
  List<BkChoice> get openModes => [for (final m in modes) if (m.available) m];
  List<BkChoice> get openKinds => [for (final k in kinds) if (k.available) k];

  double? price(String kind, String mode) => this.kind(kind)?.prices[mode];
}

class BkCentre {
  const BkCentre({required this.id, required this.name, this.address});

  factory BkCentre.fromJson(Map<String, dynamic> m) => BkCentre(
        id: bkInt(m['id']) ?? 0,
        name: BkName.fromJson(m),
        address: BkName(ar: bkStr(m['address_ar']), en: bkStr(m['address_en'])),
      );

  final int id;
  final BkName name;
  final BkName? address;
}

class BkDistrict {
  const BkDistrict({this.id, required this.name, this.centres = const []});

  factory BkDistrict.fromJson(Map<String, dynamic> m) => BkDistrict(
        id: bkInt(m['id']),
        name: BkName.fromJson(m),
        centres: [for (final c in bkMaps(m['centres'])) BkCentre.fromJson(c)],
      );

  final int? id;
  final BkName name;
  final List<BkCentre> centres;
}

class BkCity {
  const BkCity({required this.id, required this.name, this.districts = const []});

  factory BkCity.fromJson(Map<String, dynamic> m) => BkCity(
        id: bkInt(m['id']) ?? 0,
        name: BkName.fromJson(m),
        districts: [for (final d in bkMaps(m['districts'])) BkDistrict.fromJson(d)],
      );

  final int id;
  final BkName name;
  final List<BkDistrict> districts;
}

/// GET /booking/centres: only places with an active centre.
class BkCentres {
  const BkCentres({this.hereCityId, this.cities = const []});

  factory BkCentres.fromJson(Object? raw) {
    final m = bkMap(raw);
    return BkCentres(
      hereCityId: bkInt(m['here_city_id']),
      cities: [for (final c in bkMaps(m['cities'])) BkCity.fromJson(c)],
    );
  }

  final int? hereCityId;
  final List<BkCity> cities;
}

/// A group's place in the calendar: its label, weekdays and weekly instants.
class BkGroupWhen {
  const BkGroupWhen({required this.id, this.label = '', this.weekdays = const [], this.times = const [], this.startsAt});

  static BkGroupWhen? fromJson(Object? raw) {
    final m = bkMap(raw);
    if (m.isEmpty) return null;
    return BkGroupWhen(
      id: bkInt(m['id']) ?? 0,
      label: bkStr(m['label']) ?? '',
      weekdays: [for (final d in (m['weekdays'] is List ? m['weekdays'] as List : const [])) ?bkInt(d)],
      times: [for (final t in (m['times'] is List ? m['times'] as List : const [])) ?bkUtc(t)],
      startsAt: bkUtc(m['starts_at']),
    );
  }

  final int id;
  final String label;
  final List<int> weekdays;

  /// One weekly instant per weekday, UTC; ordered here by the weekday they fall on.
  final List<DateTime> times;
  final DateTime? startsAt;
}

/// One group of GET /booking/groups.
class BkGroup extends BkGroupWhen {
  const BkGroup({
    required super.id,
    super.label,
    super.weekdays,
    super.times,
    super.startsAt,
    this.gender,
    this.mode,
    this.centre,
    this.teacher,
    this.availability = 'open',
    this.price,
    this.currency,
    this.mineStatus,
  });

  factory BkGroup.fromJson(Map<String, dynamic> m) {
    final w = BkGroupWhen.fromJson(m)!;
    final c = bkMap(m['centre']);
    return BkGroup(
      id: w.id,
      label: w.label,
      weekdays: w.weekdays,
      times: w.times,
      startsAt: w.startsAt,
      gender: bkStr(m['gender']),
      mode: bkStr(m['mode']),
      centre: c.isEmpty ? null : BkCentre.fromJson(c),
      teacher: BkTeacher.fromJson(m['teacher']),
      availability: bkStr(m['availability']) ?? 'open',
      price: bkNum(m['price']),
      currency: bkStr(m['currency']),
      mineStatus: bkStr(bkMap(m['mine'])['status']),
    );
  }

  final String? gender, mode;
  final BkCentre? centre;
  final BkTeacher? teacher;

  /// `open` (متاح) · `few` (آخر مقاعد) · `full` (مكتمل).
  final String availability;
  final double? price;
  final String? currency;

  /// The student's own booking of this group (`waitlisted`, `active` …), or null.
  final String? mineStatus;

  bool get full => availability == 'full';
}

class BkGroups {
  const BkGroups({this.single = false, this.items = const []});

  factory BkGroups.fromJson(Object? raw) {
    final m = bkMap(raw);
    return BkGroups(single: m['single'] == true, items: [for (final g in bkMaps(m['items'])) BkGroup.fromJson(g)]);
  }

  /// Exactly one group: the "هذا موعد المجموعة" screen.
  final bool single;
  final List<BkGroup> items;
}

class BkSlot {
  const BkSlot({required this.id, required this.startsAt, this.weekly = true});

  static BkSlot? fromJson(Map<String, dynamic> m) {
    final at = bkUtc(m['starts_at']);
    if (at == null) return null;
    return BkSlot(id: bkInt(m['id']) ?? 0, startsAt: at, weekly: m['weekly'] != false);
  }

  final int id;
  final DateTime startsAt;
  final bool weekly;
}

/// One teacher's free weekly slots (GET /booking/slots).
class BkSlotTeacher {
  const BkSlotTeacher({required this.teacher, this.price, this.currency, this.slots = const []});

  factory BkSlotTeacher.fromJson(Map<String, dynamic> m) => BkSlotTeacher(
        teacher: BkTeacher.fromJson(m['teacher']) ?? const BkTeacher(userId: 0, name: ''),
        price: bkNum(m['price']),
        currency: bkStr(m['currency']),
        slots: [for (final s in bkMaps(m['slots'])) ?BkSlot.fromJson(s)],
      );

  final BkTeacher teacher;
  final double? price;
  final String? currency;
  final List<BkSlot> slots;
}

/// "وش الأوقات اللي تناسبك؟": Python weekday numbers (Monday 0 … Sunday 6), periods, the viewer's zone.
class BkProposal {
  const BkProposal({required this.weekdays, required this.periods, required this.tz});

  static BkProposal? fromJson(Object? raw) {
    final m = bkMap(raw);
    if (m.isEmpty) return null;
    return BkProposal(
      weekdays: [for (final d in (m['weekdays'] is List ? m['weekdays'] as List : const [])) ?bkInt(d)],
      periods: [for (final p in (m['periods'] is List ? m['periods'] as List : const [])) '$p'],
      tz: bkStr(m['tz']) ?? '',
    );
  }

  final List<int> weekdays;
  final List<String> periods;
  final String tz;

  Map<String, dynamic> toJson() => {'weekdays': weekdays, 'periods': periods, 'tz': tz};
}

/// The body of quote / confirm.
class BkRequest {
  const BkRequest({
    required this.subjectId,
    required this.gradeId,
    required this.mode,
    required this.kind,
    this.centreId,
    this.details,
    this.groupId,
    this.slotIds = const [],
    this.proposal,
    this.gender,
  });

  final int subjectId, gradeId;
  final String mode, kind;
  final int? centreId, groupId;
  final String? details, gender;
  final List<int> slotIds;
  final BkProposal? proposal;

  Map<String, dynamic> toJson() => {
        'subject_id': subjectId,
        'grade_id': gradeId,
        'mode': mode,
        'centre_id': centreId,
        'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
        'kind': kind,
        if (kind == 'group') 'group_id': groupId,
        if (kind == 'individual' && proposal == null) 'slot_ids': slotIds,
        if (kind == 'individual' && proposal != null) 'proposal': proposal!.toJson(),
        if (gender != null) 'gender': gender,
      };
}

/// POST /booking/quote.
class BkQuote {
  const BkQuote({
    this.teacher,
    this.group,
    this.slots = const [],
    this.proposal,
    this.price,
    this.currency,
    this.payNow = true,
    this.providers = const [],
  });

  factory BkQuote.fromJson(Object? raw) {
    final m = bkMap(raw);
    return BkQuote(
      teacher: BkTeacher.fromJson(m['teacher']),
      group: BkGroupWhen.fromJson(m['group']),
      slots: [for (final s in bkMaps(m['slots'])) ?BkSlot.fromJson(s)],
      proposal: BkProposal.fromJson(m['proposal']),
      price: bkNum(m['price']),
      currency: bkStr(m['currency']),
      payNow: m['pay_now'] != false,
      providers: [for (final p in (m['providers'] is List ? m['providers'] as List : const [])) '$p'],
    );
  }

  final BkTeacher? teacher;
  final BkGroupWhen? group;
  final List<BkSlot> slots;
  final BkProposal? proposal;
  final double? price;
  final String? currency;

  /// False for a proposal: paid once the team fixes the time.
  final bool payNow;
  final List<String> providers;
}

/// One booking (BookingView).
class BkBooking {
  const BkBooking({
    required this.id,
    this.kind = 'group',
    this.mode = 'remote',
    this.status = '',
    this.subject = const BkName(),
    this.grade = const BkName(),
    this.centre,
    this.teacher,
    this.group,
    this.slots = const [],
    this.proposal,
    this.nextClassAt,
    this.classMinutes = 50,
    this.price,
    this.currency,
    this.holdUntil,
    this.checkoutUrl,
  });

  factory BkBooking.fromJson(Object? raw) {
    final m = bkMap(raw);
    final c = bkMap(m['centre']);
    final co = bkMap(m['checkout']);
    return BkBooking(
      id: bkInt(m['id']) ?? 0,
      kind: bkStr(m['kind']) ?? 'group',
      mode: bkStr(m['mode']) ?? 'remote',
      status: bkStr(m['status']) ?? '',
      subject: BkName.fromJson(m['subject']),
      grade: BkName.fromJson(m['grade']),
      centre: c.isEmpty ? null : BkCentre.fromJson(c),
      teacher: BkTeacher.fromJson(m['teacher']),
      group: BkGroupWhen.fromJson(m['group']),
      slots: [for (final s in bkMaps(m['slots'])) ?BkSlot.fromJson(s)],
      proposal: BkProposal.fromJson(m['proposal']),
      nextClassAt: bkUtc(m['next_class_at']),
      classMinutes: bkInt(m['class_minutes']) ?? 50,
      price: bkNum(m['price']),
      currency: bkStr(m['currency']),
      holdUntil: bkUtc(m['hold_until']),
      checkoutUrl: bkStr(co['url'] ?? co['checkout_url']),
    );
  }

  final int id;
  final String kind, mode;

  /// proposed | scheduled | pending_payment | active | waitlisted | offered | expired | cancelled | declined | notify
  final String status;
  final BkName subject, grade;
  final BkCentre? centre;
  final BkTeacher? teacher;
  final BkGroupWhen? group;
  final List<BkSlot> slots;
  final BkProposal? proposal;
  final DateTime? nextClassAt;
  final int classMinutes;
  final double? price;
  final String? currency;
  final DateTime? holdUntil;
  final String? checkoutUrl;

  bool get active => status == 'active';
  bool get payable => const {'scheduled', 'pending_payment', 'offered'}.contains(status);

  /// Still the student's: not cancelled, expired or declined.
  bool get live => !const {'cancelled', 'expired', 'declined', ''}.contains(status);
}

/// The open checkout of a confirm / pay answer.
class BkConfirmResult {
  const BkConfirmResult({required this.booking, this.checkoutUrl});

  factory BkConfirmResult.fromJson(Object? raw) {
    final m = bkMap(raw);
    final co = bkMap(m['checkout']);
    return BkConfirmResult(booking: BkBooking.fromJson(m['booking']), checkoutUrl: bkStr(co['url'] ?? co['checkout_url']));
  }

  final BkBooking booking;
  final String? checkoutUrl;

  bool get canOpen => checkoutUrl != null && checkoutUrl!.startsWith('https://');
}

/// One method of GET /payments/methods, in the server's order.
class BkPayMethod {
  const BkPayMethod({required this.key, required this.label, this.kind = 'card', this.flow = 'card', this.brands = const []});

  factory BkPayMethod.fromJson(Map<String, dynamic> m) => BkPayMethod(
        key: bkStr(m['key']) ?? '',
        label: bkStr(m['label']) ?? bkStr(m['key']) ?? '',
        kind: bkStr(m['kind']) ?? 'card',
        flow: bkStr(m['flow']) ?? 'card',
        brands: [for (final b in (m['brands'] is List ? m['brands'] as List : const [])) '$b'],
      );

  final String key, label, kind, flow;
  final List<String> brands;
}

/// GET /payments/methods: what this payer can use, VAT and the "≈" amount.
class BkPayInfo {
  const BkPayInfo({
    this.provider,
    this.chargeCurrency,
    this.methods = const [],
    this.vatApplies = false,
    this.vatLabel,
    this.approx,
    this.approxNote,
    this.chargeNote,
  });

  factory BkPayInfo.fromJson(Object? raw) {
    final m = bkMap(raw);
    final vat = bkMap(m['vat']);
    final d = bkMap(m['display']);
    final approx = bkNum(d['approx_amount']);
    return BkPayInfo(
      provider: bkStr(m['provider']),
      chargeCurrency: bkStr(m['charge_currency']),
      methods: [for (final x in bkMaps(m['methods'])) BkPayMethod.fromJson(x)],
      vatApplies: vat['applies'] == true,
      vatLabel: bkStr(vat['label']),
      approx: approx == null ? null : bkMoney(approx, bkStr(d['currency'])),
      approxNote: bkStr(d['note']),
      chargeNote: bkStr(m['charge_note']),
    );
  }

  final String? provider, chargeCurrency;
  final List<BkPayMethod> methods;
  final bool vatApplies;
  final String? vatLabel;

  /// "≈ 1,320 جنيه" when the payer's currency differs; null otherwise.
  final String? approx;
  final String? approxNote, chargeNote;

  /// The methods the booking checkout can take (a card or a wallet on the gateway's page; a bank transfer is not a
  /// booking flow).
  List<BkPayMethod> get bookable => [for (final x in methods) if (x.flow != 'manual') x];
}
