// lib/features/org/students/students_missing_sheet.dart — "What is missing?" for one student, completed in place
// (contract §4.4, §7.2; plan §3.5).
//
//   showMissingDataSheet(context, orgId, uid, name:, onChanged:)   loads GET …/missing and shows the sheet
//   MissingDataView(data:, loading:, error:, …)                     plain values: photos · documents · fields, each item
//                                                                   with WHY it is required and its due date, plus:
//     • a photo line: "Add the photo" (pick → the app's cropper → upload)
//     • a document line: "Upload" (jpg · png · pdf)
//     • a field line: its input right there and "Save" (text, phone, e-mail, number, date; a list field opens the file)
//     • the footer: "Remind the student" (once a day: a 429 `reminded_recently` turns into "You can remind again on …")
//                   and "Open the admission file" (the review page: waive / defer stay there)
//
// Uploads and edits go through the onboarding case routes (`POST cases/{id}/documents`, `PATCH cases/{id}`), which
// accept an active case's missing items since phase 3. "Remind" is `OnboardingApi.remindMissing`
// (`POST /orgs/{o}/students/{uid}/missing/remind` → {sent}).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart' show CropShape, showAppImageCropper;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../onboarding/onboarding_api.dart';
import '../onboarding/onboarding_errors.dart' show onbRemindNextAt;
import '../onboarding/onboarding_review.dart' show OnbReviewPage;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show OrgCall, orgErrorText;
import 'students_api.dart';
import 'students_models.dart';

/// The field kinds the sheet fills in place; any other kind (a list, a department, …) opens the admission file.
const missingInlineKinds = {null, 'text', 'textarea', 'phone', 'email', 'number', 'level', 'date', 'national_id'};

/// Opens the sheet for student [uid]; [name] is the subtitle. [onChanged] runs after each completed item (the
/// caller refreshes its badge). [api] / [onboarding] are for tests.
Future<void> showMissingDataSheet(BuildContext context, int orgId, int uid,
    {String? name, VoidCallback? onChanged, StudentsApi? api, OnboardingApi? onboarding}) {
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  return showAppSheet<void>(
    context,
    (ctx) => _MissingSheet(
      orgId: orgId,
      uid: uid,
      name: name,
      api: api ?? StudentsApi(orgId),
      onboarding: onboarding ?? OnboardingApi(),
      session: session,
      onChanged: onChanged,
    ),
  );
}

class _MissingSheet extends StatefulWidget {
  const _MissingSheet({
    required this.orgId,
    required this.uid,
    required this.api,
    required this.onboarding,
    this.name,
    this.session,
    this.onChanged,
  });
  final int orgId, uid;
  final String? name;
  final StudentsApi api;
  final OnboardingApi onboarding;
  final OrgSession? session;
  final VoidCallback? onChanged;

  @override
  State<_MissingSheet> createState() => _MissingSheetState();
}

class _MissingSheetState extends State<_MissingSheet> {
  StudentMissing? _data;
  String? _error;
  bool _loading = true, _reminding = false, _remindedNow = false;
  final _busy = <String>{};
  DateTime? _remindAgainAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.api.missing(widget.uid);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = StudentMissing.fromJson(r.map);
        _error = null;
      } else if (_data == null) {
        _error = orgErrorText(r.error!);
      }
    });
  }

  void _openFile(int caseId) {
    final nav = Navigator.of(context);
    final s = widget.session;
    final page = OnbReviewPage(orgId: widget.orgId, caseId: caseId, title: widget.name ?? '');
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => s == null ? page : ChangeNotifierProvider<OrgSession>.value(value: s, child: page)));
  }

  Future<void> _done(String key, OrgCall r, String ok) async {
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _busy.remove(key));
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(ok);
    widget.onChanged?.call();
    await _load(quiet: true);
    if (mounted) setState(() => _busy.remove(key));
  }

  Future<void> _upload(MissingItem item, {required bool photo}) async {
    final caseId = _data?.caseId;
    if (caseId == null) return;
    final f = await FilePicker.pickFile(
      type: photo ? FileType.image : FileType.custom,
      allowedExtensions: photo ? null : const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (f == null || !mounted) return;
    Uint8List? bytes;
    var name = f.name;
    if (photo) {
      final raw = await f.readAsBytes();
      if (!mounted) return;
      bytes = await showAppImageCropper(context, raw, shape: CropShape.square, allowShapeChange: false, allowTransparent: false);
      if (bytes == null || !mounted) return;
      if (!identical(bytes, raw)) name = '${item.key}.png';
    } else if (kIsWeb) {
      bytes = await f.readAsBytes();
    }
    if (!mounted) return;
    setState(() => _busy.add(item.key));
    final r = await widget.onboarding.uploadDocument(widget.orgId, caseId,
        reqKey: item.key, fileName: name, path: bytes == null ? f.path : null, bytes: bytes);
    await _done(item.key, r, photo ? t('أُضيفت الصورة', 'Photo added') : t('رُفع المستند', 'Document uploaded'));
  }

  Future<void> _saveField(MissingItem item, String value) async {
    final caseId = _data?.caseId;
    if (caseId == null) return;
    setState(() => _busy.add(item.key));
    final r = await widget.onboarding.patchCase(widget.orgId, caseId, {item.key: value});
    await _done(item.key, r, t('حُفظت البيانات', 'Saved'));
  }

  Future<void> _remind() async {
    setState(() => _reminding = true);
    final r = await widget.onboarding.remindMissing(widget.orgId, widget.uid);
    if (!mounted) return;
    setState(() => _reminding = false);
    if (r.ok) {
      final sent = r.map['sent'] != false;
      setState(() {
        _remindedNow = sent;
        if (sent) _remindAgainAt = DateTime.now().toUtc().add(const Duration(hours: 24));
      });
      showAppNotice(sent ? t('أُرسل التذكير إلى الطالب', 'The student was reminded') : t('لا شيء يُذكَّر به الآن', 'Nothing to remind about now'));
      return;
    }
    if (r.code == 'reminded_recently') {
      final at = onbRemindNextAt(r.error);
      setState(() {
        _remindedNow = false;
        _remindAgainAt = at ?? DateTime.now().toUtc().add(const Duration(hours: 24));
      });
      showAppNotice(remindAgainText(_remindAgainAt));
      return;
    }
    showAppNotice(orgErrorText(r.error!), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final caseId = d?.caseId;
    final canRemind = d != null && caseId != null && !d.isEmpty && (d.canUpload || d.canEdit);
    final again = _remindAgainAt;
    final waiting = again != null && again.isAfter(DateTime.now().toUtc());
    return AppSheetContent(
      title: t('البيانات الناقصة', 'Missing data'),
      subtitle: widget.name,
      icon: Icons.assignment_late_outlined,
      tone: AppTone.warning,
      children: [
        MissingDataView(
          data: d,
          loading: _loading,
          error: _error,
          onRetry: _load,
          onOpenFile: caseId == null ? null : () => _openFile(caseId),
          busyKeys: _busy,
          onUpload: d != null && d.canUpload ? _upload : null,
          onSaveField: d != null && d.canEdit ? _saveField : null,
          onRemind: canRemind ? _remind : null,
          reminding: _reminding,
          remindLocked: waiting,
          remindNote: waiting ? (_remindedNow ? t('أُرسل التذكير الآن.', 'Reminder sent just now.') : remindAgainText(again)) : null,
        ),
      ],
    );
  }
}

/// "The student was reminded in the last 24 hours. You can remind again on …".
String remindAgainText(DateTime? at) {
  final base = t('ذُكِّر الطالب خلال آخر 24 ساعة.', 'The student was reminded in the last 24 hours.');
  if (at == null) return base;
  return '$base ${t('يمكن التذكير مرة أخرى في', 'You can remind again on')} ${AppTime.dateTime(at)}';
}

/// The sheet's body over plain values (the layout harness pumps it). Every callback is optional: without them the
/// sheet is read only, as in phase 1.
class MissingDataView extends StatelessWidget {
  const MissingDataView({
    super.key,
    this.data,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onOpenFile,
    this.onUpload,
    this.onSaveField,
    this.onRemind,
    this.busyKeys = const {},
    this.reminding = false,
    this.remindLocked = false,
    this.remindNote,
  });
  final StudentMissing? data;
  final bool loading;

  /// The text to show (already `orgErrorText`); null = no error.
  final String? error;
  final VoidCallback? onRetry;

  /// "Open the admission file"; null = no button.
  final VoidCallback? onOpenFile;

  /// Upload a photo ([photo] true) or a document; null = no upload buttons (no right).
  final void Function(MissingItem item, {required bool photo})? onUpload;

  /// Save one field; null = the fields are read only.
  final void Function(MissingItem item, String value)? onSaveField;

  /// "Remind the student"; null = no button.
  final VoidCallback? onRemind;

  /// Items being saved / uploaded right now.
  final Set<String> busyKeys;
  final bool reminding;

  /// Reminded in the last 24 hours: the button is off and [remindNote] says when it comes back.
  final bool remindLocked;
  final String? remindNote;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (loading && d == null) return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
    if (error != null && d == null) return AppErrorState(message: error, onRetry: onRetry, compact: true);
    if (d == null || d.caseId == null) {
      return AppEmpty(
        icon: Icons.folder_off_outlined,
        title: t('لا يوجد ملف التحاق لهذا الطالب', 'This student has no admission file'),
        message: t('لا يُطلب منه شيء حالياً.', 'Nothing is asked of them right now.'),
      );
    }
    if (d.isEmpty) {
      return AppEmpty(
        icon: Icons.task_alt_rounded,
        title: t('لا ينقص شيء', 'Nothing is missing'),
        message: t('الملف مكتمل.', 'The file is complete.'),
        actionLabel: onOpenFile == null ? null : t('فتح ملف الالتحاق', 'Open the admission file'),
        onAction: onOpenFile,
      );
    }
    final up = onUpload, save = onSaveField;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Intro(total: d.total, due: d.dueAt, editable: up != null || save != null),
      if (d.photos.isNotEmpty)
        _Group(
          title: t('الصور', 'Photos'),
          icon: Icons.photo_camera_outlined,
          children: [
            for (final it in d.photos)
              _ItemCard(
                item: it,
                action: up == null
                    ? null
                    : _UploadButton(
                        key: ValueKey('students.missing.upload.${it.key}'),
                        label: t('إضافة الصورة', 'Add the photo'),
                        icon: Icons.add_a_photo_outlined,
                        busy: busyKeys.contains(it.key),
                        onPressed: () => up(it, photo: true),
                      ),
              ),
          ],
        ),
      if (d.documents.isNotEmpty)
        _Group(
          title: t('المستندات', 'Documents'),
          icon: Icons.description_outlined,
          children: [
            for (final it in d.documents)
              _ItemCard(
                item: it,
                showStatus: true,
                action: up == null
                    ? null
                    : _UploadButton(
                        key: ValueKey('students.missing.upload.${it.key}'),
                        label: it.status == 'rejected' ? t('رفع نسخة جديدة', 'Upload a new copy') : t('رفع', 'Upload'),
                        icon: Icons.upload_file_rounded,
                        busy: busyKeys.contains(it.key),
                        onPressed: () => up(it, photo: false),
                      ),
              ),
          ],
        ),
      if (d.fields.isNotEmpty)
        _Group(
          title: t('البيانات', 'Details'),
          icon: Icons.edit_note_rounded,
          children: [
            for (final it in d.fields)
              _ItemCard(
                item: it,
                body: save == null
                    ? null
                    : missingInlineKinds.contains(it.kind)
                        ? MissingFieldInput(
                            key: ValueKey('students.missing.input.${it.key}'),
                            item: it,
                            busy: busyKeys.contains(it.key),
                            onSave: (v) => save(it, v),
                          )
                        : (onOpenFile == null
                            ? null
                            : Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: AppButton.ghost(
                                  label: t('يُختار من ملف الالتحاق', 'Choose it in the admission file'),
                                  icon: Icons.folder_open_rounded,
                                  size: AppButtonSize.sm,
                                  onPressed: onOpenFile,
                                ),
                              )),
              ),
          ],
        ),
      if (onRemind != null || onOpenFile != null) ...[
        AppSpace.gapMd,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
          if (onOpenFile != null)
            AppButton.secondary(
              key: const ValueKey('students.missing.open'),
              label: t('فتح ملف الالتحاق', 'Open the admission file'),
              icon: Icons.folder_open_rounded,
              onPressed: onOpenFile,
            ),
          if (onRemind != null)
            AppButton.primary(
              key: const ValueKey('students.missing.remind'),
              label: t('تذكير الطالب', 'Remind the student'),
              icon: Icons.notifications_active_outlined,
              busy: reminding,
              onPressed: reminding || remindLocked ? null : onRemind,
            ),
        ]),
      ],
      if (remindNote != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(
            remindNote!,
            key: const ValueKey('students.missing.remind.note'),
            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
            textAlign: TextAlign.end,
          ),
        ),
    ]);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.total, this.due, this.editable = false});
  final int total;
  final DateTime? due;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final n = countText(total, ar1: 'ينقص بند واحد', ar2: 'ينقص بندان', arFew: 'تنقص {n} بنود', arMany: 'ينقص {n} بندًا',
        en1: '1 item is missing', en: '{n} items are missing');
    final d = due;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d == null ? n : '$n · ${t('آخر موعد', 'due by')} ${AppTime.date(d)}', style: AppType.bodyStrong(context)),
        if (editable)
          Text(
            t('أكمل كل بند هنا مباشرة، أو ذكّر الطالب ليكمله بنفسه.', 'Complete each item right here, or remind the student to do it.'),
            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
          ),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Semantics(header: true, child: Text('$title (${children.length})', style: AppType.label(context)))),
        ]),
        AppSpace.gapXs,
        for (final w in children) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: w),
      ]),
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({super.key, required this.label, required this.icon, required this.onPressed, this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) =>
      AppButton.tonal(label: label, icon: icon, size: AppButtonSize.sm, busy: busy, onPressed: busy ? null : onPressed);
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.showStatus = false, this.action, this.body});
  final MissingItem item;
  final bool showStatus;

  /// A button under the text (upload).
  final Widget? action;

  /// An input under the text (a field).
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final why = item.why;
    final due = item.dueAt;
    return AppCard(
      key: ValueKey('students.missing.${item.key}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.label, style: AppType.bodyStrong(context)),
        if (why.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs / 2),
          Text(why, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
        if (showStatus || due != null) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            if (showStatus)
              AppStatusBadge(
                label: missingStatusText(item.status),
                tone: item.status == 'rejected' ? AppTone.danger : (item.status == 'deferred' ? AppTone.info : AppTone.warning),
                dense: true,
              ),
            if (due != null) AppStatusBadge(label: '${t('حتى', 'Due')} ${AppTime.date(due)}', icon: Icons.event_outlined, dense: true),
          ]),
        ],
        if (body != null) ...[AppSpace.gapXs, body!],
        if (action != null) ...[AppSpace.gapXs, action!],
      ]),
    );
  }
}

/// One missing field's input and its Save button (plain values: [onSave] gets the trimmed text, a date as
/// `YYYY-MM-DD`).
class MissingFieldInput extends StatefulWidget {
  const MissingFieldInput({super.key, required this.item, required this.onSave, this.busy = false});
  final MissingItem item;
  final ValueChanged<String> onSave;
  final bool busy;

  @override
  State<MissingFieldInput> createState() => _MissingFieldInputState();
}

class _MissingFieldInputState extends State<MissingFieldInput> {
  final _ctrl = TextEditingController();
  DateTime? _day;
  String? _error;

  String? get _kind => widget.item.kind;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null && mounted) setState(() => _day = d);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _save() {
    if (_kind == 'date') {
      final d = _day;
      if (d != null) widget.onSave(_iso(d));
      return;
    }
    final v = _ctrl.text.trim();
    String? err;
    if (v.isEmpty) {
      err = t('اكتب القيمة أولاً', 'Type the value first');
    } else if (_kind == 'email' && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      err = t('بريد إلكتروني غير صالح', 'Not a valid e-mail address');
    } else if (_kind == 'phone' && v.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
      err = t('رقم هاتف غير صالح', 'Not a valid phone number');
    }
    setState(() => _error = err);
    if (err == null) widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    final day = _day;
    final save = AppButton.tonal(
      key: ValueKey('students.missing.save.${widget.item.key}'),
      label: t('حفظ', 'Save'),
      icon: Icons.check_rounded,
      size: AppButtonSize.sm,
      busy: busy,
      onPressed: busy || (_kind == 'date' && day == null) ? null : _save,
    );
    if (_kind == 'date') {
      return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppButton.secondary(
          label: day == null ? t('اختر التاريخ', 'Pick a date') : AppTime.date(DateTime.utc(day.year, day.month, day.day, 12)),
          icon: Icons.event_rounded,
          size: AppButtonSize.sm,
          onPressed: busy ? null : _pickDay,
        ),
        save,
      ]);
    }
    final numeric = _kind == 'number' || _kind == 'level' || _kind == 'national_id';
    final ltr = numeric || _kind == 'phone' || _kind == 'email';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(
        controller: _ctrl,
        label: widget.item.label,
        ltr: ltr,
        enabled: !busy,
        errorText: _error,
        maxLines: _kind == 'textarea' ? 3 : 1,
        keyboard: _kind == 'email'
            ? TextInputType.emailAddress
            : _kind == 'phone'
                ? TextInputType.phone
                : numeric
                    ? TextInputType.number
                    : TextInputType.text,
        inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        onSubmitted: (_) => _save(),
      ),
      Align(alignment: AlignmentDirectional.centerEnd, child: save),
    ]);
  }
}
