// "Print bubble sheets" (brief 3, D-156): what the engine will print (`GET …/omr/sheets`), then blank sheets per form ×
// copies or one named sheet per student (the forms cycle), as a PDF (`POST …/omr/sheets`) saved or shared with the
// same helpers the table exports use (data_lab_saver: a browser download on the web, Downloads on desktop, the share
// sheet on phones). Only the built-in sheets are printable: a learned template is the school's own printed sheet.
// The named sheets are chosen by name from the exam's audience (`OmrAudiencePicker`, `GET …/omr/students`), never
// typed as raw ids.
// Print modes (a server whose describe lists `modes`): Pre-filled (name + number printed, the number's bubbles shaded)
// · Name only (name + the number's last 4 printed, bubbles left to the student) · Blank — only the modes the server
// lists, each explained in one line, Pre-filled replaced by one line on why when it is missing; the student sheets in
// order By name / By student number (the server sorts: the ids go as chosen) and an Index page first (default on).
// An older server (no `modes`) keeps blank / named and the old body (it refuses unknown fields).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../review/omr_review.dart' show OmrReviewApi;
import 'omr_audience_picker.dart';
import 'omr_scan.dart';
import '../omr_counts.dart';

Future<void> showOmrSheetsSheet(BuildContext context, {required int examId, OmrScanApi? api}) =>
    showAppSheet<void>(context, (_) => OmrSheetsSheet(examId: examId, api: api));

String omrIdKindText(String kind) => switch (kind) {
      'shaded' => t('رقم الطالب بالتظليل', 'shaded student ID'),
      'handwritten' => t('رقم الطالب بخط اليد', 'handwritten student ID'),
      'printed' => t('رقم مطبوع', 'printed ID'),
      'qr' => t('رمز QR', 'QR code'),
      _ => t('بلا رقم طالب', 'no student ID'),
    };

/// The modes offered: the server's list, or (an older server) blank + named.
List<OmrPrintMode> omrOfferedModes(OmrSheetsInfo info) => info.modes ?? const [OmrPrintMode.named, OmrPrintMode.blank];

/// The mode a sheet opens on: Name only when offered, else the first offered one.
OmrPrintMode omrDefaultMode(OmrSheetsInfo info) {
  final m = omrOfferedModes(info);
  return m.contains(OmrPrintMode.named) ? OmrPrintMode.named : (m.isEmpty ? OmrPrintMode.blank : m.first);
}

String omrModeTitle(OmrPrintMode m) => switch (m) {
      OmrPrintMode.prefilled => t('مظلّلة مسبقًا', 'Pre-filled'),
      OmrPrintMode.named => t('بالاسم فقط', 'Name only'),
      OmrPrintMode.blank => t('فارغة', 'Blank'),
    };

String omrModeLine(OmrPrintMode m) => switch (m) {
      OmrPrintMode.prefilled => t('اسم الطالب ورقمه مطبوعان، وفقاعات الرقم مظلّلة جاهزة', "The student's name and number printed, the number's bubbles already shaded"),
      OmrPrintMode.named => t('الاسم وآخر 4 أرقام مطبوعة، والطالب يظلّل رقمه بنفسه', 'Name and the last 4 digits printed; the student shades the number'),
      OmrPrintMode.blank => t('بلا اسم ولا رقم — نسخ احتياطية لأي طالب', 'No name or number — spare copies for anyone'),
    };

IconData _modeIcon(OmrPrintMode m) => switch (m) {
      OmrPrintMode.prefilled => Icons.how_to_reg_outlined,
      OmrPrintMode.named => Icons.badge_outlined,
      OmrPrintMode.blank => Icons.copy_all_rounded,
    };

/// One mode: its title and one line; a radio card.
class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.selected, required this.onTap, this.unavailable});
  final OmrPrintMode mode;
  final bool selected;
  final VoidCallback onTap;

  /// Why this mode is not offered: the card is drawn disabled with this line instead of its description.
  final String? unavailable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    final off = unavailable != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: !off,
      enabled: !off,
      child: Material(
        color: selected ? c.primary.withValues(alpha: .08) : (off ? c.background : c.cardBg),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          key: ValueKey(off ? 'omr.sheets.mode.${mode.name}.off' : 'omr.sheets.mode.${mode.name}'),
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: off ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: selected ? c.primary : c.textLight.withValues(alpha: .3), width: selected ? 1.6 : 1),
            ),
            child: Row(children: [
              Icon(_modeIcon(mode), color: off ? c.textLight : (selected ? ink : c.textMedium)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // the reason line already says "… is not available": the title stays the mode's name
                  Text(omrModeTitle(mode), style: appText(14.5, w: FontWeight.w700, c: off ? c.textMedium : c.textDark)),
                  const SizedBox(height: 2),
                  if (off)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.info_outline_rounded, size: 16, color: c.textMedium)),
                      const SizedBox(width: AppSpace.xxs),
                      Expanded(
                          child: Text(unavailable!,
                              key: ValueKey(mode == OmrPrintMode.prefilled ? 'omr.sheets.prefilled.missing' : 'omr.sheets.${mode.name}.missing'),
                              style: appText(12.5, c: c.textMedium, h: 1.35))),
                    ])
                  else
                    Text(omrModeLine(mode), style: appText(12.5, c: c.textMedium, h: 1.35)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              if (off)
                Icon(Icons.block_rounded, color: c.textLight)
              else
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: selected ? ink : c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The options, plain values (the layout harness pumps it).
class OmrSheetsOptionsView extends StatelessWidget {
  const OmrSheetsOptionsView({
    super.key,
    required this.info,
    required this.mode,
    required this.onMode,
    required this.forms,
    required this.onForm,
    required this.copiesController,
    required this.students,
    required this.onDownload,
    required this.onShare,
    this.order = OmrPrintOrder.name,
    this.onOrder,
    this.index = true,
    this.onIndex,
    this.busy = false,
    this.error,
  });

  final OmrSheetsInfo info;

  /// Pre-filled / Name only = one sheet per chosen student; Blank = sheets × copies.
  final OmrPrintMode mode;
  final ValueChanged<OmrPrintMode> onMode;
  final OmrPrintOrder order;
  final ValueChanged<OmrPrintOrder>? onOrder;
  final bool index;
  final ValueChanged<bool>? onIndex;
  final Set<String> forms;
  final ValueChanged<String> onForm;
  final TextEditingController copiesController;

  /// The students to name (an `OmrAudiencePicker`, or its body under the harness), shown for named sheets.
  final Widget students;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final summary = t('${omrQuestionsText(info.questions)} على ورقة من ${omrQuestionsText(info.sheetQuestions, after: true)} · ${omrIdKindText(info.idKind)}',
        '${info.questions} questions on a ${info.sheetQuestions}-question sheet · ${omrIdKindText(info.idKind)}');
    if (!info.printable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppBanner(icon: Icons.info_outline_rounded, text: omrCodeText('template_not_printable')),
        const SizedBox(height: AppSpace.sm),
        Text(summary, style: appText(13.5, c: c.textMedium)),
      ]);
    }
    final named = mode != OmrPrintMode.blank;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(summary, style: appText(13.5, c: c.textMedium, h: 1.4)),
      const SizedBox(height: AppSpace.md),
      if (!info.hasModes)
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(label: t('أوراق فارغة', 'Blank sheets'), icon: Icons.copy_all_rounded, selected: !named, onTap: () => onMode(OmrPrintMode.blank)),
          AppChoiceChip(
              label: t('ورقة باسم كل طالب', 'A named sheet per student'), icon: Icons.badge_outlined, selected: named, onTap: () => onMode(OmrPrintMode.named)),
        ])
      else ...[
        Text(t('ما يُطبع على الورقة', 'What each sheet shows'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        // every mode, in order: an unavailable one disabled with its reason (D-161: blank is dropped on purpose when
        // the students' numbers do not fit the ID zone), never hidden without a word
        for (final m in OmrPrintMode.values) ...[
          _ModeOption(mode: m, selected: m == mode, onTap: () => onMode(m), unavailable: info.missingText(m)),
          const SizedBox(height: AppSpace.xs),
        ],
      ],
      if (info.forms.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('النماذج', 'Models'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final f in info.forms) AppChoiceChip(label: t('نموذج $f', 'Model $f'), selected: forms.contains(f), onTap: () => onForm(f)),
        ]),
        if (named) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('تتناوب النماذج المختارة على الطلاب بالترتيب', 'The chosen models alternate across the students in order'), style: appText(12.5, c: c.textMedium)),
        ],
      ],
      const SizedBox(height: AppSpace.md),
      if (!named)
        Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: copiesController, label: t('عدد النسخ لكل نموذج', 'Copies of each model'), min: 1))
      else ...[
        students,
        const SizedBox(height: AppSpace.xs),
        Text(t('حتى ${OmrLimits.maxStudentSheets} ورقة في المرة', 'Up to ${OmrLimits.maxStudentSheets} sheets at a time'), style: appText(12.5, c: c.textMedium)),
        if (info.hasModes) ...[
          const SizedBox(height: AppSpace.md),
          Text(t('ترتيب الأوراق', 'Sheet order'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(
                key: const ValueKey('omr.sheets.order.name'),
                label: t('حسب الاسم', 'By name'),
                icon: Icons.sort_by_alpha_rounded,
                selected: order == OmrPrintOrder.name,
                onTap: () => onOrder?.call(OmrPrintOrder.name)),
            AppChoiceChip(
                key: const ValueKey('omr.sheets.order.identifier'),
                label: t('حسب رقم الطالب', 'By student number'),
                icon: Icons.pin_outlined,
                selected: order == OmrPrintOrder.identifier,
                onTap: () => onOrder?.call(OmrPrintOrder.identifier)),
          ]),
          const SizedBox(height: AppSpace.xs),
          AppSwitchTile(
            key: const ValueKey('omr.sheets.index'),
            title: t('صفحة فهرس في البداية', 'Index page first'),
            subtitle: t('قائمة بالأسماء والنماذج وأرقام الصفحات لتوزيع الأوراق بسرعة', 'Names, models and page numbers, to hand the sheets out quickly'),
            icon: Icons.format_list_numbered_rounded,
            value: index,
            onChanged: onIndex,
          ),
        ],
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('تنزيل PDF', 'Download PDF'), icon: Icons.download_rounded, onPressed: busy ? null : onDownload, busy: busy),
      const SizedBox(height: AppSpace.xs),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        onPressed: busy ? null : onShare,
        icon: const Icon(Icons.share_rounded, size: 18),
        label: Text(t('مشاركة PDF', 'Share PDF')),
      ),
    ]);
  }
}

class OmrSheetsSheet extends StatefulWidget {
  const OmrSheetsSheet({super.key, required this.examId, this.api, this.audienceApi});
  final int examId;
  final OmrScanApi? api;
  final OmrReviewApi? audienceApi;

  @override
  State<OmrSheetsSheet> createState() => _OmrSheetsSheetState();
}

class _OmrSheetsSheetState extends State<OmrSheetsSheet> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  final _copies = TextEditingController(text: '1');
  Set<int> _selected = {};
  final Set<String> _forms = {};
  OmrSheetsInfo? _info;
  String? _loadError;
  String? _error;
  OmrPrintMode _mode = OmrPrintMode.blank;
  OmrPrintOrder _order = OmrPrintOrder.name;
  bool _index = true;
  bool _busy = false;

  bool get _named => _mode != OmrPrintMode.blank;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _copies.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.sheetsInfo(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _info = OmrSheetsInfo.fromJson(r.map);
        // a server with modes opens on Name only; an older one on blank sheets, as before
        _mode = _info!.hasModes ? omrDefaultMode(_info!) : OmrPrintMode.blank;
        _forms
          ..clear()
          ..addAll(_info!.forms);
      } else {
        _loadError = omrErrorText(r);
      }
    });
  }

  Future<Uint8List?> _make() async {
    // in the order they were chosen: the server sorts them (by name or by student number)
    final ids = _named ? _selected.toList() : <int>[];
    final copies = int.tryParse(_copies.text.trim()) ?? 0;
    if (_named && ids.isEmpty) {
      setState(() => _error = t('اختر طالبًا واحدًا على الأقل', 'Choose at least one student'));
      return null;
    }
    if (_named && ids.length > OmrLimits.maxStudentSheets) {
      setState(() => _error = omrCodeText('too_many_sheets'));
      return null;
    }
    if (!_named && (copies < 1 || copies > OmrLimits.maxCopies)) {
      setState(() => _error = t('عدد النسخ من 1 إلى ${OmrLimits.maxCopies}', 'Copies: 1 to ${OmrLimits.maxCopies}'));
      return null;
    }
    final info = _info!;
    final forms = [for (final f in info.forms) if (_forms.contains(f)) f];
    if (info.forms.isNotEmpty && forms.isEmpty) {
      setState(() => _error = t('اختر نموذجًا واحدًا على الأقل', 'Choose at least one model'));
      return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final (bytes, fail) = await _api.sheetsPdf(widget.examId,
        omrSheetsBody(forms: forms, copies: copies, studentIds: ids, mode: info.hasModes ? _mode : null, order: _order, index: _index));
    if (!mounted) return null;
    setState(() {
      _busy = false;
      if (fail != null) _error = omrErrorText(fail);
    });
    return bytes;
  }

  String get _name => 'bubble-sheets-${widget.examId}.pdf';

  Future<void> _download() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await saver.dlSaveBytes(bytes, _name, 'application/pdf');
      showAppNotice(t('حُفظ الملف', 'File saved'));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      showAppNotice(t('تعذّر حفظ الملف', 'Could not save the file'), error: true);
    }
  }

  Future<void> _share() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await saver.dlShareBytes(bytes, _name, 'application/pdf');
    } catch (_) {
      showAppNotice(t('تعذّرت المشاركة', 'Could not share'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return AppSheetContent(title: t('طباعة أوراق التظليل', 'Print bubble sheets'), children: [
      if (info == null && _loadError == null) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
      if (_loadError != null) AppBanner(icon: Icons.error_outline_rounded, text: _loadError!, color: context.colors.danger),
      if (info != null)
        OmrSheetsOptionsView(
          info: info,
          mode: _mode,
          onMode: (m) => setState(() {
            _mode = m;
            _error = null;
          }),
          order: _order,
          onOrder: (o) => setState(() => _order = o),
          index: _index,
          onIndex: (v) => setState(() => _index = v),
          forms: _forms,
          onForm: (f) => setState(() => _forms.contains(f) ? _forms.remove(f) : _forms.add(f)),
          copiesController: _copies,
          students: OmrAudiencePicker(
            examId: widget.examId,
            api: widget.audienceApi,
            selected: _selected,
            onChanged: (s) => setState(() {
              _selected = s;
              _error = null;
            }),
          ),
          onDownload: _download,
          onShare: _share,
          busy: _busy,
          error: _error,
        ),
    ]);
  }
}
