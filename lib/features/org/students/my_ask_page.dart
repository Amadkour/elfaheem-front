// lib/features/org/students/my_ask_page.dart
//
// Student lifecycle phase 4, the student's side of an ask (CONTRACT §7.1 / §7.3, PLAN §3.7, D-1400). The
// organization asks the student for a meeting, some information, documents or a confirmation; the student answers
// once (a "returned" ask is answered again, with the reviewer's reason on top).
//
//   MyAsk / MyAsksState   GET /api/v1/org/me/asks → {items, fullscreen, popup} · GET …/me/asks/{id}
//   MyAskSource           where the app reads and answers (RemoteMyAskSource; tests give a fake)
//   MyAskView             the answer form, plain values: fields, documents, confirm, meeting accept / decline
//   MyAskAnswerer         MyAskView + the calls (answer, upload) with busy / error
//   MyAskOverlay          the full-screen card / the popup drawn by OrgMustAckHost (org_must_ack.dart) above the app;
//                         it carries its own Navigator so date pickers and the keyboard work above the root one
//   MyAskPage             the pushed page (a notice tap): openMyAsk(nav, askId)
// Kill switch org.students.asks (the server answers empty lists / 409 asks_disabled). Live event student_lifecycle.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import '../org_v3.dart' show OrgCall, orgParseUtc;
import 'student_asks_models.dart' show askErrorText;
import 'students_api.dart' show MyAsksApi;

/// The kill switch of asks (CONTRACT §12).
const kMyAsksFeatureKey = 'org.students.asks';

bool myAsksEnabled() => !AppConfig.disableList.contains(kMyAsksFeatureKey);

/// Whether the app should ask GET /me/asks at all.
bool myAsksShouldAsk({required bool signedIn, required bool viewAs, bool? enabled}) =>
    signedIn && !viewAs && (enabled ?? myAsksEnabled());

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

/// One question of a `data` ask: `{key, label_ar, label_en, kind, options?, required}`.
class MyAskField {
  const MyAskField({required this.key, this.labelAr = '', this.labelEn = '', this.kind = 'text', this.options = const [], this.required = true});

  final String key, labelAr, labelEn;

  /// text · long_text · choice · date · number · yes_no
  final String kind;
  final List<String> options;
  final bool required;

  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);

  static MyAskField? fromJson(dynamic j) {
    final m = asMap(j);
    final key = asStr(m['key']).trim();
    if (key.isEmpty) return null;
    return MyAskField(
      key: key,
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      kind: asStr(m['kind'], 'text'),
      options: [for (final o in (m['options'] is List ? m['options'] as List : const [])) '$o'],
      required: m['required'] != false,
    );
  }
}

class MyAskMeeting {
  const MyAskMeeting({this.startsAt, this.endsAt, this.mode = 'offline', this.location});
  final DateTime? startsAt, endsAt;
  final String mode;
  final String? location;

  bool get online => mode == 'online';

  static MyAskMeeting? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final loc = asStr(m['location']).trim();
    return MyAskMeeting(startsAt: orgParseUtc(m['starts_at']), endsAt: orgParseUtc(m['ends_at']), mode: asStr(m['mode'], 'offline'), location: loc.isEmpty ? null : loc);
  }
}

/// The `Ask` shape as the student reads it.
class MyAsk {
  const MyAsk({
    required this.id,
    this.orgId = 0,
    this.orgName = '',
    this.orgNameEn = '',
    this.kind = 'confirm',
    this.presentation = 'notice',
    this.title = '',
    this.body,
    this.fields = const [],
    this.docKeys = const [],
    this.status = 'open',
    this.answer = const {},
    this.dueAt,
    this.reviewNote,
    this.fromName,
    this.meeting,
    this.canAnswer = false,
    this.docLabels = const {},
  });

  final int id, orgId;
  final String orgName, orgNameEn, kind, presentation, title, status;
  final String? body, reviewNote, fromName;
  final List<MyAskField> fields;
  final List<String> docKeys;
  final Map<String, dynamic> answer;
  final DateTime? dueAt;
  final MyAskMeeting? meeting;
  final bool canAnswer;

  /// The server's words for [docKeys]: `doc_labels` [{key, label_ar, label_en}] → `key → (ar, en)`.
  final Map<String, (String, String)> docLabels;

  bool get returned => status == 'returned';
  bool get fullscreen => presentation == 'fullscreen';
  bool get popup => presentation == 'popup';
  String get org => t(orgName.isEmpty ? orgNameEn : orgName, orgNameEn.isEmpty ? orgName : orgNameEn);

  /// The words for document [key]: the server's bilingual label, else [myAskDocLabel] (an older server).
  String docLabel(String key) {
    final l = docLabels[key];
    if (l == null) return myAskDocLabel(key);
    final (ar, en) = l;
    final s = t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en).trim();
    return s.isEmpty ? myAskDocLabel(key) : s;
  }

  /// The same ask, closed on the server ([status]: `cancelled` / `expired` / …): no form, the closed line instead.
  MyAsk closedAs(String status) => MyAsk(
        id: id, orgId: orgId, orgName: orgName, orgNameEn: orgNameEn, kind: kind, presentation: presentation, title: title,
        body: body, fields: fields, docKeys: docKeys, status: status.isEmpty ? 'closed' : status, answer: answer, dueAt: dueAt,
        reviewNote: reviewNote, fromName: fromName, meeting: meeting, docLabels: docLabels);

  /// The documents already uploaded for this ask: `req_key → document id`.
  Map<String, int> get uploaded => {for (final e in asMap(answer['documents']).entries) e.key: asInt(e.value)};

  /// The values sent last time (a returned `data` ask starts from them).
  Map<String, dynamic> get answeredValues => asMap(answer['values']);

  static MyAsk? fromJson(dynamic j) {
    final m = asMap(j);
    final id = asInt(m['id']);
    if (id <= 0) return null;
    final org = asMap(m['org']);
    final body = asStr(m['body']).trim(), note = asStr(m['review_note']).trim(), by = asStr(asMap(m['created_by'])['name']).trim();
    return MyAsk(
      id: id,
      orgId: asInt(m['org_id'], asInt(org['id'])),
      orgName: asStr(org['name']),
      orgNameEn: asStr(org['name_en']),
      kind: asStr(m['kind'], 'confirm'),
      presentation: asStr(m['presentation'], 'notice'),
      title: asStr(m['title']),
      body: body.isEmpty ? null : body,
      fields: [for (final f in (m['fields'] is List ? m['fields'] as List : const [])) ?MyAskField.fromJson(f)],
      docKeys: [for (final k in (m['doc_keys'] is List ? m['doc_keys'] as List : const [])) '$k'],
      status: asStr(m['status'], 'open'),
      answer: asMap(m['answer']),
      dueAt: orgParseUtc(m['due_at']),
      reviewNote: note.isEmpty ? null : note,
      fromName: by.isEmpty ? null : by,
      meeting: MyAskMeeting.fromJson(m['meeting']),
      canAnswer: asMap(m['can'])['answer'] == true,
      docLabels: {
        for (final d in asMapList(m['doc_labels']))
          if (asStr(d['key']).trim().isNotEmpty) asStr(d['key']).trim(): (asStr(d['label_ar']).trim(), asStr(d['label_en']).trim()),
      },
    );
  }
}

/// GET /me/asks: my open asks across my organizations, plus the oldest full-screen and popup one.
class MyAsksState {
  const MyAsksState({this.items = const [], this.fullscreen, this.popup});
  final List<MyAsk> items;
  final MyAsk? fullscreen, popup;

  static const none = MyAsksState();

  factory MyAsksState.fromJson(dynamic j) {
    final m = asMap(j);
    return MyAsksState(
      items: [for (final x in asMapList(m['items'])) ?MyAsk.fromJson(x)],
      fullscreen: MyAsk.fromJson(m['fullscreen']),
      popup: MyAsk.fromJson(m['popup']),
    );
  }

  /// The full-screen ask to draw now (oldest first), or null; [skip]: answered / closed here, until the next read.
  MyAsk? nextFullscreen([Set<int> skip = const {}]) {
    final f = items.where((a) => a.fullscreen && a.canAnswer && !skip.contains(a.id)).firstOrNull;
    if (f != null) return f;
    final q = fullscreen;
    return q != null && !skip.contains(q.id) ? q : null;
  }

  /// The popup ask to draw now, skipping those the student put off this session.
  MyAsk? nextPopup(Set<int> later) {
    final p = items.where((a) => a.popup && a.canAnswer && !later.contains(a.id)).firstOrNull;
    if (p != null) return p;
    final q = popup;
    return q != null && !later.contains(q.id) ? q : null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels and checks (pure)
// ═════════════════════════════════════════════════════════════════════════════

String myAskKindLabel(String kind) => switch (kind) {
      'meeting' => t('اجتماع', 'Meeting'),
      'data' => t('معلومات مطلوبة', 'Information needed'),
      'documents' => t('مستندات مطلوبة', 'Documents needed'),
      _ => t('تأكيد مطلوب', 'Please confirm'),
    };

IconData myAskKindIcon(String kind) => switch (kind) {
      'meeting' => Icons.event_available_rounded,
      'data' => Icons.edit_note_rounded,
      'documents' => Icons.upload_file_rounded,
      _ => Icons.task_alt_rounded,
    };

/// A document key in plain words: the fallback when the ask carries no `doc_labels` (an older server).
String myAskDocLabel(String key) {
  final k = key.trim();
  if (k.isEmpty) return k;
  final s = k.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// The required questions of a `data` ask still empty in [values].
List<String> myAskMissing(MyAsk a, Map<String, dynamic> values) => [
      for (final f in a.fields)
        if (f.required && _empty(values[f.key])) f.key,
    ];

bool _empty(dynamic v) => v == null || (v is String && v.trim().isEmpty);

/// The values to send for a `data` ask: trimmed, empty ones dropped, numbers as numbers.
Map<String, dynamic> myAskValuesOut(MyAsk a, Map<String, dynamic> values) {
  final out = <String, dynamic>{};
  for (final f in a.fields) {
    final v = values[f.key];
    if (_empty(v)) continue;
    if (f.kind == 'number' && v is String) {
      out[f.key] = num.tryParse(v.trim().replaceAll(',', '.')) ?? v.trim();
    } else {
      out[f.key] = v is String ? v.trim() : v;
    }
  }
  return out;
}

/// "Answer by 3 Dec · 10:00", or null.
String? myAskDueText(MyAsk a) => a.dueAt == null ? null : t('الرد قبل ${AppTime.dateTime(a.dueAt!.toUtc())}', 'Answer by ${AppTime.dateTime(a.dueAt!.toUtc())}');

/// The line a closed ask shows instead of the form.
String myAskClosedText(String status) => switch (status) {
      'answered' => t('وصل ردّك. ستراجعه المؤسسة وتخبرك.', 'Your answer arrived. The organization will review it and let you know.'),
      'accepted' => t('قبلت المؤسسة ردّك. لا شيء آخر مطلوب.', 'The organization accepted your answer. Nothing else is needed.'),
      'cancelled' => t('ألغت المؤسسة هذا الطلب.', 'The organization cancelled this request.'),
      'expired' => t('انتهى موعد هذا الطلب.', 'This request is past its due date.'),
      _ => t('هذا الطلب مغلق.', 'This request is closed.'),
    };

AppTone myAskClosedTone(String status) => switch (status) {
      'answered' => AppTone.info,
      'accepted' => AppTone.success,
      'expired' => AppTone.warning,
      _ => AppTone.neutral,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Source
// ═════════════════════════════════════════════════════════════════════════════

abstract class MyAskSource {
  Future<MyAsksState> fetch();
  Future<OrgCall> one(int id);
  Future<OrgCall> answer(int id, {Map<String, dynamic> values = const {}, bool? confirm});
  Future<OrgCall> upload(int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes});
}

/// The server's (F1's MyAsksApi, students_api.dart).
class RemoteMyAskSource implements MyAskSource {
  const RemoteMyAskSource([this.client]);
  final ApiClient? client;

  MyAsksApi get _api => MyAsksApi(client);

  @override
  Future<MyAsksState> fetch() async {
    final r = await _api.list();
    return r.ok ? MyAsksState.fromJson(r.map) : MyAsksState.none;
  }

  @override
  Future<OrgCall> one(int id) => _api.get(id);

  @override
  Future<OrgCall> answer(int id, {Map<String, dynamic> values = const {}, bool? confirm}) => _api.answer(id, values: values, confirm: confirm);

  @override
  Future<OrgCall> upload(int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes}) =>
      _api.uploadDocument(id, reqKey: reqKey, fileName: fileName, path: path, bytes: bytes);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// The ask with its answer form. Plain values in, callbacks out: [onSubmit] gets the values and the confirm flag,
/// [onUpload] one document key. [onLater] draws a "Later" button (the popup). [onClose] draws "Close" under a closed
/// ask (the overlay: a full-screen ask that closed must never lock the app).
class MyAskView extends StatefulWidget {
  const MyAskView({
    super.key,
    required this.ask,
    this.onSubmit,
    this.onUpload,
    this.onLater,
    this.onClose,
    this.busy = false,
    this.uploading = const {},
    this.error,
    this.showOrg = true,
  });

  final MyAsk ask;
  final void Function(Map<String, dynamic> values, bool? confirm)? onSubmit;
  final ValueChanged<String>? onUpload;
  final VoidCallback? onLater, onClose;
  final bool busy, showOrg;
  final Set<String> uploading;
  final String? error;

  @override
  State<MyAskView> createState() => _MyAskViewState();
}

class _MyAskViewState extends State<MyAskView> {
  final _text = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  final _note = TextEditingController();
  bool _declining = false;
  List<String> _missing = const [];

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(MyAskView old) {
    super.didUpdateWidget(old);
    if (old.ask.id != widget.ask.id) _seed();
  }

  void _seed() {
    _values
      ..clear()
      ..addAll(widget.ask.answeredValues);
    for (final f in widget.ask.fields) {
      if (f.kind == 'text' || f.kind == 'long_text' || f.kind == 'number') {
        (_text[f.key] ??= TextEditingController()).text = asStr(_values[f.key]);
      }
    }
    _declining = false;
    _missing = const [];
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> _collect() => {
        ..._values,
        for (final e in _text.entries) e.key: e.value.text,
      };

  void _sendData() {
    final v = _collect();
    final miss = myAskMissing(widget.ask, v);
    setState(() => _missing = miss);
    if (miss.isEmpty) widget.onSubmit?.call(myAskValuesOut(widget.ask, v), null);
  }

  Future<void> _pickDate(MyAskField f) async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(asStr(_values[f.key]));
    final d = await showDatePicker(context: context, initialDate: cur ?? now, firstDate: DateTime(1900), lastDate: DateTime(now.year + 20));
    if (d == null || !mounted) return;
    setState(() => _values[f.key] = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = widget.ask;
    final due = myAskDueText(a);
    final soon = a.dueAt != null && a.dueAt!.difference(DateTime.now()).inHours < 48;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(color: appToneTint(context, AppTone.brand), shape: BoxShape.circle),
          child: Icon(myAskKindIcon(a.kind), color: appToneInk(context, AppTone.brand), size: AppIconSize.lg),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(myAskKindLabel(a.kind), style: AppType.overline(context).copyWith(color: appToneInk(context, AppTone.brand))),
            if (widget.showOrg && a.org.isNotEmpty) Text(a.org, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
      AppSpace.gapMd,
      Semantics(header: true, child: Text(a.title, style: AppType.headline(context))),
      if (a.fromName != null) ...[
        AppSpace.gapXs,
        Text('${t('من', 'From')}: ${a.fromName}', style: AppType.meta(context)),
      ],
      if (due != null && (a.canAnswer || a.status == 'open')) ...[
        AppSpace.gapXs,
        Row(children: [
          Icon(Icons.schedule_rounded, size: AppIconSize.sm, color: soon ? appToneInk(context, AppTone.warning) : c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Text(due, style: AppType.meta(context).copyWith(color: soon ? appToneInk(context, AppTone.warning) : null))),
        ]),
      ],
      if (a.returned && a.reviewNote != null) ...[
        AppSpace.gapMd,
        Container(
          key: const ValueKey('my_ask.returned'),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: appToneTint(context, AppTone.warning), borderRadius: AppRadius.cardAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('أعادته المؤسسة إليك', 'The organization sent it back'), style: AppType.label(context).copyWith(color: appToneInk(context, AppTone.warning))),
            const SizedBox(height: AppSpace.xxs),
            Text(a.reviewNote!, style: AppType.bodyStrong(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('عدّل ردّك وأرسله مرة أخرى.', 'Change your answer and send it again.'), style: AppType.meta(context)),
          ]),
        ),
      ],
      if (a.body != null && a.kind != 'confirm') ...[
        AppSpace.gapMd,
        Text(a.body!, style: AppType.body(context).copyWith(height: 1.6)),
      ],
      if (a.kind == 'meeting' && a.meeting != null) ...[
        AppSpace.gapMd,
        _MeetingBox(meeting: a.meeting!),
      ],
      AppSpace.gapMd,
      if (!a.canAnswer)
        Container(
          key: const ValueKey('my_ask.closed'),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: appToneTint(context, myAskClosedTone(a.status)), borderRadius: AppRadius.cardAll),
          child: Text(myAskClosedText(a.status), style: AppType.body(context).copyWith(color: appToneInk(context, myAskClosedTone(a.status)))),
        )
      else
        ..._form(context),
      if (widget.error != null) ...[
        AppSpace.gapSm,
        Text(widget.error!, key: const ValueKey('my_ask.error'), style: AppType.body(context).copyWith(color: c.danger)),
      ],
      if (!a.canAnswer && widget.onClose != null) ...[
        // a closed ask over the app (full screen / popup): never a dead end
        AppSpace.gapSm,
        AppButton.secondary(key: const ValueKey('my_ask.close'), label: t('إغلاق', 'Close'), icon: Icons.close_rounded, expand: true, onPressed: widget.onClose),
      ] else if (widget.onLater != null) ...[
        AppSpace.gapSm,
        AppButton.ghost(key: const ValueKey('my_ask.later'), label: t('لاحقاً', 'Later'), expand: true, onPressed: widget.busy ? null : widget.onLater),
      ],
    ]);
  }

  List<Widget> _form(BuildContext context) {
    final a = widget.ask;
    final busy = widget.busy;
    switch (a.kind) {
      case 'meeting':
        return [
          if (!_declining) ...[
            AppButton.primary(
              key: const ValueKey('my_ask.attend'),
              label: t('سأحضر', 'I will attend'),
              icon: Icons.check_rounded,
              busy: busy,
              expand: true,
              onPressed: busy || widget.onSubmit == null ? null : () => widget.onSubmit!(const {}, true),
            ),
            AppSpace.gapSm,
            AppButton.secondary(
              key: const ValueKey('my_ask.decline'),
              label: t('لا أستطيع الحضور', 'I cannot attend'),
              expand: true,
              onPressed: busy ? null : () => setState(() => _declining = true),
            ),
          ] else ...[
            AppField(
              controller: _note,
              label: t('لماذا؟ أو اقترح وقتاً يناسبك', 'Why? Or suggest a time that suits you'),
              maxLines: 3,
              required: true,
              errorText: _missing.contains('note') ? t('اكتب سطراً واحداً على الأقل', 'Write at least one line') : null,
            ),
            AppSpace.gapSm,
            AppButton.primary(
              key: const ValueKey('my_ask.send_decline'),
              label: t('أرسل', 'Send'),
              icon: Icons.send_rounded,
              busy: busy,
              expand: true,
              onPressed: busy || widget.onSubmit == null
                  ? null
                  : () {
                      final n = _note.text.trim();
                      if (n.isEmpty) {
                        setState(() => _missing = const ['note']);
                        return;
                      }
                      widget.onSubmit!({'note': n}, false);
                    },
            ),
            AppButton.ghost(label: t('رجوع', 'Back'), expand: true, onPressed: busy ? null : () => setState(() => _declining = false)),
          ],
        ];
      case 'data':
        return [
          for (final f in a.fields) ...[_question(context, f), AppSpace.gapSm],
          if (_missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(t('أكمل الإجابات المطلوبة', 'Complete the required answers'), style: AppType.meta(context).copyWith(color: context.colors.danger)),
            ),
          AppButton.primary(
            key: const ValueKey('my_ask.send'),
            label: t('أرسل الإجابات', 'Send my answers'),
            icon: Icons.send_rounded,
            busy: busy,
            expand: true,
            onPressed: busy || widget.onSubmit == null ? null : _sendData,
          ),
        ];
      case 'documents':
        final have = a.uploaded;
        final all = a.docKeys.every(have.containsKey);
        return [
          for (final k in a.docKeys) ...[
            _DocRow(
              label: a.docLabel(k),
              uploaded: have.containsKey(k),
              busy: widget.uploading.contains(k),
              onUpload: busy || widget.onUpload == null ? null : () => widget.onUpload!(k),
              keyName: k,
            ),
            AppSpace.gapSm,
          ],
          AppButton.primary(
            key: const ValueKey('my_ask.send'),
            label: t('أرسل المستندات', 'Send the documents'),
            icon: Icons.send_rounded,
            busy: busy,
            expand: true,
            onPressed: busy || !all || widget.onSubmit == null ? null : () => widget.onSubmit!(const {}, null),
          ),
          if (!all) ...[
            AppSpace.gapXs,
            Text(t('ارفع كل المستندات أولاً.', 'Upload every document first.'), textAlign: TextAlign.center, style: AppType.meta(context)),
          ],
        ];
      default:
        return [
          if (a.body != null)
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: context.colors.primaryWash, borderRadius: AppRadius.cardAll),
              child: Text(a.body!, style: AppType.bodyStrong(context).copyWith(height: 1.6)),
            ),
          AppSpace.gapMd,
          AppButton.primary(
            key: const ValueKey('my_ask.confirm'),
            label: t('نعم، أؤكد ذلك', 'Yes, I confirm'),
            icon: Icons.check_rounded,
            busy: busy,
            expand: true,
            onPressed: busy || widget.onSubmit == null ? null : () => widget.onSubmit!(const {}, true),
          ),
        ];
    }
  }

  Widget _question(BuildContext context, MyAskField f) {
    final err = _missing.contains(f.key) ? t('مطلوب', 'Required') : null;
    final label = f.label;
    switch (f.kind) {
      case 'choice':
      case 'yes_no':
        final opts = f.kind == 'yes_no' ? const [true, false] : f.options;
        String optLabel(Object o) => o == true ? t('نعم', 'Yes') : o == false ? t('لا', 'No') : '$o';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.required ? '$label *' : label, style: AppType.label(context)),
          const SizedBox(height: AppSpace.xxs),
          if (opts.length <= 8)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final o in opts)
                ChoiceChip(
                  label: Text(optLabel(o)),
                  selected: _values[f.key] == o,
                  onSelected: widget.busy ? null : (_) => setState(() => _values[f.key] = o),
                ),
            ])
          else
            AppDropdown<String>(
              value: _values[f.key] is String ? _values[f.key] as String : null,
              items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
              onChanged: widget.busy ? null : (v) => setState(() => _values[f.key] = v),
            ),
          if (err != null) Text(err, style: AppType.meta(context).copyWith(color: context.colors.danger)),
        ]);
      case 'date':
        final v = asStr(_values[f.key]);
        final d = DateTime.tryParse(v);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.required ? '$label *' : label, style: AppType.label(context)),
          const SizedBox(height: AppSpace.xxs),
          AppButton.secondary(
            label: d == null ? t('اختر التاريخ', 'Pick the date') : AppTime.wall(d),
            icon: Icons.calendar_month_rounded,
            expand: true,
            onPressed: widget.busy ? null : () => _pickDate(f),
          ),
          if (err != null) Text(err, style: AppType.meta(context).copyWith(color: context.colors.danger)),
        ]);
      default:
        return AppField(
          controller: _text[f.key] ??= TextEditingController(),
          label: label,
          required: f.required,
          maxLines: f.kind == 'long_text' ? 4 : 1,
          keyboard: f.kind == 'number' ? const TextInputType.numberWithOptions(decimal: true) : null,
          ltr: f.kind == 'number',
          enabled: !widget.busy,
          errorText: err,
        );
    }
  }
}

class _MeetingBox extends StatelessWidget {
  const _MeetingBox({required this.meeting});
  final MyAskMeeting meeting;

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    final c = context.colors;
    final s = m.startsAt, e = m.endsAt;
    final when = s == null ? null : '${AppTime.dateTime(s.toUtc())}${e == null ? '' : ' – ${AppTime.time(e.toUtc())}'}';
    Widget line(IconData i, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: AppIconSize.sm, color: c.textMedium),
            AppSpace.gapXs,
            Expanded(child: Text(text, style: AppType.body(context))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.primaryWash, borderRadius: AppRadius.cardAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (when != null) line(Icons.event_rounded, when),
        line(m.online ? Icons.videocam_rounded : Icons.place_rounded,
            m.online ? t('عبر الإنترنت', 'Online') : (m.location ?? t('في المؤسسة', 'At the organization'))),
        if (m.online && m.location != null) line(Icons.link_rounded, m.location!),
      ]),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.label, required this.uploaded, required this.keyName, this.busy = false, this.onUpload});
  final String label, keyName;
  final bool uploaded, busy;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(border: Border.all(color: c.divider, width: AppBorder.hairline), borderRadius: AppRadius.cardAll),
      child: Row(children: [
        Icon(uploaded ? Icons.check_circle_rounded : Icons.description_outlined,
            size: AppIconSize.md, color: uploaded ? appToneInk(context, AppTone.success) : c.textMedium),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            Text(uploaded ? t('تم الرفع', 'Uploaded') : t('مطلوب', 'Needed'), style: AppType.meta(context)),
          ]),
        ),
        AppSpace.gapXs,
        AppButton.tonal(
          key: ValueKey('my_ask.upload.$keyName'),
          label: uploaded ? t('استبدال', 'Replace') : t('رفع', 'Upload'),
          icon: Icons.upload_rounded,
          busy: busy,
          onPressed: onUpload,
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The answerer: the form + the calls
// ═════════════════════════════════════════════════════════════════════════════

/// [onChanged] gets the ask the server answered (after an answer or an upload). [onAnswered] runs after a
/// successful answer, [onFailed] after ANY failed answer and an upload refused as closed (the host reads the asks
/// again, so an ask that closed meanwhile never stays over the app). A closed ask (409 ask_closed, gone, asks off)
/// shows the closed line; [onClose] adds a "Close" button under it. Errors are inline only (the root overlay is hidden
/// under the full-screen card).
class MyAskAnswerer extends StatefulWidget {
  const MyAskAnswerer({super.key, required this.ask, required this.source, this.onChanged, this.onAnswered, this.onFailed, this.onLater, this.onClose, this.showOrg = true});

  final MyAsk ask;
  final MyAskSource source;
  final ValueChanged<MyAsk>? onChanged, onAnswered;
  final ValueChanged<MyAsk>? onFailed;
  final VoidCallback? onLater, onClose;
  final bool showOrg;

  @override
  State<MyAskAnswerer> createState() => _MyAskAnswererState();
}

/// The answer / upload error codes that mean the ask can no longer be answered.
const _closedCodes = {'ask_closed', 'ask_not_found', 'asks_disabled'};

class _MyAskAnswererState extends State<MyAskAnswerer> {
  late MyAsk _ask = widget.ask;
  bool _busy = false;
  final _uploading = <String>{};
  String? _error;

  @override
  void didUpdateWidget(MyAskAnswerer old) {
    super.didUpdateWidget(old);
    if (!identical(old.ask, widget.ask)) _ask = widget.ask;
  }

  /// A failed call: a closed ask turns into the closed line (no error under it), anything else shows its text.
  void _failed(OrgCall r) {
    if (_closedCodes.contains(r.code)) {
      final s = asStr(r.detail['ask_status']).trim();
      _ask = _ask.closedAs(s.isEmpty ? 'closed' : s);
      _error = null;
    } else {
      _error = r.ok ? t('تعذّرت قراءة رد الخادم. حاول مرة أخرى.', 'The server answer could not be read. Try again.') : askErrorText(r.error!);
    }
  }

  Future<void> _submit(Map<String, dynamic> values, bool? confirm) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.source.answer(_ask.id, values: values, confirm: confirm);
    if (!mounted) return;
    final next = r.ok ? MyAsk.fromJson(r.map) : null;
    setState(() {
      _busy = false;
      if (next != null) {
        _ask = next;
      } else {
        _failed(r);
      }
    });
    if (next != null) {
      widget.onChanged?.call(next);
      widget.onAnswered?.call(next);
    } else {
      widget.onFailed?.call(_ask);
    }
  }

  Future<void> _upload(String key) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf']);
    if (f == null || !mounted) return;
    Uint8List? bytes;
    if (kIsWeb) bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _uploading.add(key);
      _error = null;
    });
    final r = await widget.source.upload(_ask.id, reqKey: key, fileName: f.name, path: bytes == null ? f.path : null, bytes: bytes);
    if (!mounted) return;
    final next = r.ok ? MyAsk.fromJson(r.map) : null;
    setState(() {
      _uploading.remove(key);
      if (next != null) {
        _ask = next;
      } else {
        _failed(r);
      }
    });
    if (next != null) {
      widget.onChanged?.call(next);
    } else if (_closedCodes.contains(r.code)) {
      widget.onFailed?.call(_ask);
    }
  }

  @override
  Widget build(BuildContext context) => MyAskView(
        ask: _ask,
        busy: _busy,
        uploading: _uploading,
        error: _error,
        showOrg: widget.showOrg,
        onSubmit: _submit,
        onUpload: _upload,
        onLater: widget.onLater,
        onClose: widget.onClose,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The overlay (full screen / popup) drawn by OrgMustAckHost
// ═════════════════════════════════════════════════════════════════════════════

/// Above the app (MaterialApp.builder, no Navigator there): its own Navigator gives the form an Overlay (text
/// selection) and a place for the date picker. [fullscreen] covers the app until answered; otherwise a popup on a
/// scrim with "Later" ([onLater]).
class MyAskOverlay extends StatelessWidget {
  const MyAskOverlay({super.key, required this.ask, required this.source, required this.fullscreen, this.onAnswered, this.onFailed, this.onLater, this.onClose});

  final MyAsk ask;
  final MyAskSource source;
  final bool fullscreen;
  final ValueChanged<MyAsk>? onAnswered, onFailed;
  final VoidCallback? onLater, onClose;

  @override
  Widget build(BuildContext context) => Navigator(
        key: ValueKey('my_ask.nav.${ask.id}.$fullscreen'),
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => MyAskCardFrame(
            fullscreen: fullscreen,
            onLater: onLater,
            child: MyAskAnswerer(ask: ask, source: source, onAnswered: onAnswered, onFailed: onFailed, onLater: fullscreen ? null : onLater, onClose: onClose),
          ),
        ),
      );
}

/// The frame of the overlay: a full page (full screen) or a card on a scrim (popup). Plain values.
class MyAskCardFrame extends StatelessWidget {
  const MyAskCardFrame({super.key, required this.child, required this.fullscreen, this.onLater});
  final Widget child;
  final bool fullscreen;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = LayoutBuilder(builder: (context, box) {
      final gutter = AppWidth.gutter(box.maxWidth);
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: AppSpace.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: AppCard(child: child),
          ),
        ),
      );
    });
    return Material(
      color: fullscreen ? c.background : appScrimColor(context),
      child: SafeArea(
        child: FocusScope(
          autofocus: true,
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: t('طلب من مؤسستك', 'A request from your organization'),
            child: fullscreen ? card : Center(child: card),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page (a notice tap)
// ═════════════════════════════════════════════════════════════════════════════

/// Opens ask [askId] as a page (AppNavigator: notice module `student_ask`, id = the ask).
Future<void> openMyAsk(NavigatorState nav, int askId) => nav.push(MaterialPageRoute<void>(builder: (_) => MyAskPage(askId: askId)));

class MyAskPage extends StatefulWidget {
  const MyAskPage({super.key, required this.askId, this.source = const RemoteMyAskSource()});
  final int askId;
  final MyAskSource source;

  @override
  State<MyAskPage> createState() => _MyAskPageState();
}

class _MyAskPageState extends State<MyAskPage> {
  MyAsk? _ask;
  String? _error;
  StreamSubscription<LiveEvent>? _live;

  @override
  void initState() {
    super.initState();
    _live = LiveEvents.instance.listen({LiveEvents.studentLifecycle}, (e) {
      final id = asInt(e.data['ask_id']);
      if (id == 0 || id == widget.askId) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.source.one(widget.askId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _ask = MyAsk.fromJson(r.map) ?? _ask;
        _error = null;
      } else {
        _error = askErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _ask;
    final Widget body;
    if (a == null) {
      body = _error != null ? AppErrorState(message: _error, onRetry: _load) : const AppListSkeleton(items: 3);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          AppCard(
            child: MyAskAnswerer(
              ask: a,
              source: widget.source,
              onChanged: (x) => setState(() => _ask = x),
              onAnswered: (_) => showAppNotice(t('أُرسل ردّك', 'Your answer was sent')),
              onFailed: (_) => _load(),
            ),
          ),
        ]),
      );
    }
    return BasePage(
      useWebCard: true,
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: a == null ? t('طلب من مؤسستك', 'A request from your organization') : myAskKindLabel(a.kind)),
      child: body,
    );
  }
}
