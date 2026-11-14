// The server's real print preview of a paper exam (back contract OFFLINE_FLOW_CONTRACT.md §5, D-696 / D-699): page 1 of
// the NB2 or bubble sheet as the server will print it, for one student or a generic copy, with the stored design and the
// chosen attributes, and the design adjustments the server made (an element moved off a machine-read area, a QR
// dropped, …) in plain words. Shown on the Paper design and Review steps; when the route fails, the sheet is not one the
// server draws, or `exam.paper_designer` is off, the client's header preview stands in.
//
// Pure parts (parsers, texts) are tested on a real payload in test/org/offline_flow_test.dart; PaperPreviewView is the
// plain-value widget the layout harness pumps; PaperPreviewPane owns the debounced calls.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/hub/create/offline_plan_api.dart' show OfflinePlanApi, offlinePlanErrorText;

/// The design kill switch (the same key the paper sheet and Deliver read).
const kExamPaperDesignerKey = 'exam.paper_designer';

/// The two sheets the server draws.
enum PreviewPart { nb2, bubble }

/// One adjustment the server made to the design so the sheet still reads (contract §5 "Report").
class DesignAdjustment {
  const DesignAdjustment({required this.part, this.element, required this.action, required this.reason});
  final String part;
  final String? element;

  /// moved · shrunk · scaled · dropped.
  final String action;
  final String reason;

  static DesignAdjustment fromJson(Map<String, dynamic> j) => DesignAdjustment(
        part: '${j['part'] ?? 'header'}',
        element: j['element'] == null ? null : '${j['element']}',
        action: '${j['action'] ?? ''}',
        reason: '${j['reason'] ?? ''}',
      );
}

/// The `X-Design-Adjustments` header of a print answer: base64 of a JSON list; empty when absent or unreadable.
List<DesignAdjustment> adjustmentsOfHeader(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  try {
    final list = jsonDecode(utf8.decode(base64.decode(value.trim())));
    return [for (final x in asMapList(list)) DesignAdjustment.fromJson(x)];
  } catch (_) {
    return const [];
  }
}

/// One adjustment in words, e.g. "Header: an element was moved off the QR and the marks".
String adjustmentText(DesignAdjustment a) {
  final where = a.part == 'footer' ? t('التذييل', 'Footer') : t('الرأس', 'Header');
  final what = switch (a.reason) {
    'moved_into_zone' => t('نُقل عنصر ليبقى داخل مساحته', 'an element was moved back inside its area'),
    'shrunk_to_zone' => t('صُغّر عنصر ليتسع في مساحته', 'an element was shrunk to fit its area'),
    'moved_off_machine_area' => t('نُقل عنصر بعيدًا عن رمز QR وعلامات القراءة', 'an element was moved off the QR and the reading marks'),
    'covers_machine_area' => t('حُذف عنصر يغطي منطقة يقرؤها الماسح', 'an element covering a machine-read area was left out'),
    'qr_not_allowed' => t('حُذف رمز QR إضافي، فللورقة رمزها', 'an extra QR code was left out; the sheet has its own'),
    'band_taller_than_zone' => t('ضُغط الشريط ليتسع في الورقة', 'the band was squeezed to fit the sheet'),
    'no_footer_on_this_sheet' => t('لا مكان للتذييل في هذه الورقة', 'this sheet has no room for a footer'),
    'image_unavailable' || 'image_unreadable' => t('صورة لم تعد متاحة فلم تُطبع', 'a picture is no longer available, so it is not printed'),
    _ => t('عُدّل عنصر ليُطبع سليمًا', 'an element was adjusted to print cleanly'),
  };
  return '$where: $what';
}

/// `POST /exams/{id}/paper-design/preview`.
class PaperPreview {
  const PaperPreview({required this.png, required this.part, this.adjustments = const []});
  final Uint8List png;
  final String part;
  final List<DesignAdjustment> adjustments;

  /// Null when the answer holds no PNG.
  static PaperPreview? fromJson(Map<String, dynamic> j) {
    try {
      final bytes = base64.decode('${j['png'] ?? ''}');
      if (bytes.length < 8 || bytes[0] != 0x89 || bytes[1] != 0x50) return null;
      return PaperPreview(png: bytes, part: '${j['part'] ?? ''}', adjustments: [for (final a in asMapList(j['adjustments'])) DesignAdjustment.fromJson(a)]);
    } catch (_) {
      return null;
    }
  }
}

/// The preview body: [studentId] null = a generic copy; [attributes] null = the plan's.
Map<String, dynamic> paperPreviewBody(PreviewPart part, {int? studentId, List<String>? attributes, Map<String, dynamic>? document, String? lang}) => {
      'part': part.name,
      'student_id': ?studentId,
      'attributes': ?attributes,
      'document': ?document,
      'lang': ?lang,
    };

class PaperPreviewApi {
  PaperPreviewApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<EngineResult> preview(int examId, Map<String, dynamic> body) =>
      engineCall(() => _api.post('${ExamEngineApi.base}/exams/$examId/paper-design/preview', body: body));
}

/// A student to preview: (id, name).
typedef PreviewStudent = ({int id, String name});

// ═══════════════════════════════════════ drawn ═════════════════════════════════════════════════════════════════

/// The real page, with the student picker above it and the adjustments under it. [png] null = loading (a skeleton).
class PaperPreviewView extends StatelessWidget {
  const PaperPreviewView({
    super.key,
    required this.png,
    required this.students,
    required this.studentId,
    required this.onStudent,
    this.adjustments = const [],
    this.parts = const [],
    this.part,
    this.onPart,
  });

  final Uint8List? png;
  final List<PreviewStudent> students;

  /// Null = a generic copy.
  final int? studentId;
  final ValueChanged<int?> onStudent;
  final List<DesignAdjustment> adjustments;

  /// Shown as chips when there is more than one sheet to see.
  final List<PreviewPart> parts;
  final PreviewPart? part;
  final ValueChanged<PreviewPart>? onPart;

  static String partLabel(PreviewPart p) => p == PreviewPart.nb2 ? t('ورقة الإجابة', 'Answer sheet') : t('ورقة التظليل', 'Bubble sheet');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: const ValueKey('create.preview'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.print_outlined, size: AppIconSize.sm, color: c.textLight),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(t('كما ستُطبع الصفحة الأولى', 'Page 1, as it will print'), style: AppType.meta(context))),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (parts.length > 1 && onPart != null) ...[
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final p in parts) AppChoiceChip(key: ValueKey('create.preview.part.${p.name}'), label: partLabel(p), selected: p == part, onTap: () => onPart!(p)),
          ]),
          const SizedBox(height: AppSpace.xs),
        ],
        AppDropdown<int>(
          key: const ValueKey('create.preview.student'),
          value: studentId ?? 0,
          items: [
            DropdownMenuItem(value: 0, child: Text(t('نسخة عامة', 'Generic copy'), overflow: TextOverflow.ellipsis)),
            for (final s in students) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onStudent(v == null || v == 0 ? null : v),
        ),
        const SizedBox(height: AppSpace.sm),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: AspectRatio(
              aspectRatio: 210 / 297,
              child: png == null
                  ? const AppSkeletonBox(key: ValueKey('create.preview.loading'), height: double.infinity)
                  : DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: c.divider)),
                      child: Image.memory(png!, key: const ValueKey('create.preview.page'), fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: t('معاينة الورقة', 'Sheet preview')),
                    ),
            ),
          ),
        ),
        for (final a in adjustments) ...[
          const SizedBox(height: AppSpace.xs),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_fix_high_outlined, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(adjustmentText(a), style: AppType.meta(context))),
          ]),
        ],
      ]),
    );
  }
}

/// Loads the real preview for [parts] (the first one shown), again a moment after the attributes change, and shows
/// [fallback] (the client's header preview) whenever the server cannot: no sheet it draws, the switch off, or a failure.
class PaperPreviewPane extends StatefulWidget {
  const PaperPreviewPane({super.key, required this.examId, required this.parts, required this.attributes, required this.fallback, this.api, this.people, this.debounce = const Duration(milliseconds: 400)});
  final int examId;
  final List<PreviewPart> parts;
  final List<String> attributes;
  final Widget fallback;

  /// Tests pass fakes.
  final PaperPreviewApi? api;
  final OfflinePlanApi? people;
  final Duration debounce;

  @override
  State<PaperPreviewPane> createState() => _PaperPreviewPaneState();
}

class _PaperPreviewPaneState extends State<PaperPreviewPane> {
  late final PaperPreviewApi _api = widget.api ?? PaperPreviewApi();
  late final OfflinePlanApi _people = widget.people ?? OfflinePlanApi();
  Timer? _timer;
  int _ask = 0;
  PaperPreview? _got;
  bool _loading = true, _failed = false;
  List<PreviewStudent> _students = const [];
  int? _student;
  late PreviewPart? _part = widget.parts.firstOrNull;

  bool get _on => !AppConfig.disableList.contains(kExamPaperDesignerKey) && _part != null;

  @override
  void initState() {
    super.initState();
    if (_on) {
      _loadStudents();
      _timer = Timer(Duration.zero, _load);
    }
  }

  @override
  void didUpdateWidget(PaperPreviewPane old) {
    super.didUpdateWidget(old);
    if (!widget.parts.contains(_part)) _part = widget.parts.firstOrNull;
    if (_on && (old.attributes.join('|') != widget.attributes.join('|') || old.parts.join('|') != widget.parts.join('|'))) _schedule(widget.debounce);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    final r = await _people.attributeValues(widget.examId, 'name');
    if (!mounted || !r.ok) return;
    setState(() => _students = [
          for (final x in asMapList(r.map['items']).take(200)) (id: asInt(x['student_id']), name: '${x['name'] ?? ''}'.trim()),
        ].where((s) => s.id != 0 && s.name.isNotEmpty).toList());
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    setState(() => _loading = true);
    _timer = Timer(d, _load);
  }

  Future<void> _load() async {
    final part = _part;
    if (part == null) return;
    final ask = ++_ask;
    final r = await _api.preview(widget.examId, paperPreviewBody(part, studentId: _student, attributes: widget.attributes.isEmpty ? null : widget.attributes, lang: AppConfig.lang));
    if (!mounted || ask != _ask) return;   // a newer request is on its way
    final got = r.ok ? PaperPreview.fromJson(asMap(r.map)) : null;
    setState(() {
      _loading = false;
      _failed = got == null;
      if (got != null) _got = got;
      if (got != null) SeenDesignAdjustments.remember(widget.examId, got.adjustments);
    });
    if (!r.ok && r.status != 0 && !r.unavailable) debugPrint('paper preview: ${offlinePlanErrorText(r)}');
  }

  @override
  Widget build(BuildContext context) {
    if (!_on || _failed) return widget.fallback;
    return PaperPreviewView(
      png: _loading && _got == null ? null : _got?.png,
      adjustments: _got?.adjustments ?? const [],
      students: _students,
      studentId: _student,
      onStudent: (v) {
        _student = v;
        _schedule(Duration.zero);
      },
      parts: widget.parts,
      part: _part,
      onPart: (p) {
        _part = p;
        _got = null;
        _schedule(Duration.zero);
      },
    );
  }
}

// ═══════════════════════════════════════ adjustments on a real print ═══════════════════════════════════════════

/// The adjustments the teacher last saw for each exam (in the preview, or in a print's notice): in memory, and on the
/// device under `paper_adjust_seen.<examId>`. A print says the adjustments again only when they differ from these.
class SeenDesignAdjustments {
  SeenDesignAdjustments._();
  static final Map<int, String> _seen = {};

  static String signature(List<DesignAdjustment> list) =>
      ([for (final a in list) '${a.part}|${a.element ?? ''}|${a.action}|${a.reason}']..sort()).join('\n');

  static String _key(int examId) => 'paper_adjust_seen.$examId';

  /// What the teacher saw for [examId]: memory first, else the device; null when nothing was ever seen.
  static Future<String?> seen(int examId) async {
    final m = _seen[examId];
    if (m != null) return m;
    try {
      return (await SharedPreferences.getInstance()).getString(_key(examId));
    } catch (_) {
      return null;
    }
  }

  static void remember(int examId, List<DesignAdjustment> list) {
    final s = signature(list);
    if (_seen[examId] == s) return;
    _seen[examId] = s;
    unawaited(() async {
      try {
        await (await SharedPreferences.getInstance()).setString(_key(examId), s);
      } catch (_) {
        // memory alone then
      }
    }());
  }

  /// Tests.
  static void clear() => _seen.clear();
}

/// One quiet line for a print's adjustments: at most two, then "and N more".
String designAdjustmentsNoticeText(List<DesignAdjustment> list) {
  final shown = [for (final a in list.take(2)) adjustmentText(a)];
  final more = list.length - shown.length;
  final head = shown.join(t('؛ ', '; '));
  if (more <= 0) return head;
  return t('$head، و$more غيرها', '$head, and $more more');
}

/// Reads a printed sheet's `X-Design-Adjustments` header for [examId] and says them once, only when they differ from the
/// ones the teacher last saw. Missing or unreadable header: nothing. Never awaited by the print. Returns the line shown.
Future<String?> noticePrintAdjustments(int examId, Map<String, List<String>> headers, {void Function(String text)? notify}) async {
  String? raw;
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == 'x-design-adjustments' && e.value.isNotEmpty) raw = e.value.first;
  }
  if (raw == null || raw.trim().isEmpty) return null;
  List<DesignAdjustment> list;
  try {
    final decoded = jsonDecode(utf8.decode(base64.decode(raw.trim())));
    if (decoded is! List) return null;
    list = [for (final x in asMapList(decoded)) DesignAdjustment.fromJson(x)];
  } catch (_) {
    return null;
  }
  final seen = await SeenDesignAdjustments.seen(examId);
  SeenDesignAdjustments.remember(examId, list);
  if (list.isEmpty || seen == SeenDesignAdjustments.signature(list)) return null;
  final text = designAdjustmentsNoticeText(list);
  (notify ?? (s) => showAppNotice(s))(text);
  return text;
}
