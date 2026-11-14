// lib/features/org/org_registrar_midterm.dart — midterm marks (docs/advising/PHASE6.md "Midterm marks"): the
// course's instructor, or staff with `academic update`, enter each student's midterm mark out of 100. The mark feeds
// the early warning's `midterm_fail` rule; a row whose final grade is approved is locked (read-only).
//
//   RegMidtermRow / RegMidtermRoster   the GET body (tolerant of missing keys)
//   regMidtermEdit                     the PUT body from the CHANGED, unlocked rows only (empty field = clear)
//   RegMidtermList                     the roster (plain values, test/ui/registrar_midterm_layout_test.dart)
//   RegMidtermPane                     loads / saves through the instructor or staff route; `reload()`, `dirty`
// Routes: staff `/orgs/{org}/registrar/terms/{tid}/midterm/{cid}`, instructor
// `/public/{org}/registrar/teach/terms/{tid}/courses/{cid}/midterm` (both GET and PUT).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t, toast;
import 'org_providers.dart' show OrgApi;
import 'org_registrar.dart' show registrarCodeText, regStatusText;
import 'org_v3.dart' show orgCall, orgParseUtc;

/// One student of the midterm roster.
class RegMidtermRow {
  const RegMidtermRow({
    required this.registrationId,
    required this.studentId,
    this.name = '',
    this.code,
    this.status = '',
    this.percent,
    this.at,
    this.locked = false,
  });

  final int registrationId, studentId;
  final String name;
  final String? code;

  /// `registered` · `completed`.
  final String status;

  /// The stored mark out of 100 (null: none yet).
  final double? percent;

  /// When the mark was last saved.
  final DateTime? at;

  /// The final grade is approved: the mark can no longer change.
  final bool locked;

  factory RegMidtermRow.fromJson(Map<String, dynamic> j) {
    final student = asMap(j['student']);
    final p = j['interim_percent'];
    final code = asStr(j['student_code']).trim();
    return RegMidtermRow(
      registrationId: asInt(j['registration_id']),
      studentId: asInt(student['id'] ?? student['user_id']),
      name: asStr(student['name']).trim(),
      code: code.isEmpty || code == 'null' ? null : code,
      status: asStr(j['status']),
      percent: p is num ? p.toDouble() : double.tryParse('${p ?? ''}'),
      at: orgParseUtc(j['interim_at']),
      locked: asBool(j['locked']),
    );
  }

  String get shown => name.isEmpty ? '#$studentId' : name;

  /// The mark as the field shows it ('' for none, "45" for a whole mark).
  String get text => regMidtermText(percent);
}

/// A mark as text: '' for none, "45" for a whole mark, else "45.5".
String regMidtermText(double? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return '${v.round()}';
  return '$v';
}

/// `GET …/midterm`: the term, the course and its students.
class RegMidtermRoster {
  const RegMidtermRoster({this.term = const {}, this.course = const {}, this.rows = const []});

  final Map<String, dynamic> term, course;
  final List<RegMidtermRow> rows;

  factory RegMidtermRoster.fromJson(Map<String, dynamic> j) => RegMidtermRoster(
        term: asMap(j['term']),
        course: asMap(j['course']),
        rows: [for (final m in asMapList(j['items'])) RegMidtermRow.fromJson(m)].where((r) => r.studentId != 0).toList(),
      );

  /// "CS101 · Programming I".
  String get courseTitle {
    final name = t('${course['name_ar'] ?? course['name_en'] ?? ''}', '${course['name_en'] ?? course['name_ar'] ?? ''}');
    final code = course['code'];
    return code == null ? name : '$code · $name';
  }
}

/// The PUT items for the rows whose field ([texts]: student id → typed text) differs from the stored mark; locked
/// rows are never sent; an empty field clears the mark (null). [error] `bad_percent`: a field is not a number from 0
/// to 100 (nothing is sent then).
({List<Map<String, dynamic>> items, String? error}) regMidtermEdit(List<RegMidtermRow> rows, Map<int, String> texts) {
  final items = <Map<String, dynamic>>[];
  for (final r in rows) {
    if (r.locked) continue;
    final typed = texts[r.studentId];
    if (typed == null) continue;
    final s = typed.trim().replaceAll(',', '.');
    if (s.isEmpty) {
      if (r.percent != null) items.add({'student_id': r.studentId, 'interim_percent': null});
      continue;
    }
    final v = double.tryParse(s);
    if (v == null || v.isNaN || v < 0 || v > 100) return (items: const [], error: 'bad_percent');
    if (r.percent != null && (r.percent! - v).abs() < 1e-9) continue;
    items.add({'student_id': r.studentId, 'interim_percent': v});
  }
  return (items: items, error: null);
}

// ═════════════════════════════════════════════════════════════════════════════
//  The roster (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class RegMidtermList extends StatelessWidget {
  const RegMidtermList({super.key, required this.rows, required this.controllers, this.busy = false, this.errorText, this.onSave});

  final List<RegMidtermRow> rows;

  /// Student id → the field of an unlocked row.
  final Map<int, TextEditingController> controllers;
  final bool busy;

  /// A failed save, shown above the roster.
  final String? errorText;

  /// null: nothing can be saved (every row is locked).
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (rows.isEmpty) {
      return AppEmpty(icon: Icons.groups_rounded, title: t('لا يوجد طلاب مسجلون', 'No registered students'));
    }
    final editable = rows.any((r) => !r.locked);
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: AppBanner(
              icon: Icons.info_outline_rounded,
              text: t('اكتب درجة منتصف الفصل من 100، أو امسحها لإزالتها. تُستخدم في الإنذار المبكر، وتُقفل حين تُعتمد الدرجة النهائية.',
                  'Enter the midterm mark out of 100, or clear it to remove it. It feeds early warning, and approving the final grade locks it.'),
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: AppSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: errorText!),
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          for (final r in rows) _MidtermCard(row: r, controller: controllers[r.studentId], enabled: !busy),
        ]),
      ),
      if (editable)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
            child: AppPrimaryButton(label: t('حفظ درجات منتصف الفصل', 'Save midterm marks'), icon: Icons.save_rounded, busy: busy, onPressed: onSave),
          ),
        ),
    ]);
  }
}

class _MidtermCard extends StatelessWidget {
  const _MidtermCard({required this.row, this.controller, this.enabled = true});
  final RegMidtermRow row;
  final TextEditingController? controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row;
    final status = r.status.isEmpty || r.status == 'registered' ? null : regStatusText(r.status);
    final meta = [
      ?r.code,
      if (status != null && status.isNotEmpty) status,
      if (r.at != null) t('حُفظت ${AppTime.dateTime(r.at!.toUtc())}', 'Saved ${AppTime.dateTime(r.at!.toUtc())}'),
    ].join(' · ');
    final Widget mark = r.locked || controller == null
        ? Text(r.text.isEmpty ? '—' : r.text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]))
        : Semantics(
            label: t('درجة منتصف الفصل لـ ${r.shown}', 'Midterm mark for ${r.shown}'),
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(isDense: true, hintText: '—'),
            ),
          );
    return AppCard(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              if (meta.isNotEmpty) Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (r.locked) ...[
                const SizedBox(height: AppSpace.xxs),
                AppBadgePill(t('مقفلة — الدرجة النهائية معتمدة', 'Locked — final grade approved'), color: c.textMedium, icon: Icons.lock_rounded),
              ],
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          SizedBox(width: 76, child: mark),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pane
// ═════════════════════════════════════════════════════════════════════════════

/// The midterm roster of one course: loads [path], saves the changed rows with PUT, reloads.
class RegMidtermPane extends StatefulWidget {
  const RegMidtermPane({super.key, required this.path});
  final String path;

  @override
  State<RegMidtermPane> createState() => RegMidtermPaneState();
}

class RegMidtermPaneState extends State<RegMidtermPane> {
  RegMidtermRoster? _roster;
  bool _failed = false, _missing = false, _busy = false;
  String? _error;
  final Map<int, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<int, String> get _texts => {for (final e in _ctrl.entries) e.key: e.value.text};

  /// A field differs from the stored mark (or holds something that is not a mark).
  bool get dirty {
    final r = _roster;
    if (r == null) return false;
    final e = regMidtermEdit(r.rows, _texts);
    return e.error != null || e.items.isNotEmpty;
  }

  Future<void> reload() async {
    final r = await orgCall(() => OrgApi.i.api.get(widget.path), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        final roster = RegMidtermRoster.fromJson(r.map);
        _roster = roster;
        for (final row in roster.rows) {
          if (!row.locked) _ctrl.putIfAbsent(row.studentId, () => TextEditingController()).text = row.text;
        }
        _failed = _missing = false;
      } else {
        _missing = r.endpointMissing;
        _failed = _roster == null;
      }
    });
  }

  Future<void> _save() async {
    final roster = _roster;
    if (roster == null || _busy) return;
    final e = regMidtermEdit(roster.rows, _texts);
    if (e.error != null) {
      setState(() => _error = registrarCodeText(e.error!));
      return;
    }
    if (e.items.isEmpty) {
      toast(t('لا تغييرات للحفظ', 'No changes to save'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => OrgApi.i.api.put(widget.path, body: {'items': e.items}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return;
    final errs = asMapList(r.map['errors']);
    final saved = asInt(r.map['saved'], e.items.length - errs.length);
    if (errs.isEmpty) {
      toast(t('حُفظت درجات منتصف الفصل ($saved)', 'Midterm marks saved ($saved)'));
    } else {
      toast('${registrarCodeText('${errs.first['code']}')} (${errs.length})', error: true);
    }
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_missing && _roster == null) {
      return AppEmpty(
        icon: Icons.system_update_alt_rounded,
        title: t('يحتاج تحديث الخادم', 'Needs a server update'),
        message: t('رصد درجات منتصف الفصل لم يصل إلى الخادم بعد.', 'Midterm mark entry is not on the server yet.'),
      );
    }
    final roster = _roster;
    return AppAsync(
      loading: roster == null && !_failed,
      failed: _failed,
      onRetry: () {
        setState(() => _failed = false);
        reload();
      },
      child: roster == null
          ? const SizedBox.shrink()
          : RegMidtermList(rows: roster.rows, controllers: _ctrl, busy: _busy, errorText: _error, onSave: _save),
    );
  }
}
