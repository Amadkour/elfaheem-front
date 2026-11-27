// lib/features/booking/booking_flow_controller.dart
//
// The booking flow's state (BookFlow): what the student picked in each step, the server's lists, and the move to
// the next step. One controller per flow, owned by the page (not a global provider). The picks survive a sign-in in
// between (4ب "حجزك محفوظ لين تكمّل"): [saveDraft] before leaving for the sign-in page, [restoreDraft] when the
// flow opens again for the same subject and grade.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';

/// The proposal's periods, in the order the design lists them, with their local hours (start, end).
const List<(String, int, int)> kBkPeriods = [
  ('morning', 9 * 60, 12 * 60),
  ('afternoon', 15 * 60, 17 * 60),
  ('evening', 19 * 60 + 30, 21 * 60),
  ('night', 21 * 60, 23 * 60),
];

const String _kDraftKey = 'bk_draft_v1';

class BkFlowController extends ChangeNotifier {
  BkFlowController({
    required this.subjectId,
    required this.gradeId,
    this.subjectTitle,
    this.gradeTitle,
    this.subjectKey,
    this.courseId,
    BookingApi? api,
  }) : api = api ?? BookingApi();

  final int subjectId, gradeId;

  /// Shown before the options arrive.
  final String? subjectTitle, gradeTitle;

  /// The server subject (slug or name) for the book's colour.
  final String? subjectKey;

  /// The course page the flow was opened from (the sign-in resumes it).
  final String? courseId;
  final BookingApi api;

  // ── where we are ──────────────────────────────────────────────────────────
  /// 1 how · 2 group or individual · 3 the time · 4 review and pay · 5 done.
  int step = 1;
  bool loading = false;
  String? error;
  bool busy = false;

  BkOptions? options;

  // ── step 1 ────────────────────────────────────────────────────────────────
  String? mode;
  BkCentres? centres;
  bool centresLoading = false;
  int? cityId;
  int? districtIndex;
  int? centreId;
  String details = '';

  // ── step 2 ────────────────────────────────────────────────────────────────
  String? kind;
  String? gender;

  // ── step 3 ────────────────────────────────────────────────────────────────
  BkGroups? groups;
  List<BkSlotTeacher>? slotTeachers;
  bool timesLoading = false;
  String? timesError;
  int? groupId;
  final Set<int> notifiedGroups = {};
  bool notifiedOtherTime = false;
  int teacherIndex = 0;

  /// The picked slot of each local weekday (1 Monday … 7 Sunday, Dart's numbering).
  final Map<int, int> pickedSlots = {};
  bool proposing = false;
  final Set<int> proposalDays = {}; // Python weekdays
  final Set<String> proposalPeriods = {};

  // ── step 4 / 5 ────────────────────────────────────────────────────────────
  BkQuote? quote;
  BkPayInfo? payInfo;
  String? method;
  BkBooking? booked;

  // ═══════════════════════════════════════════════════════════════════════════

  String get subjectLabel => options?.subject.label.isNotEmpty == true ? options!.subject.label : (subjectTitle ?? '');
  String get gradeLabel => options?.grade.label.isNotEmpty == true ? options!.grade.label : (gradeTitle ?? '');
  int get classMinutes => options?.classMinutes ?? 50;
  String? get currency => quote?.currency ?? options?.currency;

  bool get inPersonOn => !AppConfig.disableList.contains(kBookingInPersonKey);
  bool get individualOn => !AppConfig.disableList.contains(kBookingIndividualKey);
  bool get proposalsOn => (options?.proposals ?? false) && !AppConfig.disableList.contains(kBookingProposalsKey);

  /// The modes to offer: the server's available ones, minus a switched-off kind.
  List<BkChoice> get modes => [
        for (final m in options?.openModes ?? const <BkChoice>[])
          if (m.key != 'in_person' || inPersonOn) m,
      ];

  List<BkChoice> get kinds => [
        for (final k in options?.openKinds ?? const <BkChoice>[])
          if (k.key != 'individual' || individualOn) k,
      ];

  String? get knownGender => gender ?? options?.gender;

  BkCity? get city => centres?.cities.where((c) => c.id == cityId).firstOrNull;
  BkDistrict? get district {
    final c = city;
    final i = districtIndex;
    if (c == null || i == null || i < 0 || i >= c.districts.length) return null;
    return c.districts[i];
  }

  BkCentre? get centre {
    for (final c in centres?.cities ?? const <BkCity>[]) {
      for (final d in c.districts) {
        for (final x in d.centres) {
          if (x.id == centreId) return x;
        }
      }
    }
    return null;
  }

  BkGroup? get group => groups?.items.where((g) => g.id == groupId).firstOrNull;
  BkSlotTeacher? get slotTeacher {
    final t = slotTeachers;
    if (t == null || t.isEmpty) return null;
    return t[teacherIndex.clamp(0, t.length - 1)];
  }

  List<BkSlot> get chosenSlots {
    final t = slotTeacher;
    if (t == null) return [];
    final ids = pickedSlots.values.toSet();
    return [for (final s in t.slots) if (ids.contains(s.id)) s];
  }

  /// The monthly price of what is picked so far (null: nothing to show yet).
  double? get price {
    if (quote?.price != null && step >= 4) return quote!.price;
    if (kind == 'group' && group?.price != null) return group!.price;
    if (kind == 'individual' && !proposing && slotTeacher?.price != null) return slotTeacher!.price;
    if (kind == null || mode == null) return null;
    return options?.price(kind!, mode!);
  }

  /// The forward button may move on.
  bool get canNext => switch (step) {
        1 => mode != null && (mode == 'remote' || centreId != null),
        2 => kind != null && knownGender != null,
        3 => kind == 'group'
            ? (group != null && !group!.full)
            : proposing
                ? proposalDays.length >= 2 && proposalPeriods.isNotEmpty
                : pickedSlots.isNotEmpty,
        4 => !busy,
        _ => false,
      };

  BkRequest get request => BkRequest(
        subjectId: subjectId,
        gradeId: gradeId,
        mode: mode ?? 'remote',
        kind: kind ?? 'group',
        centreId: mode == 'in_person' ? centreId : null,
        details: mode == 'in_person' ? details : null,
        groupId: kind == 'group' ? groupId : null,
        slotIds: [for (final s in chosenSlots) s.id],
        proposal: kind == 'individual' && proposing
            ? BkProposal(
                weekdays: proposalDays.toList()..sort(),
                periods: [for (final p in kBkPeriods) if (proposalPeriods.contains(p.$1)) p.$1],
                tz: AppTime.zoneId,
              )
            : null,
        gender: options?.gender == null ? gender : null,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // Loading
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      options = await api.options(subjectId: subjectId, gradeId: gradeId, gender: gender);
      final ms = modes;
      if (mode == null && ms.length == 1) mode = ms.first.key;
      if (mode == 'in_person') await _loadCentres();
    } catch (e) {
      error = bkErrorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCentres() async {
    if (centres != null) return;
    centresLoading = true;
    notifyListeners();
    try {
      centres = await api.centres();
      final here = centres!.hereCityId;
      cityId ??= here ?? (centres!.cities.length == 1 ? centres!.cities.first.id : null);
      _autoDistrict();
    } catch (e) {
      error = bkErrorText(e);
    } finally {
      centresLoading = false;
      notifyListeners();
    }
  }

  void _autoDistrict() {
    final c = city;
    if (c == null) return;
    if (districtIndex == null && c.districts.length == 1) districtIndex = 0;
    final d = district;
    if (d != null && centreId == null && d.centres.length == 1) centreId = d.centres.first.id;
  }

  Future<void> _loadTimes() async {
    timesLoading = true;
    timesError = null;
    notifyListeners();
    try {
      if (kind == 'group') {
        groups = await api.groups(
          subjectId: subjectId,
          gradeId: gradeId,
          mode: mode ?? 'remote',
          centreId: mode == 'in_person' ? centreId : null,
          gender: options?.gender == null ? gender : null,
        );
        final items = groups!.items;
        if (groupId != null && !items.any((g) => g.id == groupId)) groupId = null;
        if (groups!.single && items.isNotEmpty && !items.first.full) groupId = items.first.id;
      } else {
        slotTeachers = await api.slots(
          subjectId: subjectId,
          gradeId: gradeId,
          mode: mode ?? 'remote',
          centreId: mode == 'in_person' ? centreId : null,
          gender: options?.gender == null ? gender : null,
        );
        if (teacherIndex >= (slotTeachers?.length ?? 0)) teacherIndex = 0;
        // a restored pick of a slot that is gone: drop it
        final ids = {for (final s in slotTeacher?.slots ?? const <BkSlot>[]) s.id};
        pickedSlots.removeWhere((_, v) => !ids.contains(v));
        if ((slotTeachers ?? const []).every((t) => t.slots.isEmpty) && proposalsOn) proposing = true;
      }
    } catch (e) {
      timesError = bkErrorText(e);
    } finally {
      timesLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadReview() async {
    quote = null;
    timesError = null;
    notifyListeners();
    final futures = <Future<void>>[
      api.payMethods(amount: price).then((p) {
        payInfo = p;
        final keys = [for (final m in p.bookable) m.key];
        if (method == null || !keys.contains(method)) method = keys.firstOrNull;
      }).catchError((_) {}),
    ];
    // a guest may not send a write: the review is drawn from the picks, the server's quote comes after the sign-in
    if (!GuestState.active) {
      futures.add(api.quote(request).then<void>((q) => quote = q).catchError((Object e) {
        timesError = bkErrorText(e);
      }));
    }
    await Future.wait(futures);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Picks
  // ═══════════════════════════════════════════════════════════════════════════

  void pickMode(String key) {
    if (mode == key) return;
    mode = key;
    _resetTimes();
    notifyListeners();
    if (key == 'in_person') _loadCentres();
  }

  void pickCity(int id) {
    if (cityId == id) return;
    cityId = id;
    districtIndex = null;
    centreId = null;
    _autoDistrict();
    _resetTimes();
    notifyListeners();
  }

  void pickDistrict(int index) {
    districtIndex = index;
    centreId = null;
    _autoDistrict();
    _resetTimes();
    notifyListeners();
  }

  void pickCentre(int id) {
    centreId = id;
    _resetTimes();
    notifyListeners();
  }

  void setDetails(String v) => details = v;

  void pickKind(String key) {
    if (kind == key) return;
    kind = key;
    _resetTimes();
    notifyListeners();
  }

  Future<void> pickGender(String g) async {
    if (gender == g) return;
    gender = g;
    _resetTimes();
    notifyListeners();
  }

  void pickGroup(int id) {
    groupId = id;
    notifyListeners();
  }

  void pickTeacher(int index) {
    if (teacherIndex == index) return;
    teacherIndex = index;
    pickedSlots.clear();
    notifyListeners();
  }

  /// One slot per day: a second tap on the same time drops it, another time of that day moves the pick.
  void toggleSlot(BkSlot s) {
    final day = AppTime.toZone(s.startsAt).weekday;
    if (pickedSlots[day] == s.id) {
      pickedSlots.remove(day);
    } else {
      pickedSlots[day] = s.id;
    }
    notifyListeners();
  }

  void setProposing(bool on) {
    proposing = on;
    notifyListeners();
  }

  void toggleProposalDay(int pyWeekday) {
    if (!proposalDays.remove(pyWeekday)) proposalDays.add(pyWeekday);
    notifyListeners();
  }

  void toggleProposalPeriod(String key) {
    if (!proposalPeriods.remove(key)) proposalPeriods.add(key);
    notifyListeners();
  }

  void pickMethod(String key) {
    method = key;
    notifyListeners();
  }

  void _resetTimes() {
    groups = null;
    slotTeachers = null;
    groupId = null;
    pickedSlots.clear();
    quote = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Moving
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens [to] (an earlier step from "تعديل", or the next one), loading what it needs.
  Future<void> goTo(int to) async {
    step = to.clamp(1, 5);
    notifyListeners();
    if (step == 3 && (kind == 'group' ? groups == null : slotTeachers == null)) await _loadTimes();
    if (step == 4) await _loadReview();
  }

  Future<void> next() async {
    if (!canNext) return;
    await goTo(step + 1);
  }

  Future<void> back() => goTo(step - 1);

  /// Reloads the times (a group filled up, a slot was taken).
  Future<void> reloadTimes() async {
    groups = null;
    slotTeachers = null;
    await _loadTimes();
  }

  Future<String?> notifyFull(int groupId) async {
    try {
      await api.notifyGroup(groupId);
      notifiedGroups.add(groupId);
      notifyListeners();
      return null;
    } catch (e) {
      return bkErrorText(e);
    }
  }

  Future<String?> notifyOther() async {
    try {
      await api.notifyOtherTime(
        subjectId: subjectId,
        gradeId: gradeId,
        mode: mode ?? 'remote',
        centreId: mode == 'in_person' ? centreId : null,
        gender: options?.gender == null ? gender : null,
      );
      notifiedOtherTime = true;
      notifyListeners();
      return null;
    } catch (e) {
      return bkErrorText(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // The sign-in in between (4ب)
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _draft() => {
        'subject_id': subjectId,
        'grade_id': gradeId,
        'course_id': courseId,
        'mode': mode,
        'city_id': cityId,
        'district': districtIndex,
        'centre_id': centreId,
        'details': details,
        'kind': kind,
        'gender': gender,
        'group_id': groupId,
        'teacher': teacherIndex,
        'slots': {for (final e in pickedSlots.entries) '${e.key}': e.value},
        'proposing': proposing,
        'days': proposalDays.toList(),
        'periods': proposalPeriods.toList(),
        'at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> saveDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kDraftKey, jsonEncode(_draft()));
    } catch (_) {}
  }

  /// A flow left for the sign-in within the last day for this subject and grade.
  static Future<bool> hasDraft(int subjectId, int gradeId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kDraftKey);
      if (raw == null) return false;
      final m = bkMap(jsonDecode(raw));
      final at = bkUtc(m['at']);
      return bkInt(m['subject_id']) == subjectId &&
          bkInt(m['grade_id']) == gradeId &&
          at != null &&
          DateTime.now().toUtc().difference(at) <= const Duration(days: 1);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kDraftKey);
    } catch (_) {}
  }

  /// The picks of a flow left for the sign-in within the last day, when they are for this subject and grade.
  /// True when something was restored (the flow then opens on the review).
  Future<bool> restoreDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kDraftKey);
      if (raw == null) return false;
      final m = bkMap(jsonDecode(raw));
      final at = bkUtc(m['at']);
      if (bkInt(m['subject_id']) != subjectId || bkInt(m['grade_id']) != gradeId) return false;
      if (at == null || DateTime.now().toUtc().difference(at) > const Duration(days: 1)) return false;
      mode = bkStr(m['mode']);
      cityId = bkInt(m['city_id']);
      districtIndex = bkInt(m['district']);
      centreId = bkInt(m['centre_id']);
      details = bkStr(m['details']) ?? '';
      kind = bkStr(m['kind']);
      gender = bkStr(m['gender']);
      groupId = bkInt(m['group_id']);
      teacherIndex = bkInt(m['teacher']) ?? 0;
      pickedSlots
        ..clear()
        ..addAll({
          for (final e in bkMap(m['slots']).entries)
            if (int.tryParse(e.key) != null && bkInt(e.value) != null) int.parse(e.key): bkInt(e.value)!,
        });
      proposing = m['proposing'] == true;
      proposalDays
        ..clear()
        ..addAll([for (final d in (m['days'] is List ? m['days'] as List : const [])) ?bkInt(d)]);
      proposalPeriods
        ..clear()
        ..addAll([for (final x in (m['periods'] is List ? m['periods'] as List : const [])) '$x']);
      await p.remove(_kDraftKey);
      return mode != null && kind != null;
    } catch (_) {
      return false;
    }
  }

  /// After [load] with a restored draft: the lists, then the review.
  Future<void> resumeAtReview() async {
    if (mode == 'in_person') await _loadCentres();
    await _loadTimes();
    if (canNextFrom3) {
      await goTo(4);
    } else {
      step = 3;
      notifyListeners();
    }
  }

  bool get canNextFrom3 {
    final keep = step;
    step = 3;
    final ok = canNext;
    step = keep;
    return ok;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Confirm and pay
  // ═══════════════════════════════════════════════════════════════════════════

  /// Confirms the booking. The answer: the checkout page to open (null when nothing is to be paid now).
  Future<BkConfirmResult> confirm() async {
    busy = true;
    notifyListeners();
    try {
      final r = await api.confirm(request, provider: payInfo?.provider);
      booked = r.booking;
      return r;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// After the gateway page: reads the booking until its seat is paid (30 s at most). True once active.
  Future<bool> settle({Duration every = const Duration(seconds: 5), int tries = 6}) async {
    final id = booked?.id;
    if (id == null) return false;
    for (var i = 0; i < tries; i++) {
      try {
        final mine = await api.mine(subjectId: subjectId);
        final b = mine.where((x) => x.id == id).firstOrNull;
        if (b != null) booked = b;
        if (b == null || b.status != 'pending_payment') break;
      } catch (_) {}
      if (i < tries - 1) await Future<void>.delayed(every);
    }
    notifyListeners();
    return booked?.active == true;
  }

  void done() {
    step = 5;
    notifyListeners();
  }
}
