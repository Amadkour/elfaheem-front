// lib/features/org/students/student_asks_models.dart — asks and the requests inbox (student lifecycle contract §7.1,
// §7.3; PLAN §3.6, §3.7). Plain Dart: no widget, no network, so test/org/student_asks_test.dart reads it directly.
//
//   askKinds / askPresentations / askStatuses        the enums, with askKindLabel · askPresentationLabel / Hint ·
//                                                    askStatusLabel / askStatusTone
//   AskField · AskMeeting · AskPerson · AskOrg       the parts of an `Ask`
//   StudentAsk.fromJson                              the server's `Ask` (staff and student read the same shape)
//   MyAsks.fromJson                                  GET /api/v1/org/me/asks → {items, fullscreen, popup}
//   AskListPage.fromJson                             GET …/students/asks → {items, total, page, pages}
//   InboxRow · InboxPage.fromJson                    GET …/students/requests?tab= → {counts, items, …}
//   AskDraft                                         the staff sheet's form: problem() / problemText() / toJson() (AskIn)
//   askPreviewLines(draft, name:)                    "what the student will see", in plain sentences
//   askAnswerLines(ask)                              the student's answer as label → value lines (the reviewer reads it)
//   askAnswerMissing(ask, values, confirm)           the keys the student still has to fill (mirrors the server's
//                                                    422 answer_incomplete), for the student's own form
//   AskBusy.listOf(detail)                           the 409 `attendees_busy` list
//   askCodeTexts() / askErrorText(e)                 bilingual texts of the phase-4 codes
//
// Times: the server sends naive UTC (orgParseUtc → local); the draft keeps UTC instants and sends orgUtc().
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr, asBool;
import '../org_v3.dart' show orgParseUtc, orgUtc, orgErrorText;
import 'student_status_models.dart' show StatusSource;
import 'students_models.dart' show StudentUser;

/// The kill switch of asks (§12).
const kStudentAsksKey = 'org.students.asks';

/// The live event of the student lifecycle (payload {org_id, student_id, ask_id, kind}).
const kStudentLifecycleEvent = 'student_lifecycle';

/// The help page of the inbox (the ask sheet shares it, §12).
const kStudentRequestsHelpId = 'org.students.requests';

const askKinds = ['meeting', 'data', 'documents', 'confirm'];
const askPresentations = ['notice', 'popup', 'fullscreen'];
const askStatuses = ['open', 'answered', 'accepted', 'returned', 'cancelled', 'expired'];

/// The student may still answer.
const askOpenStatuses = {'open', 'returned'};

/// Staff may still act.
const askLiveStatuses = {'open', 'answered', 'returned'};

/// The answer types of a written question (server `FIELD_KINDS`).
const askFieldKinds = ['text', 'long_text', 'choice', 'date', 'number', 'yes_no'];

/// A full-screen ask needs a due date within this many days (422 `fullscreen_needs_due`).
const askFullscreenMaxDays = 7;

/// Meeting lengths the sheet offers, in minutes.
const askMeetingLengths = [15, 30, 45, 60, 90, 120];

String _pick(String ar, String en) => AppConfig.lang == 'en' && en.trim().isNotEmpty ? en : (ar.trim().isNotEmpty ? ar : en);

String askKindLabel(String k) => switch (k) {
      'meeting' => t('اجتماع', 'Meeting'),
      'data' => t('معلومات', 'Information'),
      'documents' => t('مستندات', 'Documents'),
      'confirm' => t('تأكيد', 'Confirmation'),
      _ => k,
    };

/// The inbox's type chip ("Meeting request").
String askKindRequestLabel(String k) => switch (k) {
      'meeting' => t('طلب اجتماع', 'Meeting request'),
      'data' => t('طلب معلومات', 'Information request'),
      'documents' => t('طلب مستندات', 'Documents request'),
      'confirm' => t('طلب تأكيد', 'Confirmation request'),
      _ => k,
    };

String askKindHint(String k) => switch (k) {
      'meeting' => t('موعد يحضره الطالب حضورياً أو عبر الإنترنت', 'A time the student attends in person or online'),
      'data' => t('أسئلة قصيرة أو بيانات ناقصة من ملفه', 'Short questions, or data missing from the file'),
      'documents' => t('مستندات يرفعها إلى ملفه', 'Documents the student uploads to the file'),
      'confirm' => t('عبارة يقرأها الطالب ويؤكدها', 'A sentence the student reads and confirms'),
      _ => '',
    };

String askPresentationLabel(String p) => switch (p) {
      'notice' => t('إشعار', 'Notification'),
      'popup' => t('نافذة منبثقة', 'Popup'),
      'fullscreen' => t('ملء الشاشة', 'Full screen'),
      _ => p,
    };

String askPresentationHint(String p) => switch (p) {
      'notice' => t('يصله إشعار ويفتح الطلب متى شاء', 'A notification; the student opens it when ready'),
      'popup' => t('نافذة تظهر عند فتح التطبيق، ويمكنه تأجيلها', 'A window on the next app open; it can be put off'),
      'fullscreen' => t('صفحة كاملة لا تُغلق حتى يرد، بموعد خلال ٧ أيام', 'A full page that stays until answered; due within 7 days'),
      _ => '',
    };

String askStatusLabel(String s) => switch (s) {
      'open' => t('بانتظار الطالب', 'Waiting for the student'),
      'answered' => t('أجاب الطالب', 'Answered'),
      'accepted' => t('مقبول', 'Accepted'),
      'returned' => t('أُعيد للتصحيح', 'Returned for a fix'),
      'cancelled' => t('أُلغي', 'Cancelled'),
      'expired' => t('انتهى موعده', 'Expired'),
      _ => s,
    };

AppTone askStatusTone(String s) => switch (s) {
      'open' => AppTone.info,
      'answered' => AppTone.brand,
      'accepted' => AppTone.success,
      'returned' => AppTone.warning,
      'expired' => AppTone.danger,
      _ => AppTone.neutral,
    };

String askFieldKindLabel(String k) => switch (k) {
      'text' => t('نص قصير', 'Short text'),
      'long_text' => t('نص طويل', 'Long text'),
      'choice' => t('اختيار من قائمة', 'A choice'),
      'date' => t('تاريخ', 'Date'),
      'number' => t('رقم', 'Number'),
      'yes_no' => t('نعم / لا', 'Yes / no'),
      _ => k,
    };

/// The default title of a new ask of [kind].
String askDefaultTitle(String kind) => switch (kind) {
      'meeting' => t('اجتماع مع شؤون الطلاب', 'A meeting with student affairs'),
      'data' => t('نحتاج بعض المعلومات منك', 'We need some information from you'),
      'documents' => t('نحتاج مستندات لملفك', 'We need documents for your file'),
      'confirm' => t('نرجو تأكيدك', 'Please confirm'),
      _ => '',
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Parts
// ═════════════════════════════════════════════════════════════════════════════

/// One question of a `data` ask. Mutable labels / options so the sheet edits a written question in place.
class AskField {
  AskField({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.kind = 'text',
    List<String>? options,
    this.required = true,
    this.caseField = false,
  }) : options = options ?? [];

  String key, labelAr, labelEn, kind;
  List<String> options;
  bool required, caseField;

  factory AskField.fromJson(Map<String, dynamic> m) => AskField(
        key: asStr(m['key']),
        labelAr: asStr(m['label_ar']),
        labelEn: asStr(m['label_en']),
        kind: asStr(m['kind']).isEmpty ? 'text' : asStr(m['kind']),
        options: [for (final o in (m['options'] is List ? m['options'] as List : const [])) '$o'],
        required: m['required'] != false,
        caseField: asBool(m['case_field']),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label_ar': labelAr.trim(),
        'label_en': labelEn.trim(),
        'kind': kind,
        if (kind == 'choice') 'options': [for (final o in options) if (o.trim().isNotEmpty) o.trim()],
        'required': required,
        'case_field': caseField,
      };

  String get label {
    final l = _pick(labelAr, labelEn);
    return l.isEmpty ? key : l;
  }
}

class AskMeeting {
  const AskMeeting({this.id, this.startsAt, this.endsAt, this.mode = 'offline', this.location, this.status});
  final int? id;
  final DateTime? startsAt, endsAt;
  final String mode;
  final String? location, status;

  bool get online => mode == 'online';

  static AskMeeting? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final id = asInt(m['id']);
    final loc = asStr(m['location']).trim(), st = asStr(m['status']).trim();
    return AskMeeting(
      id: id > 0 ? id : null,
      startsAt: orgParseUtc(m['starts_at']),
      endsAt: orgParseUtc(m['ends_at']),
      mode: asStr(m['mode']) == 'online' ? 'online' : 'offline',
      location: loc.isEmpty ? null : loc,
      status: st.isEmpty ? null : st,
    );
  }

  /// "25 Nov 2026 · 10:00 AM · In person: Room 12".
  String get line => [
        if (startsAt != null) AppTime.dateTime(startsAt!.toUtc()),
        online ? t('عبر الإنترنت', 'Online') : (location == null ? t('حضورياً', 'In person') : t('حضورياً: $location', 'In person: $location')),
      ].join(' · ');
}

class AskPerson {
  const AskPerson(this.id, this.name);
  final int id;
  final String name;

  static AskPerson? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final id = asInt(m['id']);
    return id > 0 ? AskPerson(id, asStr(m['name'])) : null;
  }
}

class AskOrg {
  const AskOrg({required this.id, this.name = '', this.nameEn = '', this.logo});
  final int id;
  final String name, nameEn;
  final String? logo;

  static AskOrg? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final logo = asStr(m['logo']).trim();
    return AskOrg(id: asInt(m['id']), name: asStr(m['name']), nameEn: asStr(m['name_en']), logo: logo.isEmpty ? null : logo);
  }

  String get displayName => _pick(name, nameEn);
}

class AskCan {
  const AskCan({this.answer = false, this.cancel = false, this.accept = false});
  final bool answer, cancel, accept;

  factory AskCan.fromJson(dynamic j) {
    final m = asMap(j);
    return AskCan(answer: asBool(m['answer']), cancel: asBool(m['cancel']), accept: asBool(m['accept']));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Ask
// ═════════════════════════════════════════════════════════════════════════════

class StudentAsk {
  const StudentAsk({
    required this.id,
    this.orgId = 0,
    this.userId = 0,
    this.kind = 'data',
    this.presentation = 'notice',
    this.title = '',
    this.body,
    this.fields = const [],
    this.docKeys = const [],
    this.status = 'open',
    this.answer = const {},
    this.answeredAt,
    this.dueAt,
    this.remindDays = const [],
    this.remindedCount = 0,
    this.meetingId,
    this.sourceType,
    this.sourceId,
    this.caseId,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.createdAt,
    this.updatedAt,
    this.org,
    this.createdBy,
    this.student,
    this.meeting,
    this.can = const AskCan(),
  });

  final int id, orgId, userId;
  final String kind, presentation, title, status;
  final String? body;
  final List<AskField> fields;
  final List<String> docKeys;

  /// `{values: {}}` · `{documents: {req_key: doc_id}}` · `{confirm: true}` · `{confirm, note}` (meeting).
  final Map<String, dynamic> answer;
  final DateTime? answeredAt, dueAt, reviewedAt, createdAt, updatedAt;
  final List<int> remindDays;
  final int remindedCount;
  final int? meetingId, sourceId, caseId;
  final String? sourceType, reviewNote;
  final AskPerson? reviewedBy, createdBy;
  final AskOrg? org;

  /// Only in a staff read.
  final StudentUser? student;
  final AskMeeting? meeting;
  final AskCan can;

  factory StudentAsk.fromJson(dynamic j) {
    final m = asMap(j);
    int? id0(dynamic v) {
      final i = asInt(v);
      return i > 0 ? i : null;
    }

    String? s0(dynamic v) {
      final s = asStr(v).trim();
      return s.isEmpty ? null : s;
    }

    final stu = m['student'];
    final kind = asStr(m['kind']);
    final pres = asStr(m['presentation']);
    final status = asStr(m['status']);
    return StudentAsk(
      id: asInt(m['id']),
      orgId: asInt(m['org_id']),
      userId: asInt(m['user_id']),
      kind: askKinds.contains(kind) ? kind : 'data',
      presentation: askPresentations.contains(pres) ? pres : 'notice',
      title: asStr(m['title']),
      body: s0(m['body']),
      fields: [for (final f in asMapList(m['fields'])) AskField.fromJson(f)],
      docKeys: [for (final k in (m['doc_keys'] is List ? m['doc_keys'] as List : const [])) '$k'],
      status: status.isEmpty ? 'open' : status,
      answer: asMap(m['answer']),
      answeredAt: orgParseUtc(m['answered_at']),
      dueAt: orgParseUtc(m['due_at']),
      remindDays: [for (final d in (m['remind_days'] is List ? m['remind_days'] as List : const [])) asInt(d)],
      remindedCount: m['reminded'] is List ? (m['reminded'] as List).length : 0,
      meetingId: id0(m['meeting_id']),
      sourceType: s0(m['source_type']),
      sourceId: id0(m['source_id']),
      caseId: id0(m['case_id']),
      reviewedBy: AskPerson.fromJson(m['reviewed_by']),
      reviewedAt: orgParseUtc(m['reviewed_at']),
      reviewNote: s0(m['review_note']),
      createdAt: orgParseUtc(m['created_at']),
      updatedAt: orgParseUtc(m['updated_at']),
      org: AskOrg.fromJson(m['org']),
      createdBy: AskPerson.fromJson(m['created_by']),
      student: stu is Map
          ? StudentUser(id: asInt(stu['id']), name: asStr(stu['name']), imageUrl: s0(stu['image_url']))
          : null,
      meeting: AskMeeting.fromJson(m['meeting']),
      can: AskCan.fromJson(m['can']),
    );
  }

  bool get isOpen => askOpenStatuses.contains(status);
  bool get isLive => askLiveStatuses.contains(status);
  bool get isAnswered => status == 'answered';

  /// Open and past its due date (the sweep will mark it expired).
  bool overdue([DateTime? now]) => isOpen && dueAt != null && dueAt!.isBefore(now ?? DateTime.now());

  Map<String, dynamic> get answerValues => asMap(answer['values']);
  Map<String, dynamic> get answerDocuments => asMap(answer['documents']);
  bool? get answerConfirm => answer['confirm'] is bool ? answer['confirm'] as bool : null;
  String? get answerNote {
    final n = asStr(answer['note']).trim();
    return n.isEmpty ? null : n;
  }

  String get kindLabel => askKindLabel(kind);
  String get statusLabel => askStatusLabel(status);
  AppTone get statusTone => askStatusTone(status);
}

class MyAsks {
  const MyAsks({this.items = const [], this.fullscreen, this.popup});
  final List<StudentAsk> items;
  final StudentAsk? fullscreen, popup;

  factory MyAsks.fromJson(dynamic j) {
    final m = asMap(j);
    return MyAsks(
      items: [for (final a in asMapList(m['items'])) StudentAsk.fromJson(a)],
      fullscreen: m['fullscreen'] is Map ? StudentAsk.fromJson(m['fullscreen']) : null,
      popup: m['popup'] is Map ? StudentAsk.fromJson(m['popup']) : null,
    );
  }
}

class AskListPage {
  const AskListPage({this.items = const [], this.total = 0, this.page = 1, this.pages = 0});
  final List<StudentAsk> items;
  final int total, page, pages;

  factory AskListPage.fromJson(dynamic j) {
    final m = asMap(j);
    final items = [for (final a in asMapList(m['items'])) StudentAsk.fromJson(a)];
    return AskListPage(
      items: items,
      total: m.containsKey('total') ? asInt(m['total']) : items.length,
      page: asInt(m['page']) < 1 ? 1 : asInt(m['page']),
      pages: asInt(m['pages']),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests inbox
// ═════════════════════════════════════════════════════════════════════════════

const inboxTabs = ['decide', 'waiting', 'done'];
const inboxSources = ['case', 'decision', 'ask', 'work_item'];

String inboxTabLabel(String tab) => switch (tab) {
      'decide' => t('للقرار', 'To decide'),
      'waiting' => t('بانتظار الطالب', 'Waiting for the student'),
      'done' => t('تم', 'Done'),
      _ => tab,
    };

String inboxSourceLabel(String s) => switch (s) {
      'case' => t('ملف قبول', 'Admission file'),
      'decision' => t('توصية', 'Recommendation'),
      'ask' => t('طلب من الطالب', 'Request to the student'),
      'work_item' => t('طلب الطالب', 'Student request'),
      _ => s,
    };

class InboxCan {
  const InboxCan({this.accept = false, this.ret = false, this.reject = false, this.meeting = false, this.ask = false});
  final bool accept, ret, reject, meeting, ask;

  factory InboxCan.fromJson(dynamic j) {
    final m = asMap(j);
    return InboxCan(
      accept: asBool(m['accept']),
      ret: asBool(m['return']),
      reject: asBool(m['reject']),
      meeting: asBool(m['meeting']),
      ask: asBool(m['ask']),
    );
  }

  bool get any => accept || ret || reject || meeting || ask;
}

class InboxRow {
  const InboxRow({
    required this.id,
    required this.source,
    required this.sourceId,
    this.student,
    this.titleAr = '',
    this.titleEn = '',
    this.at,
    this.status = '',
    this.can = const InboxCan(),
  });

  /// `"<source>:<source_id>"`.
  final String id;
  final String source;
  final int sourceId;
  final StudentUser? student;
  final String titleAr, titleEn, status;
  final DateTime? at;
  final InboxCan can;

  factory InboxRow.fromJson(Map<String, dynamic> m) {
    final s = m['student'];
    StudentUser? stu;
    if (s is Map && asInt(s['id']) > 0) {
      final img = asStr(s['image_url']).trim();
      stu = StudentUser(id: asInt(s['id']), name: asStr(s['name']), imageUrl: img.isEmpty ? null : img);
    }
    final src = asStr(m['source']);
    final sid = asInt(m['source_id']);
    final id = asStr(m['id']);
    return InboxRow(
      id: id.isEmpty ? '$src:$sid' : id,
      source: src,
      sourceId: sid,
      student: stu,
      titleAr: asStr(m['title_ar']),
      titleEn: asStr(m['title_en']),
      at: orgParseUtc(m['at']),
      status: asStr(m['status']),
      can: InboxCan.fromJson(m['can']),
    );
  }

  String get title => _pick(titleAr, titleEn);
  String get sourceLabel => inboxSourceLabel(source);
  bool get isAsk => source == 'ask';

  /// The status text of the row (ask statuses read plainly; the others keep a generic word).
  String get statusLabel => isAsk
      ? askStatusLabel(status)
      : switch (status) {
          'submitted' || 'under_review' || 'open' => t('ينتظر قراراً', 'Waiting for a decision'),
          'needs_correction' => t('أُعيد للتصحيح', 'Returned for a fix'),
          'approved' || 'active' || 'accepted' || 'applied' => t('مقبول', 'Accepted'),
          'rejected' => t('مرفوض', 'Rejected'),
          _ => status,
        };

  AppTone get statusTone => isAsk
      ? askStatusTone(status)
      : switch (status) {
          'submitted' || 'under_review' || 'open' => AppTone.brand,
          'needs_correction' => AppTone.warning,
          'approved' || 'active' || 'accepted' || 'applied' => AppTone.success,
          'rejected' => AppTone.danger,
          _ => AppTone.neutral,
        };
}

class InboxPage {
  const InboxPage({this.tab = 'decide', this.counts = const {}, this.items = const [], this.page = 1, this.size = 30, this.total = 0});
  final String tab;
  final Map<String, int> counts;
  final List<InboxRow> items;
  final int page, size, total;

  factory InboxPage.fromJson(dynamic j) {
    final m = asMap(j);
    final c = asMap(m['counts']);
    final items = [for (final r in asMapList(m['items'])) InboxRow.fromJson(r)];
    final size = asInt(m['size']);
    return InboxPage(
      tab: inboxTabs.contains(asStr(m['tab'])) ? asStr(m['tab']) : 'decide',
      counts: {for (final k in inboxTabs) k: asInt(c[k])},
      items: items,
      page: asInt(m['page']) < 1 ? 1 : asInt(m['page']),
      size: size < 1 ? 30 : size,
      total: m.containsKey('total') ? asInt(m['total']) : items.length,
    );
  }

  int count(String tab) => counts[tab] ?? 0;
  int get pages => total <= 0 ? 1 : (total + size - 1) ~/ size;
}

// ═════════════════════════════════════════════════════════════════════════════
//  The staff form (AskIn)
// ═════════════════════════════════════════════════════════════════════════════

/// A document or data item the sheet can ask for (from GET …/missing).
class AskPickable {
  const AskPickable(this.key, this.label, {this.kind});
  final String key, label;

  /// A field's input kind (`date`, `phone`, …); null for a document.
  final String? kind;
}

/// The server's answer kind for a case field's input kind.
String askKindForCaseField(String? inputKind) => switch (inputKind) {
      'date' => 'date',
      'number' || 'integer' => 'number',
      'textarea' || 'long_text' => 'long_text',
      _ => 'text',
    };

/// Mutable: the sheet edits it inside setState. All times are UTC instants.
class AskDraft {
  AskDraft({
    this.kind = 'meeting',
    this.presentation = 'notice',
    String? title,
    this.body = '',
    List<AskField>? fields,
    List<String>? docKeys,
    this.dueAt,
    List<int>? remindDays,
    this.startsAt,
    this.minutes = 30,
    this.mode = 'offline',
    this.location = '',
    this.source,
    this.force = false,
  })  : title = title ?? askDefaultTitle(kind),
        fields = fields ?? [],
        docKeys = docKeys ?? [],
        remindDays = remindDays ?? [3, 1];

  String kind, presentation, title, body;
  List<AskField> fields;
  List<String> docKeys;
  DateTime? dueAt;
  List<int> remindDays;

  // meeting
  DateTime? startsAt;
  int minutes;
  String mode, location;

  StatusSource? source;

  /// Book although the student is busy (the busy list was on screen).
  bool force;

  DateTime? get endsAt => startsAt?.add(Duration(minutes: minutes));

  /// Switches the kind; a title still equal to the old default follows the new kind.
  void setKind(String k) {
    if (title.trim().isEmpty || title == askDefaultTitle(kind)) title = askDefaultTitle(k);
    kind = k;
    force = false;
  }

  /// A new written question with a key that is not taken yet.
  AskField addQuestion() {
    var n = fields.length + 1;
    while (fields.any((f) => f.key == 'q$n')) {
      n++;
    }
    final f = AskField(key: 'q$n');
    fields.add(f);
    return f;
  }

  /// Toggles a case field from the student's file.
  void toggleCaseField(AskPickable p) {
    final i = fields.indexWhere((f) => f.key == p.key && f.caseField);
    if (i >= 0) {
      fields.removeAt(i);
    } else {
      fields.add(AskField(key: p.key, labelAr: p.label, labelEn: p.label, kind: askKindForCaseField(p.kind), caseField: true));
    }
  }

  void toggleDoc(String key) => docKeys.contains(key) ? docKeys.remove(key) : docKeys.add(key);

  /// The first thing that stops the save (a code), null when it may be sent.
  String? problem([DateTime? now]) {
    final at = now ?? DateTime.now();
    if (title.trim().isEmpty) return 'title';
    switch (kind) {
      case 'meeting':
        if (startsAt == null) return 'meeting_time';
        if (!startsAt!.isAfter(at)) return 'meeting_past';
      case 'data':
        if (fields.isEmpty) return 'fields';
        for (final f in fields) {
          if (f.labelAr.trim().isEmpty && f.labelEn.trim().isEmpty) return 'field_label';
          if (f.kind == 'choice' && f.options.where((o) => o.trim().isNotEmpty).length < 2) return 'field_options';
        }
      case 'documents':
        if (docKeys.isEmpty) return 'doc_keys';
      case 'confirm':
        if (body.trim().isEmpty) return 'confirm_text';
    }
    if (dueAt != null && !dueAt!.isAfter(at)) return 'due_past';
    if (presentation == 'fullscreen') {
      if (dueAt == null || dueAt!.isAfter(at.add(const Duration(days: askFullscreenMaxDays)))) return 'fullscreen_due';
    }
    return null;
  }

  String? problemText([DateTime? now]) => switch (problem(now)) {
        null => null,
        'title' => t('اكتب عنواناً قصيراً للطلب', 'Write a short title for the request'),
        'meeting_time' => t('اختر يوم الاجتماع ووقته', 'Pick the meeting day and time'),
        'meeting_past' => t('وقت الاجتماع يجب أن يكون في المستقبل', 'The meeting must be in the future'),
        'fields' => t('اختر بنداً من ملفه أو أضف سؤالاً', 'Pick an item from the file or add a question'),
        'field_label' => t('كل سؤال يحتاج نصاً', 'Every question needs its wording'),
        'field_options' => t('سؤال الاختيار يحتاج خيارين على الأقل', 'A choice needs at least two options'),
        'doc_keys' => t('اختر مستنداً واحداً على الأقل', 'Pick at least one document'),
        'confirm_text' => t('اكتب العبارة التي يؤكدها الطالب', 'Write the sentence the student confirms'),
        'due_past' => t('موعد الاستحقاق يجب أن يكون في المستقبل', 'The due date must be in the future'),
        'fullscreen_due' => t('العرض بملء الشاشة يحتاج موعد استحقاق خلال ٧ أيام', 'Full screen needs a due date within 7 days'),
        final c => c,
      };

  /// AskIn (§7.3).
  Map<String, dynamic> toJson() {
    final b = body.trim();
    return {
      'kind': kind,
      'presentation': presentation,
      'title': title.trim(),
      'body': b.isEmpty ? null : b,
      'fields': kind == 'data' ? [for (final f in fields) f.toJson()] : const [],
      'doc_keys': kind == 'documents' ? List<String>.of(docKeys) : const [],
      'due_at': orgUtc(dueAt),
      'remind_days': dueAt == null ? null : (List<int>.of(remindDays)..sort((a, b) => b.compareTo(a))),
      'meeting': kind == 'meeting' && startsAt != null
          ? {
              'starts_at': orgUtc(startsAt),
              'ends_at': orgUtc(endsAt),
              'mode': mode,
              'location': location.trim().isEmpty ? null : location.trim(),
            }
          : null,
      'source': source?.toJson(),
      'force': force,
    };
  }
}

/// "What the student will see", one plain sentence per line. [name] is the student's name.
List<String> askPreviewLines(AskDraft d, {String? name}) {
  final who = (name == null || name.trim().isEmpty) ? t('الطالب', 'The student') : name.trim();
  final title = d.title.trim().isEmpty ? askDefaultTitle(d.kind) : d.title.trim();
  final how = switch (d.presentation) {
    'popup' => t('تظهر لـ$who نافذة عند فتح التطبيق بعنوان «$title».', '$who sees a window on the next app open: “$title”.'),
    'fullscreen' => t('تظهر لـ$who صفحة كاملة بعنوان «$title» لا تُغلق حتى يرد.', '$who sees a full page, “$title”, that stays until answered.'),
    _ => t('يصل إلى $who إشعار بعنوان «$title».', '$who gets a notification: “$title”.'),
  };
  final what = switch (d.kind) {
    'meeting' => d.startsAt == null
        ? t('يختار: سأحضر، أو لا أستطيع مع السبب.', 'They choose: I will attend, or I cannot, with a reason.')
        : t(
            'الاجتماع ${AppTime.dateTime(d.startsAt!.toUtc())} (${d.minutes} دقيقة) ${d.mode == 'online' ? 'عبر الإنترنت برابط في تقويمه' : (d.location.trim().isEmpty ? 'حضورياً' : 'حضورياً في ${d.location.trim()}')}، ويظهر في تقويمه وتقويمك.',
            'The meeting is on ${AppTime.dateTime(d.startsAt!.toUtc())} (${d.minutes} min), ${d.mode == 'online' ? 'online with a link in their calendar' : (d.location.trim().isEmpty ? 'in person' : 'in person at ${d.location.trim()}')}, in both calendars.'),
    'data' => d.fields.isEmpty
        ? t('يجيب عن الأسئلة التي تختارها.', 'They answer the questions you pick.')
        : t('يجيب عن: ${d.fields.map((f) => f.label).join('، ')}.', 'They answer: ${d.fields.map((f) => f.label).join(', ')}.'),
    'documents' => t('يرفع ${d.docKeys.isEmpty ? 'المستندات المطلوبة' : '${d.docKeys.length} مستند'} إلى ملفه مباشرة.',
        'They upload ${d.docKeys.isEmpty ? 'the documents' : '${d.docKeys.length} document(s)'} straight to the file.'),
    _ => d.body.trim().isEmpty
        ? t('يقرأ العبارة ويضغط «أؤكد».', 'They read the sentence and tap “I confirm”.')
        : t('يقرأ: «${d.body.trim()}» ثم يضغط «أؤكد».', 'They read: “${d.body.trim()}”, then tap “I confirm”.'),
  };
  final due = d.dueAt == null
      ? t('بلا موعد نهائي.', 'No due date.')
      : t(
          'الموعد النهائي ${AppTime.dateTime(d.dueAt!.toUtc())}${d.remindDays.isEmpty ? '' : '، مع تذكير قبله بـ${d.remindDays.join(' و')} يوم'}.',
          'Due ${AppTime.dateTime(d.dueAt!.toUtc())}${d.remindDays.isEmpty ? '' : ', reminded ${d.remindDays.join(' and ')} day(s) before'}.');
  final review = d.kind == 'data' && d.fields.any((f) => f.caseField)
      ? t('إجاباته عن بيانات الملف لا تُحفظ فيه حتى تقبلها.', 'Answers about file data reach the file only when you accept them.')
      : null;
  return [how, what, due, ?review];
}

/// The answer as (label, value) lines for the reviewer.
List<(String, String)> askAnswerLines(StudentAsk a) {
  switch (a.kind) {
    case 'data':
      final v = a.answerValues;
      return [
        for (final f in a.fields)
          if (v.containsKey(f.key)) (f.label, _answerText(f, v[f.key])),
      ];
    case 'documents':
      final d = a.answerDocuments;
      return [
        for (final k in a.docKeys) (k, d.containsKey(k) ? t('مرفوع', 'Uploaded') : t('لم يُرفع', 'Not uploaded')),
      ];
    case 'confirm':
      return [(t('التأكيد', 'Confirmation'), a.answerConfirm == true ? t('أكّد الطالب', 'Confirmed') : t('لم يؤكد بعد', 'Not confirmed yet'))];
    default:
      final c = a.answerConfirm;
      return [
        (t('الحضور', 'Attendance'), c == null ? t('لم يرد بعد', 'No answer yet') : (c ? t('سيحضر', 'Will attend') : t('لا يستطيع الحضور', 'Cannot attend'))),
        if (a.answerNote != null) (t('ملاحظته', 'Their note'), a.answerNote!),
      ];
  }
}

String _answerText(AskField f, dynamic v) {
  if (v == null) return '—';
  if (f.kind == 'yes_no') return v == true ? t('نعم', 'Yes') : t('لا', 'No');
  if (f.kind == 'date') {
    final d = DateTime.tryParse('$v');
    if (d != null) return AppTime.wall(d);
  }
  return '$v';
}

/// The keys the student still has to fill before sending (empty = may send). `confirm` / `note` for the confirm and
/// meeting kinds; the document keys not uploaded yet for `documents`.
List<String> askAnswerMissing(StudentAsk a, Map<String, dynamic> values, bool? confirm) {
  bool empty(dynamic v) => v == null || (v is String && v.trim().isEmpty);
  switch (a.kind) {
    case 'data':
      return [for (final f in a.fields) if (f.required && empty(values[f.key])) f.key];
    case 'documents':
      final have = a.answerDocuments;
      return [for (final k in a.docKeys) if (!have.containsKey(k)) k];
    case 'confirm':
      return confirm == true ? const [] : const ['confirm'];
    default:
      if (confirm == null) return const ['confirm'];
      if (confirm == false && empty(values['note'])) return const ['note'];
      return const [];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Busy list and errors
// ═════════════════════════════════════════════════════════════════════════════

/// One busy invitee of a 409 `attendees_busy` (the calendar's shape).
class AskBusy {
  const AskBusy({required this.name, this.items = const []});
  final String name;
  final List<({String title, DateTime? startsAt, DateTime? endsAt})> items;

  static List<AskBusy> listOf(Map<String, dynamic> detail) {
    final raw = detail['busy'];
    if (raw is! List) return const [];
    return [
      for (final b in raw)
        if (b is Map)
          AskBusy(
            name: asStr(asMap(b['user'])['name']),
            items: [
              for (final i in asMapList(b['items']))
                (title: asStr(i['title']), startsAt: orgParseUtc(i['starts_at']), endsAt: orgParseUtc(i['ends_at'])),
            ],
          ),
    ];
  }

  /// "Lecture · 25 Nov 2026 · 10:00 AM".
  String get line => items
      .map((i) => [if (i.title.isNotEmpty) i.title, if (i.startsAt != null) AppTime.dateTime(i.startsAt!.toUtc())].join(' · '))
      .join('\n');
}

Map<String, String> askCodeTexts() => {
      'bad_ask': t('بعض بيانات الطلب غير صالحة، راجعها', 'Some of the request is not valid; check it'),
      'ask_not_found': t('الطلب غير موجود', 'This request was not found'),
      'ask_action_unknown': t('إجراء غير معروف', 'Unknown action'),
      'fullscreen_needs_due': t('العرض بملء الشاشة يحتاج موعد استحقاق خلال ٧ أيام', 'Full screen needs a due date within 7 days'),
      'asks_disabled': t('طلب البيانات أو الاجتماع من الطالب موقوف حالياً', 'Asking students for data or a meeting is switched off right now'),
      'ask_not_answered': t('لم يُجب الطالب على هذا الطلب بعد', 'The student has not answered yet'),
      'ask_closed': t('هذا الطلب مغلق', 'This request is closed'),
      'answer_incomplete': t('أكمل الإجابات المطلوبة', 'Complete the required answers'),
      'reason_required': t('اكتب السبب ليعرف الطالب ما المطلوب', 'Write the reason so the student knows what to fix'),
      'reminded_recently': t('تم تذكير الطالب خلال آخر 24 ساعة', 'The student was reminded in the last 24 hours'),
      'attendees_busy': t('الطالب مشغول في هذا الوقت', 'The student is busy at this time'),
      'bad_time': t('صيغة الوقت غير صحيحة', 'The time is not valid'),
      'bad_range': t('وقت الانتهاء يجب أن يكون بعد وقت البدء', 'The end must come after the start'),
      'bad_mode': t('طريقة الاجتماع غير معروفة', 'Unknown meeting mode'),
      'doc_type': t('هذا المستند غير مطلوب في هذا الطلب', 'This document is not part of this request'),
    };

/// A phase-4 code → its text; `bad_ask` keeps the server's own sentence (it names the field).
String askErrorText(ApiException e) {
  final c = e.code;
  if (c == 'bad_ask' && e.message.trim().isNotEmpty) {
    final d = ApiException.asMap(e.body)?['detail'];
    final en = d is Map ? asStr(d['message_en']).trim() : '';
    return AppConfig.lang == 'en' && en.isNotEmpty ? en : e.message;
  }
  return (c == null ? null : askCodeTexts()[c]) ?? orgErrorText(e);
}
