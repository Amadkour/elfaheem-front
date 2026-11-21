// lib/features/org/students/student_ask_sheet.dart — "Ask the student" / "Request a meeting" (student lifecycle
// contract §7.3, PLAN §3.7, §3.9).
//
//   showStudentAskSheet(context, orgId, uid, {kind, source, name, canFullscreen, api})
//       one sheet, four parts on one screen: WHAT (Meeting · Information · Documents · Confirmation, a pill row),
//       the DETAILS that kind needs (a meeting's day, time, length, in person / online and place; questions or items
//       from the student's file; documents from the file's requirements; the sentence to confirm), HOW IT APPEARS
//       (Notification · Popup · Full screen, each with one line), and the DUE DATE with reminders. A plain preview
//       says what the student will see. POST …/students/{uid}/asks; a meeting whose student is busy (409
//       attendees_busy) shows who and when with "Pick another time" and "Book anyway" (force), as SchedulePage does.
//       Resolves to the created StudentAsk, or null when closed.
//   StudentAskView                 the body over plain values (the layout harness pumps it)
//   AskBusyCard · AskPreviewCard   its pieces
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../help/help_info_button.dart';
import 'student_asks_models.dart';
import 'student_status_models.dart' show StatusSource;
import 'student_status_sheet.dart' show StatusDateField;
import 'students_api.dart';
import 'students_models.dart' show StudentMissing;

/// Opens the ask sheet for student [uid]. [kind] preselects the kind (`meeting` for "Request a meeting"), [source]
/// is recorded on the ask (`{type: complaint, id}` from a complaint thread), [name] is the subtitle and the preview's
/// name. [canFullscreen] = the caller holds `student_status:update` (the server checks it too). [api] is for tests.
Future<StudentAsk?> showStudentAskSheet(BuildContext context, int orgId, int uid,
    {String kind = 'meeting', StatusSource? source, String? name, bool canFullscreen = true, StudentsApi? api}) {
  return showAppSheet<StudentAsk>(
    context,
    (ctx) => _AskSheet(
      uid: uid,
      api: api ?? StudentsApi(orgId),
      kind: askKinds.contains(kind) ? kind : 'meeting',
      source: source,
      name: name,
      canFullscreen: canFullscreen,
    ),
  );
}

class _AskSheet extends StatefulWidget {
  const _AskSheet({required this.uid, required this.api, required this.kind, this.source, this.name, this.canFullscreen = true});
  final int uid;
  final StudentsApi api;
  final String kind;
  final StatusSource? source;
  final String? name;
  final bool canFullscreen;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  late final AskDraft _d = AskDraft(kind: widget.kind, source: widget.source);
  late final TextEditingController _title = TextEditingController(text: _d.title);
  final TextEditingController _body = TextEditingController();
  final TextEditingController _place = TextEditingController();
  StudentMissing? _missing;
  bool _missingLoading = false;
  String? _missingError;
  List<AskBusy> _busy = const [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_needsMissing(_d.kind)) _loadMissing();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _place.dispose();
    super.dispose();
  }

  bool _needsMissing(String k) => k == 'data' || k == 'documents';

  Future<void> _loadMissing() async {
    if (_missingLoading) return;
    setState(() {
      _missingLoading = true;
      _missingError = null;
    });
    final r = await widget.api.missing(widget.uid);
    if (!mounted) return;
    setState(() {
      _missingLoading = false;
      if (r.ok) {
        _missing = StudentMissing.fromJson(r.map);
      } else {
        _missingError = askErrorText(r.error!);
      }
    });
  }

  void _edit(void Function() fn) => setState(() {
        fn();
        _error = null;
      });

  void _kind(String k) {
    _edit(() {
      final follow = _title.text.trim().isEmpty || _title.text == askDefaultTitle(_d.kind);
      _d.setKind(k);
      if (follow) _title.text = _d.title;
      _busy = const [];
    });
    if (_needsMissing(k) && _missing == null) _loadMissing();
  }

  void _presentation(String p) => _edit(() {
        _d.presentation = p;
        // a full-screen ask needs a due date within 7 days: offer three days when none is set
        if (p == 'fullscreen' && _d.dueAt == null) _d.dueAt = _endOfDay(DateTime.now().add(const Duration(days: 3)));
      });

  /// The end of [day] (local calendar day) in the platform zone, as a UTC instant.
  DateTime _endOfDay(DateTime day) => AppTime.fromZone(DateTime(day.year, day.month, day.day, 23, 59));

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final cur = _d.startsAt == null ? null : AppTime.toZone(_d.startsAt!.toUtc());
    final first = DateTime(now.year, now.month, now.day);
    final day = await showDatePicker(
      context: context,
      initialDate: cur ?? first.add(const Duration(days: 1)),
      firstDate: first,
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur?.hour ?? 10, minute: cur?.minute ?? 0));
    if (time == null || !mounted) return;
    _edit(() {
      _d.startsAt = AppTime.fromZone(DateTime(day.year, day.month, day.day, time.hour, time.minute));
      _d.force = false;
      _busy = const [];
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final cur = _d.dueAt == null ? null : AppTime.toZone(_d.dueAt!.toUtc());
    final day = await showDatePicker(
      context: context,
      initialDate: cur == null ? first.add(const Duration(days: 3)) : DateTime(cur.year, cur.month, cur.day),
      firstDate: first,
      lastDate: _d.presentation == 'fullscreen' ? first.add(const Duration(days: askFullscreenMaxDays - 1)) : DateTime(now.year + 2, 12, 31),
    );
    if (day == null || !mounted) return;
    _edit(() => _d.dueAt = _endOfDay(day));
  }

  Future<void> _submit({bool force = false}) async {
    if (_saving) return;
    _d.title = _title.text;
    _d.body = _body.text;
    _d.location = _place.text;
    if (force) _d.force = true;
    final why = _d.problemText();
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await widget.api.createAsk(widget.uid, _d.toJson());
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _saving = false;
        if (r.code == 'attendees_busy') {
          _busy = AskBusy.listOf(r.detail);
          if (_busy.isEmpty) _error = askErrorText(r.error!);
        } else {
          _error = askErrorText(r.error!);
        }
      });
      return;
    }
    final ask = StudentAsk.fromJson(r.map);
    showAppNotice(_d.kind == 'meeting'
        ? t('حُجز الاجتماع وأُبلغ الطالب', 'The meeting is booked and the student is told')
        : t('أُرسل الطلب إلى الطالب', 'The request was sent to the student'));
    Navigator.of(context).pop(ask);
  }

  @override
  Widget build(BuildContext context) {
    final meeting = _d.kind == 'meeting';
    return AppSheetContent(
      title: meeting ? t('طلب اجتماع', 'Request a meeting') : t('اطلب من الطالب', 'Ask the student'),
      subtitle: widget.name,
      icon: meeting ? Icons.event_available_rounded : Icons.forum_outlined,
      headerTrailing: const HelpInfoButton(pageId: kStudentRequestsHelpId, autoTour: false),
      children: [
        StudentAskView(
          draft: _d,
          title: _title,
          body: _body,
          place: _place,
          name: widget.name,
          missing: _missing,
          missingLoading: _missingLoading,
          missingError: _missingError,
          onRetryMissing: _loadMissing,
          busy: _busy,
          saving: _saving,
          error: _error,
          canFullscreen: widget.canFullscreen,
          onKind: _saving ? null : _kind,
          onPresentation: _saving ? null : _presentation,
          onEdit: _saving ? null : (fn) => _edit(() => fn(_d)),
          onPickStart: _saving ? null : _pickStart,
          onPickDue: _saving ? null : _pickDue,
          onClearDue: _saving || _d.presentation == 'fullscreen' ? null : () => _edit(() => _d.dueAt = null),
          onSubmit: () => _submit(),
          onForce: () => _submit(force: true),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The body over plain values
// ═════════════════════════════════════════════════════════════════════════════

class StudentAskView extends StatelessWidget {
  const StudentAskView({
    super.key,
    required this.draft,
    required this.title,
    required this.body,
    required this.place,
    this.name,
    this.missing,
    this.missingLoading = false,
    this.missingError,
    this.onRetryMissing,
    this.busy = const [],
    this.saving = false,
    this.error,
    this.canFullscreen = true,
    this.onKind,
    this.onPresentation,
    this.onEdit,
    this.onPickStart,
    this.onPickDue,
    this.onClearDue,
    this.onSubmit,
    this.onForce,
  });

  final AskDraft draft;
  final TextEditingController title, body, place;
  final String? name;

  /// What the student's file lacks (the data and documents to pick from); null = not loaded.
  final StudentMissing? missing;
  final bool missingLoading;
  final String? missingError;
  final VoidCallback? onRetryMissing;

  /// The 409 `attendees_busy` list; empty = none.
  final List<AskBusy> busy;
  final bool saving;
  final String? error;
  final bool canFullscreen;
  final ValueChanged<String>? onKind, onPresentation;
  final void Function(void Function(AskDraft d) edit)? onEdit;
  final VoidCallback? onPickStart, onPickDue, onClearDue, onSubmit, onForce;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final kIndex = askKinds.indexOf(d.kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // 1. what
      AppFieldLabel(t('ماذا تطلب؟', 'What do you need?')),
      AppTabs(
        key: const ValueKey('students.ask.kind'),
        items: [
          for (final k in askKinds) AppTabItem(askKindLabel(k), icon: _kindIcon(k)),
        ],
        index: kIndex < 0 ? 0 : kIndex,
        onChanged: (i) => onKind?.call(askKinds[i]),
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(askKindHint(d.kind), style: AppType.meta(context)),
      AppSpace.gapMd,
      AppField(
        key: const ValueKey('students.ask.title'),
        controller: title,
        label: t('العنوان الذي يراه الطالب', 'The title the student sees'),
        required: true,
        maxLength: 200,
        enabled: !saving,
      ),
      AppSpace.gapSm,
      // 2. details
      ...switch (d.kind) {
        'meeting' => _meeting(context, d),
        'data' => _data(context, d),
        'documents' => _documents(context, d),
        _ => _confirm(context),
      },
      AppSpace.gapMd,
      // 3. how it appears
      AppFieldLabel(t('كيف يظهر للطالب؟', 'How does the student see it?')),
      for (final p in askPresentations)
        if (p != 'fullscreen' || canFullscreen) _PresentationTile(value: p, selected: d.presentation == p, onTap: onPresentation),
      AppSpace.gapSm,
      // 4. due date and reminders
      StatusDateField(
        key: const ValueKey('students.ask.due'),
        label: t('آخر موعد للرد', 'Answer by'),
        required: d.presentation == 'fullscreen',
        value: d.dueAt == null ? null : AppTime.toZone(d.dueAt!.toUtc()),
        placeholder: t('بلا موعد نهائي', 'No due date'),
        onPick: onPickDue,
        onClear: onClearDue,
      ),
      if (d.dueAt != null) ...[
        AppFieldLabel(t('ذكّره قبل الموعد بـ', 'Remind them before the due date')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final n in const [7, 3, 1])
            AppChoiceChip(
              key: ValueKey('students.ask.remind.$n'),
              label: n == 1 ? t('يوم', '1 day') : t('$n أيام', '$n days'),
              selected: d.remindDays.contains(n),
              onTap: () => onEdit?.call((x) => x.remindDays.contains(n) ? x.remindDays.remove(n) : x.remindDays.add(n)),
            ),
        ]),
        AppSpace.gapSm,
      ],
      AppSpace.gapSm,
      AskPreviewCard(lines: askPreviewLines(_withText(d), name: name)),
      if (busy.isNotEmpty) ...[
        AppSpace.gapSm,
        AskBusyCard(busy: busy, onPickAnother: onPickStart, onForce: saving ? null : onForce),
      ],
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger),
      ],
      AppSpace.gapMd,
      AppButton.primary(
        key: const ValueKey('students.ask.submit'),
        label: d.kind == 'meeting' ? t('احجز وأبلغ الطالب', 'Book and tell the student') : t('أرسل إلى الطالب', 'Send to the student'),
        icon: d.kind == 'meeting' ? Icons.event_available_rounded : Icons.send_rounded,
        busy: saving,
        expand: true,
        onPressed: saving || busy.isNotEmpty ? null : onSubmit,
      ),
    ]);
  }

  /// The draft with the typed texts, for the preview (the controllers hold them until the save).
  AskDraft _withText(AskDraft d) => AskDraft(
        kind: d.kind,
        presentation: d.presentation,
        title: title.text,
        body: body.text,
        fields: d.fields,
        docKeys: d.docKeys,
        dueAt: d.dueAt,
        remindDays: d.remindDays,
        startsAt: d.startsAt,
        minutes: d.minutes,
        mode: d.mode,
        location: place.text,
      );

  static IconData _kindIcon(String k) => switch (k) {
        'meeting' => Icons.event_rounded,
        'data' => Icons.edit_note_rounded,
        'documents' => Icons.upload_file_rounded,
        _ => Icons.task_alt_rounded,
      };

  List<Widget> _meeting(BuildContext context, AskDraft d) {
    final start = d.startsAt;
    final when = start == null ? '' : AppTime.dateTime(start.toUtc());
    return [
      _TapWell(
        key: const ValueKey('students.ask.start'),
        label: t('اليوم والوقت', 'Day and time'),
        value: when,
        placeholder: t('اختر اليوم والوقت', 'Pick the day and time'),
        icon: Icons.schedule_rounded,
        required: true,
        onTap: onPickStart,
      ),
      AppDropdown<int>(
        key: const ValueKey('students.ask.length'),
        value: askMeetingLengths.contains(d.minutes) ? d.minutes : 30,
        decoration: InputDecoration(labelText: t('المدة', 'Length')),
        items: [
          for (final m in askMeetingLengths)
            DropdownMenuItem(value: m, child: Text(m < 60 ? t('$m دقيقة', '$m min') : (m % 60 == 0 ? t('${m ~/ 60} ساعة', '${m ~/ 60} h') : t('ساعة ونصف', '1 h 30 min')))),
        ],
        onChanged: onEdit == null
            ? null
            : (v) => onEdit!((x) {
                  x.minutes = v ?? 30;
                  x.force = false;
                }),
      ),
      AppSpace.gapSm,
      AppFieldLabel(t('الطريقة', 'Where')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(
          key: const ValueKey('students.ask.mode.offline'),
          label: t('حضورياً', 'In person'),
          icon: Icons.meeting_room_outlined,
          selected: d.mode == 'offline',
          onTap: () => onEdit?.call((x) => x.mode = 'offline'),
        ),
        AppChoiceChip(
          key: const ValueKey('students.ask.mode.online'),
          label: t('عبر الإنترنت', 'Online'),
          icon: Icons.videocam_outlined,
          selected: d.mode == 'online',
          onTap: () => onEdit?.call((x) => x.mode = 'online'),
        ),
      ]),
      AppSpace.gapSm,
      if (d.mode == 'offline')
        AppField(
          key: const ValueKey('students.ask.place'),
          controller: place,
          label: t('المكان', 'Place'),
          hint: t('مثل: مكتب شؤون الطلاب، الدور الثاني', 'e.g. Student affairs office, 2nd floor'),
          icon: Icons.place_outlined,
          maxLength: 255,
          enabled: !saving,
        )
      else
        Text(t('يُنشأ رابط غرفة الاجتماع تلقائياً ويظهر في تقويمكما.', 'A meeting-room link is made for you and shows in both calendars.'),
            style: AppType.meta(context)),
      AppSpace.gapSm,
      AppField(
        key: const ValueKey('students.ask.body'),
        controller: body,
        label: t('ملاحظة للطالب (اختياري)', 'A note for the student (optional)'),
        maxLines: 3,
        maxLength: 2000,
        enabled: !saving,
      ),
    ];
  }

  Widget _missingState(BuildContext context) {
    if (missingLoading && missing == null) return const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero);
    if (missingError != null && missing == null) return AppErrorState(message: missingError, onRetry: onRetryMissing, compact: true);
    return const SizedBox.shrink();
  }

  List<Widget> _data(BuildContext context, AskDraft d) {
    final m = missing;
    final fromFile = m?.fields ?? const [];
    final written = d.fields.where((f) => !f.caseField).toList();
    return [
      AppFieldLabel(t('من ملف الطالب', 'From the student\'s file')),
      _missingState(context),
      if (m != null && fromFile.isEmpty)
        Text(t('لا تنقص ملفه بيانات الآن. اكتب سؤالاً بالأسفل.', 'Nothing is missing from the file now. Write a question below.'), style: AppType.meta(context)),
      if (fromFile.isNotEmpty)
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final f in fromFile)
            AppChoiceChip(
              key: ValueKey('students.ask.case.${f.key}'),
              label: f.label,
              selected: d.fields.any((x) => x.caseField && x.key == f.key),
              onTap: () => onEdit?.call((x) => x.toggleCaseField(AskPickable(f.key, f.label, kind: f.kind))),
            ),
        ]),
      AppSpace.gapMd,
      AppFieldLabel(t('أسئلة تكتبها', 'Your own questions')),
      for (final f in written)
        _QuestionCard(
          key: ValueKey('students.ask.q.${f.key}'),
          field: f,
          onRemove: onEdit == null ? null : () => onEdit!((x) => x.fields.removeWhere((y) => y.key == f.key && !y.caseField)),
        ),
      _QuestionComposer(
        enabled: !saving && onEdit != null,
        onAdd: (label, kind, options) => onEdit?.call((x) {
          final q = x.addQuestion();
          q.labelAr = label;
          q.labelEn = label;
          q.kind = kind;
          q.options = options;
        }),
      ),
      AppSpace.gapSm,
      AppField(
        controller: body,
        label: t('ملاحظة للطالب (اختياري)', 'A note for the student (optional)'),
        maxLines: 2,
        maxLength: 5000,
        enabled: !saving,
      ),
    ];
  }

  List<Widget> _documents(BuildContext context, AskDraft d) {
    final m = missing;
    final docs = m?.documents ?? const [];
    return [
      AppFieldLabel(t('المستندات المطلوبة', 'Documents to upload'), required: true),
      _missingState(context),
      if (m != null && m.caseId == null)
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('ليس للطالب ملف التحاق، فلا يمكن طلب مستندات منه هنا.', 'This student has no admission file, so documents cannot be asked for here.'),
        )
      else if (m != null && docs.isEmpty)
        Text(t('لا ينقص ملفه أي مستند الآن.', 'No document is missing from the file now.'), style: AppType.meta(context)),
      for (final doc in docs)
        AppSwitchTile(
          key: ValueKey('students.ask.doc.${doc.key}'),
          title: doc.label,
          subtitle: doc.why.isEmpty ? null : doc.why,
          value: d.docKeys.contains(doc.key),
          onChanged: onEdit == null ? null : (_) => onEdit!((x) => x.toggleDoc(doc.key)),
        ),
      AppSpace.gapSm,
      AppField(
        controller: body,
        label: t('ملاحظة للطالب (اختياري)', 'A note for the student (optional)'),
        maxLines: 2,
        maxLength: 5000,
        enabled: !saving,
      ),
    ];
  }

  List<Widget> _confirm(BuildContext context) => [
        AppField(
          key: const ValueKey('students.ask.confirm'),
          controller: body,
          label: t('العبارة التي يؤكدها الطالب', 'The sentence the student confirms'),
          hint: t('مثل: أؤكد أن بيانات الاتصال في ملفي صحيحة.', 'e.g. I confirm the contact details in my file are correct.'),
          required: true,
          maxLines: 3,
          maxLength: 5000,
          enabled: !saving,
        ),
      ];
}

/// A tappable well that shows a picked value (the meeting's day and time).
class _TapWell extends StatelessWidget {
  const _TapWell({super.key, required this.label, required this.value, required this.placeholder, required this.icon, this.required = false, this.onTap});
  final String label, value, placeholder;
  final IconData icon;
  final bool required;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppFieldLabel(label, required: required),
          Semantics(
            button: true,
            label: '$label: ${value.isEmpty ? placeholder : value}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: AppRadius.controlAll,
              onTap: onTap,
              child: InputDecorator(
                isEmpty: value.isEmpty,
                decoration: appFieldDecoration(context, hint: placeholder, icon: icon, enabled: onTap != null),
                child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appFieldTextStyle(context)),
              ),
            ),
          ),
        ]),
      );
}

class _PresentationTile extends StatelessWidget {
  const _PresentationTile({required this.value, required this.selected, this.onTap});
  final String value;
  final bool selected;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (value) {
      'popup' => Icons.web_asset_rounded,
      'fullscreen' => Icons.fullscreen_rounded,
      _ => Icons.notifications_none_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: AppCard(
          key: ValueKey('students.ask.presentation.$value'),
          highlight: selected,
          padding: const EdgeInsets.all(AppSpace.sm),
          onTap: onTap == null ? null : () => onTap!(value),
          child: Row(children: [
            Icon(icon, size: AppIconSize.md, color: selected ? appToneInk(context, AppTone.brand) : c.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(askPresentationLabel(value), style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(askPresentationHint(value), style: AppType.meta(context)),
              ]),
            ),
            AppSpace.gapXs,
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: AppIconSize.md, color: selected ? appToneInk(context, AppTone.brand) : c.textLight),
          ]),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({super.key, required this.field, this.onRemove});
  final AskField field;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final f = field;
    final opts = f.kind == 'choice' ? f.options.join(' · ') : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.label, style: AppType.bodyStrong(context)),
              Text([askFieldKindLabel(f.kind), if (opts.isNotEmpty) opts].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          IconButton(
            tooltip: t('احذف السؤال', 'Remove the question'),
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ]),
      ),
    );
  }
}

/// "Add a question": the wording, the answer type and, for a choice, its options (one per line).
class _QuestionComposer extends StatefulWidget {
  const _QuestionComposer({required this.enabled, required this.onAdd});
  final bool enabled;
  final void Function(String label, String kind, List<String> options) onAdd;

  @override
  State<_QuestionComposer> createState() => _QuestionComposerState();
}

class _QuestionComposerState extends State<_QuestionComposer> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  String _kind = 'text';
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  void _add() {
    final label = _label.text.trim();
    final opts = [for (final o in _options.text.split('\n')) if (o.trim().isNotEmpty) o.trim()];
    if (label.isEmpty) {
      setState(() => _error = t('اكتب نص السؤال', 'Write the question'));
      return;
    }
    if (_kind == 'choice' && opts.length < 2) {
      setState(() => _error = t('اكتب خيارين على الأقل، كل خيار في سطر', 'Write at least two options, one per line'));
      return;
    }
    widget.onAdd(label, _kind, opts);
    setState(() {
      _label.clear();
      _options.clear();
      _kind = 'text';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppField(
            key: const ValueKey('students.ask.q.label'),
            controller: _label,
            label: t('السؤال', 'Question'),
            hint: t('مثل: ما رقم هاتف ولي الأمر؟', 'e.g. What is your guardian\'s phone number?'),
            maxLength: 200,
            enabled: widget.enabled,
            errorText: _error,
          ),
          AppSpace.gapXs,
          AppDropdown<String>(
            key: const ValueKey('students.ask.q.kind'),
            value: _kind,
            enabled: widget.enabled,
            decoration: InputDecoration(labelText: t('نوع الإجابة', 'Answer type')),
            items: [for (final k in askFieldKinds) DropdownMenuItem(value: k, child: Text(askFieldKindLabel(k)))],
            onChanged: (v) => setState(() => _kind = v ?? 'text'),
          ),
          if (_kind == 'choice') ...[
            AppSpace.gapXs,
            AppField(
              key: const ValueKey('students.ask.q.options'),
              controller: _options,
              label: t('الخيارات (خيار في كل سطر)', 'Options (one per line)'),
              maxLines: 4,
              enabled: widget.enabled,
            ),
          ],
          AppSpace.gapXs,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.tonal(
              key: const ValueKey('students.ask.q.add'),
              label: t('أضف السؤال', 'Add the question'),
              icon: Icons.add_rounded,
              onPressed: widget.enabled ? _add : null,
            ),
          ),
        ]),
      );
}

/// "What the student will see".
class AskPreviewCard extends StatelessWidget {
  const AskPreviewCard({super.key, required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      key: const ValueKey('students.ask.preview'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: appTintOn(context, c.primary), borderRadius: AppRadius.cardAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.visibility_outlined, size: AppIconSize.md, color: appToneInk(context, AppTone.brand)),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('ما سيراه الطالب', 'What the student will see'), style: AppType.label(context)),
            const SizedBox(height: AppSpace.xxs),
            for (final l in lines)
              Padding(padding: const EdgeInsets.only(bottom: AppSpace.xxs), child: Text(l, style: AppType.body(context))),
          ]),
        ),
      ]),
    );
  }
}

/// The 409 `attendees_busy` card: who is busy and when, "Pick another time", "Book anyway".
class AskBusyCard extends StatelessWidget {
  const AskBusyCard({super.key, required this.busy, this.onPickAnother, this.onForce});
  final List<AskBusy> busy;
  final VoidCallback? onPickAnother, onForce;

  @override
  Widget build(BuildContext context) {
    final ink = appToneInk(context, AppTone.warning);
    return Container(
      key: const ValueKey('students.ask.busy'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: appTintOn(context, appToneColor(context, AppTone.warning)), borderRadius: AppRadius.cardAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.event_busy_rounded, size: AppIconSize.md, color: ink),
          AppSpace.gapXs,
          Expanded(child: Text(t('الطالب مشغول في هذا الوقت', 'The student is busy at this time'), style: AppType.bodyStrong(context).copyWith(color: ink))),
        ]),
        AppSpace.gapXs,
        for (final b in busy) ...[
          if (b.name.isNotEmpty) Text(b.name, style: AppType.label(context)),
          if (b.line.isNotEmpty) Text(b.line, style: AppType.meta(context)),
          const SizedBox(height: AppSpace.xxs),
        ],
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
          AppButton.secondary(
            key: const ValueKey('students.ask.busy.another'),
            label: t('اختر وقتاً آخر', 'Pick another time'),
            icon: Icons.schedule_rounded,
            onPressed: onPickAnother,
          ),
          AppButton.tonal(
            key: const ValueKey('students.ask.busy.force'),
            label: t('احجز رغم ذلك', 'Book anyway'),
            onPressed: onForce,
          ),
        ]),
      ]),
    );
  }
}
