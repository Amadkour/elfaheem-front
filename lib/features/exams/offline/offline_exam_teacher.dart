// Offline sittings, teacher side: allow the exam offline, hand it out and collect answers in the hall (this phone
// becomes a relay), upload answers files in bulk, auto-grade in one tap, then review and override in the usual review
// screen. Every bundle shows where it came from (the delivery chain) and anything the server found suspicious.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/attendance/relay_host_provider.dart';
import 'package:flutter_education_app/features/exams/exam_features.dart' show examAutoCorrectAllowed;
import 'package:flutter_education_app/features/exams/exam_review_screen.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_core.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_relay.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_service.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';

String offlineFlagText(String code) => switch (code) {
      'unsealed' => t('غير مختومة', 'Not sealed'),
      'package_mismatch' => t('نسخة مختلفة', 'Different copy'),
      'over_time' => t('تجاوز المدة', 'Over time'),
      'late' => t('بعد نهاية الموعد', 'After the end'),
      'clock_changed' => t('تغيير ساعة الجهاز', 'Device clock changed'),
      'bad_answer' => t('إجابة غير صالحة', 'Invalid answer'),
      _ => code,
    };

String offlineStepText(Map<String, dynamic> h) {
  final from = switch ('${h['from'] ?? ''}') {
    'server' => t('من الخادم', 'from the server'),
    'teacher' => t('من جهاز المعلم', 'from the teacher\'s phone'),
    'peer' => t('من جهاز زميل', 'from a classmate\'s phone'),
    _ => '',
  };
  final via = switch ('${h['via'] ?? ''}') {
    'self' => t('من الطالب نفسه', 'by the student'),
    'classmate' => t('عبر زميل', 'through a classmate'),
    'teacher' => t('عبر المعلم', 'through the teacher'),
    _ => '',
  };
  final what = switch ('${h['step']}') {
    'package' => t('استلام الاختبار', 'Exam received'),
    'key' => t('استلام المفتاح', 'Key received'),
    'started' => t('بدء الحل', 'Started'),
    'finished' => t('إنهاء وختم الإجابات', 'Finished and sealed'),
    'relayed' => t('تمرير عبر جهاز قريب', 'Passed through a nearby phone'),
    'uploaded' => t('وصول إلى الخادم', 'Reached the server'),
    _ => '${h['step']}',
  };
  return [what, from, via].where((s) => s.isNotEmpty).join(' · ');
}

/// One received bundle (plain values; under the layout harness).
class OfflineSubmissionTile extends StatelessWidget {
  const OfflineSubmissionTile({super.key, required this.item, this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flags = [for (final f in (item['integrity'] as List? ?? const [])) '$f'];
    final open = asInt(item['open_answers']);
    final pct = item['percentage'];
    final who = item['student_id'] == null ? t('طالب (تصحيح مُعمّى)', 'Student (anonymous marking)') : t('الطالب #${item['student_id']}', 'Student #${item['student_id']}');
    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(who, style: appText(14, w: FontWeight.w700, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (pct != null && open == 0) Text('$pct%', style: appText(13.5, w: FontWeight.w700, c: c.primary)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppBadgePill(open > 0 ? t('$open بانتظار التصحيح', '$open to mark') : t('مُصحّح', 'Marked'), color: open > 0 ? c.warning : c.success),
          AppBadgePill(item['sealed'] == true ? t('مختومة', 'Sealed') : t('غير مختومة', 'Not sealed'),
              color: item['sealed'] == true ? c.textMedium : c.warning, icon: item['sealed'] == true ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined),
          for (final f in flags) AppBadgePill(offlineFlagText(f), color: c.danger, icon: Icons.flag_outlined),
        ]),
      ]),
    );
  }
}

/// The counters at the top (plain values; under the layout harness).
class OfflineSummaryRow extends StatelessWidget {
  const OfflineSummaryRow({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      AppBadgePill(t('وصلت ${asInt(summary['total'])}', '${asInt(summary['total'])} received'), icon: Icons.inbox_rounded),
      AppBadgePill(t('مُصحّحة ${asInt(summary['graded'])}', '${asInt(summary['graded'])} marked'), color: c.success),
      AppBadgePill(t('للمراجعة ${asInt(summary['to_review'])}', '${asInt(summary['to_review'])} to review'), color: c.warning),
      if (asInt(summary['flagged']) > 0) AppBadgePill(t('مُعلَّمة ${asInt(summary['flagged'])}', '${asInt(summary['flagged'])} flagged'), color: c.danger),
    ]);
  }
}

/// Entry to the panel from the exam screens.
class OfflineExamEntryTile extends StatelessWidget {
  const OfflineExamEntryTile({super.key, required this.examId, required this.title});
  final int examId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfflineExamPanel(examId: examId, title: title))),
      child: Row(children: [
        Icon(Icons.offline_pin_rounded, color: c.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('الاختبار دون اتصال', 'Offline sitting'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
            Text(t('توزيع الاختبار وجمع الإجابات دون إنترنت، ثم التصحيح', 'Hand out and collect without internet, then grade'),
                style: appText(12, c: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    );
  }
}

class OfflineExamPanel extends StatefulWidget {
  const OfflineExamPanel({super.key, required this.examId, required this.title});
  final int examId;
  final String title;

  @override
  State<OfflineExamPanel> createState() => _OfflineExamPanelState();
}

class _OfflineExamPanelState extends State<OfflineExamPanel> {
  final _api = OfflineExamApi();
  final _hostState = OfflineExamHost.instance;
  late final RelayHostProvider? _host = _relayHost();
  Map<String, dynamic>? _ov;
  String? _error;
  String? _busy;
  bool _hosting = false;
  int _held = 0;

  RelayHostProvider? _relayHost() {
    if (!offlineExamsSupported) return null;
    try {
      return context.read<RelayHostProvider>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_hosting) {
      _hostState.teacher = false;
      _host?.releaseCheckIn();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (offlineExamsSupported) await OfflineExamSync.instance.flush();      // answers collected here go up first
    final r = await _api.overview(widget.examId);
    final held = offlineExamsSupported ? (await OfflineExamStore.instance.held()).length : 0;
    if (!mounted) return;
    setState(() {
      _held = held;
      if (r.ok) {
        _ov = r.map;
        _error = null;
      } else {
        _error = r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update') : (r.message.isEmpty ? '${r.code}' : r.message);
      }
    });
  }

  /// This phone keeps the package and its key, so it can hand the exam out with no internet in the hall.
  Future<bool> _keepCopy() async {
    if (!offlineExamsSupported) return false;
    final r = await _api.package(widget.examId);
    if (!r.ok) return false;
    return await OfflineExamSync.instance.savePackageReply(r.map, from: 'teacher') != null;
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = 'switch');
    final r = await _api.setEnabled(widget.examId, on);
    if (r.ok && on && _ov?['status'] == 'published') await _keepCopy();
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok) _ov = r.map;
    });
    if (!r.ok) appToast(offlineCodeText(r.code) == (r.code ?? '') ? r.message : offlineCodeText(r.code), error: true);
  }

  Future<void> _hall(bool on) async {
    if (on) {
      setState(() => _busy = 'hall');
      final ok = await _keepCopy() || await OfflineExamStore.instance.latestPackage(widget.examId) != null;
      if (!mounted) return;
      setState(() => _busy = null);
      if (!ok) return appToast(t('افتح هذه الصفحة متصلاً بالإنترنت مرة واحدة قبل الاختبار', 'Open this page once while online before the exam'), error: true);
      _hostState.teacher = true;
      await _host?.holdForCheckIn(asTeacher: true);
    } else {
      _hostState.teacher = false;
      await _host?.releaseCheckIn();
      await _load();
    }
    if (mounted) setState(() => _hosting = on);
  }

  Future<void> _uploadFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final bundles = <Map<String, dynamic>>[];
    for (final f in picked) {
      try {
        bundles.addAll(bundlesInFile(utf8.decode(await f.readAsBytes(), allowMalformed: true)));
      } catch (_) {}
    }
    if (!mounted || picked.isEmpty) return;
    if (bundles.isEmpty) return appToast(t('لم يُعثر على إجابات في الملفات المختارة', 'No answers found in the chosen files'), error: true);
    await _upload(bundles);
  }

  Future<void> _upload(List<Map<String, dynamic>> bundles) async {
    setState(() => _busy = 'upload');
    var ok = 0;
    final refused = <String>[];
    for (var i = 0; i < bundles.length; i += 50) {
      final r = await _api.submit(bundles.sublist(i, i + 50 > bundles.length ? bundles.length : i + 50));
      if (!r.ok) {
        refused.add(r.message);
        break;
      }
      for (final res in asMapList(r.map['results'])) {
        if (res['status'] == 'accepted' || res['status'] == 'duplicate') {
          ok++;
        } else {
          refused.add(offlineCodeText('${res['code']}'));
        }
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    appToast(refused.isEmpty
        ? t('رُفعت إجابات $ok طالب', 'Uploaded answers of $ok student(s)')
        : t('رُفع $ok، ولم يُقبل ${refused.length}: ${refused.toSet().join('، ')}', '$ok uploaded, ${refused.length} not accepted: ${refused.toSet().join(', ')}'),
        error: refused.isNotEmpty);
    await _load();
  }

  Future<void> _grade() async {
    if (!examAutoCorrectAllowed()) return;               // D-301: the Super Admin's switch
    setState(() => _busy = 'grade');
    final r = await _api.grade(widget.examId);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok) _ov = r.map;
    });
    if (!r.ok) return appToast(r.message, error: true);
    appToast(t('صُحّحت الأسئلة الموضوعية، وأُرسلت ${asInt(r.map['queued'])} ورقة للمصحح الآلي', 'Objective questions marked; ${asInt(r.map['queued'])} paper(s) sent to the auto-grader'));
  }

  void _chain(Map<String, dynamic> item) {
    showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSectionTitle(t('مسار التسليم', 'Delivery chain')),
          for (final h in asMapList(item['chain']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(h['sealed'] == true ? Icons.lock_outline_rounded : Icons.swap_horiz_rounded, size: 18, color: c.textMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(offlineStepText(h), style: appText(13.5, c: c.textDark)),
                    if (h['at'] != null && DateTime.tryParse('${h['at']}') != null)
                      Text(AppTime.dateTime(DateTime.parse('${h['at']}'.endsWith('Z') || '${h['at']}'.contains('+') ? '${h['at']}' : '${h['at']}Z')),
                          style: appText(11.5, c: c.textLight)),
                  ]),
                ),
              ]),
            ),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ov = _ov;
    final enabled = ov?['enabled'] == true;
    final items = asMapList(ov?['items']);
    final pkg = asMap(ov?['package']);
    return BasePage(
      key: const ValueKey('exam.offline.teacher'),
      appBar: AppHeader(title: widget.title),
      child: ov == null && _error == null
          ? const AppListSkeleton(items: 4)
          : AppRefresh(
              onRefresh: _load,
              child: ExamPageWidth(width: AppWidth.reading, builder: (side) => ListView(padding: EdgeInsets.fromLTRB(side, 12, side, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
                if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
                if (ov != null) ...[
                  AppCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AppSwitchTile(
                        title: t('السماح بالحل دون إنترنت', 'Allow taking it without internet'),
                        subtitle: t('تحفظ أجهزة الطلاب نسخة مشفرة لا تُفتح إلا عند بدء الاختبار', 'Students\' phones keep an encrypted copy that opens only when the exam starts'),
                        icon: Icons.offline_pin_rounded,
                        value: enabled,
                        onChanged: _busy != null ? null : _toggle,
                      ),
                      if (enabled && offlineExamsSupported)
                        AppSwitchTile(
                          title: t('توزيع وجمع في القاعة', 'Hand out and collect in the hall'),
                          subtitle: t('هذا الجهاز يعطي الاختبار لأجهزة الطلاب القريبة عند البدء ويجمع إجاباتهم', 'This phone gives the exam to nearby students at the start and collects their answers'),
                          icon: Icons.bluetooth_audio_rounded,
                          value: _hosting,
                          onChanged: _busy != null || ov['status'] != 'published' ? null : _hall,
                        ),
                      if (_hosting)
                        ValueListenableBuilder<int>(
                          valueListenable: _hostState.received,
                          builder: (_, n, _) => Text(t('استُلمت إجابات $n جهاز في هذه الجلسة', 'Answers received from $n phone(s) in this session'),
                              style: appText(12.5, c: c.textMedium)),
                        ),
                      if (enabled && pkg.isNotEmpty)
                        Text(t('النسخة ${pkg['package_id']} · ${asInt(pkg['questions'])} سؤال', 'Copy ${pkg['package_id']} · ${asInt(pkg['questions'])} questions'),
                            style: appText(12, c: c.textLight)),
                    ]),
                  ),
                  OfflineSummaryRow(summary: asMap(ov['summary'])),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _busy != null ? null : _uploadFiles,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(t('رفع ملفات الإجابات', 'Upload answers files'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (_held > 0) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _busy != null ? null : () async => _upload(await OfflineExamStore.instance.held()),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(t('رفع $_held إجابة محفوظة على هذا الجهاز', 'Upload $_held answer(s) kept on this phone'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AppPrimaryButton(label: t('تصحيح آلي للكل', 'Auto-grade all'), icon: Icons.auto_awesome_rounded, busy: _busy == 'grade',
                        onPressed: _busy != null ? null : _grade),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamReviewScreen(examId: widget.examId, examTitle: widget.title)))
                            .then((_) => _load()),
                        icon: const Icon(Icons.rate_review_outlined),
                        label: Text(t('مراجعة وتعديل الدرجات', 'Review and override'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final it in items) OfflineSubmissionTile(item: it, onTap: () => _chain(it)),
                  ] else if (enabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: AppEmpty(icon: Icons.inbox_outlined, title: t('لم تصل إجابات بعد', 'No answers yet')),
                    ),
                ],
              ])),
            ),
    );
  }
}
