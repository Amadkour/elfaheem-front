import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/component/number_pair.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/session_track_tabs.dart';

/// Opens the Add/Edit Lesson UI: the app's sheet (a bottom sheet on phones, the side panel on wide windows).
Future<void> showSessionFormSheet(
    BuildContext context, {
      TeacherSessionItem? existing,
      bool? openLive,
    }) async {
  final provider = context.read<TeacherCourseScreenProvider>();
  await showAppSideSheet<void>(
    context, mode: AppSheetMode.side,
    builder: (_) => ChangeNotifierProvider.value(
      value: provider,
      child: SessionFormSheet(existing: existing, provider: provider, openLive: openLive),
    ),
  );
}

class SessionFormSheet extends StatefulWidget {
  final TeacherSessionItem? existing;
  final TeacherCourseScreenProvider provider;
  final bool? openLive;

  const SessionFormSheet({
    super.key,
    this.existing,
    required this.provider,
    this.openLive,
  });

  @override
  State<SessionFormSheet> createState() => _SessionFormSheetState();
}

class _SessionFormSheetState extends State<SessionFormSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durCtrl = TextEditingController(text: '60');
  final _orderCtrl = TextEditingController(text: '0');
  String _type = 'pre-recorded';
  String _track = 'lecture';   // lecture (teacher) · section (assistant)
  bool _recordEnabled = false; // live sessions: "Record this session" (off until the host turns it on, D-1503)
  DateTime? _scheduled;

  String? _nameError;
  String? _dateError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _nameCtrl.text = s.name;
      _descCtrl.text = s.description ?? '';
      _type = s.type ?? 'pre-recorded';
      _track = s.track;
      _recordEnabled = s.recordEnabled;
      _scheduled = s.scheduledAt?.toLocal();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduled ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: context.colors.primary),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduled ?? DateTime.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: context.colors.primary),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _dateError = null;
    });
  }

  Future<void> _submit() async {
    final nameError =
    _nameCtrl.text.trim().isEmpty ? 'session_name_validator'.tr : null;
    final dateError = (_type == 'live' && _scheduled == null)
        ? 'pick_live_datetime'.tr
        : null;

    setState(() {
      _nameError = nameError;
      _dateError = dateError;
    });

    if (nameError != null || dateError != null) {
      HapticFeedback.selectionClick();
      // The date field lives inside the collapsible "session details"
      // section. If that's what's blocking submission, open the section so
      // the error is actually visible instead of silently failing.
      final detailsProvider = context.read<TeacherCourseScreenProvider>();
      if (dateError != null && !detailsProvider.openCourseDetails) {
        detailsProvider.onToggleOpenDetails();
      }
      return;
    }

    bool ok;
    TeacherSessionItem? r;
    if (_isEdit) {
      r = await widget.provider.updateSession(
        widget.existing!.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        type: _type,
        scheduledAt: _scheduled?.toUtc().toIso8601String(),
        durationMinutes: int.tryParse(_durCtrl.text),
        order: int.tryParse(_orderCtrl.text),
        track: _track,
        recordEnabled: _type == 'live' ? _recordEnabled : null,
      );
      ok = r != null;
    } else {
      r = await widget.provider.createSession(
        name: _nameCtrl.text.trim(),
        type: _type,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        scheduledAt: _scheduled?.toUtc().toIso8601String(),
        durationMinutes: int.tryParse(_durCtrl.text) ?? 60,
        order: int.tryParse(_orderCtrl.text) ?? 0,
        track: _track,
        recordEnabled: _type == 'live' ? _recordEnabled : null,
      );
      ok = r != null;
    }

    Helpers.showMessage(
      ok
          ? (_isEdit ? 'session_edited_success'.tr : 'session_added_success'.tr)
          : 'generic_error'.tr,
      isError: !ok,
    );
    if ((widget.openLive ?? false) && ok) {
      await widget.provider.startLive(r!.id);
      if (mounted) {
        await widget.provider.joinLive(context, r.id, r.courseId, 200, false);
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }


  @override
  Widget build(BuildContext context) {
    // watch (not widget.provider) — this is what makes the sheet rebuild
    // when onToggleOpenDetails()/notifyListeners() fires. Reading the plain
    // field off widget.provider never triggers a rebuild on its own, which
    // is why the details section previously appeared stuck closed.
    final liveProvider = context.watch<TeacherCourseScreenProvider>();
    final loading = liveProvider.submitLoading;

    final c = context.colors;
    // every field is open (Tea1Course "new session"): name · description · type · when · length · record, a footer
    // with Cancel and the one filled button pinned under the scroll
    return PopScope(
      canPop: !loading,
      child: Directionality(
        textDirection: Helpers.pageDirection,
        child: LayoutBuilder(builder: (context, box) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
              child: _Header(isEdit: _isEdit, loading: loading),
            ),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            // the sheet's own height bounds the scroll; with none (a bare page) the fields just lay out
            _MaybeFlexible(
              bounded: box.hasBoundedHeight,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                      controller: _nameCtrl,
                      label: 't1_cp_sf_name'.tr,
                      required: true,
                      errorText: _nameError,
                      onChanged: (_) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    const SizedBox(height: AppSpace.md),
                    AppField(
                      controller: _descCtrl,
                      label: '${'t1_cp_sf_desc'.tr} · ${'t1_cp_optional'.tr}',
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpace.md),
                    SessionTrackTabs(
                      value: _track,
                      showAll: false,
                      onChanged: (v) => setState(() => _track = v),
                    ),
                    const SizedBox(height: AppSpace.md),
                    _TypeSelector(
                      selected: _type,
                      onChanged: (t) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _type = t;
                          if (t != 'live') _dateError = null;
                        });
                      },
                    ),
                    if (_type == 'live') ...[
                      const SizedBox(height: AppSpace.md),
                      AppFieldLabel('t1_cp_sf_when'.tr),
                      _LiveDateTimePicker(
                        scheduled: _scheduled,
                        errorText: _dateError,
                        onTap: _pickDateTime,
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    NumberPair(
                      first: AppNumberField(
                        controller: _durCtrl,
                        label: 't1_cp_sf_duration'.tr,
                        min: 1,
                        step: 5,
                      ),
                      second: AppNumberField(
                        controller: _orderCtrl,
                        label: 'order_label'.tr,
                        min: 0,
                      ),
                    ),
                    if (_type == 'live') ...[
                      const SizedBox(height: AppSpace.md),
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                        child: AppSwitchTile(
                          title: 't1_cp_sf_rec_title'.tr,
                          subtitle: 't1_cp_sf_rec_sub'.tr,
                          value: _recordEnabled,
                          dense: true,
                          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            setState(() => _recordEnabled = v);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.md),
              child: LayoutBuilder(builder: (context, fb) {
                final cancel = AppButton.secondary(
                  label: 't1_cp_cancel'.tr,
                  size: AppButtonSize.lg,
                  expand: fb.maxWidth < _kFooterStackW,
                  onPressed: loading ? null : () => Navigator.of(context).pop(),
                );
                final save = AppButton.primary(
                  label: _isEdit ? 'save_changes'.tr : 't1_cp_sf_add'.tr,
                  icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
                  size: AppButtonSize.lg,
                  expand: true,
                  busy: loading,
                  onPressed: _submit,
                );
                // a narrow sheet (or a large text size) stacks them: the one filled button first
                if (fb.maxWidth < _kFooterStackW) {
                  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    save,
                    const SizedBox(height: AppSpace.xs),
                    cancel,
                  ]);
                }
                return Row(children: [cancel, const SizedBox(width: AppSpace.sm), Expanded(child: save)]);
              }),
            ),
          ],
        )),
      ),
    );
  }
}

/// Below this width the footer's two buttons stack.
const double _kFooterStackW = 330;

/// [Flexible] when the parent column has a bounded height, the child as it is otherwise.
class _MaybeFlexible extends StatelessWidget {
  const _MaybeFlexible({required this.bounded, required this.child});

  final bool bounded;
  final Widget child;

  @override
  Widget build(BuildContext context) => bounded ? Flexible(child: child) : child;
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — the editorial title, one line of direction, the close button
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isEdit;
  final bool loading;

  const _Header({required this.isEdit, required this.loading});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  isEdit ? 't1_cp_sf_edit'.tr : 't1_cp_sf_title'.tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.pageTitle(context),
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                isEdit ? 'edit_session_subtitle'.tr : 't1_cp_sf_sub'.tr,
                style: AppType.meta(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        IconButton(
          onPressed: loading ? null : () => Navigator.of(context).pop(),
          tooltip: 'close'.tr,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          style: IconButton.styleFrom(backgroundColor: c.inputBg, disabledBackgroundColor: c.inputBg),
          icon: Icon(
            Icons.close_rounded,
            size: AppIconSize.md,
            color: loading ? c.textLight : c.textMedium,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live date/time picker — a well like the fields around it
// ─────────────────────────────────────────────────────────────────────────────

class _LiveDateTimePicker extends StatelessWidget {
  final DateTime? scheduled;
  final String? errorText;
  final VoidCallback onTap;

  const _LiveDateTimePicker({
    required this.scheduled,
    required this.onTap,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = scheduled != null;
    final hasError = errorText != null;
    final radius = AppRadius.controlAll;
    final border = hasError ? c.danger : c.divider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.inputBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: border, width: hasError ? AppBorder.strong : AppBorder.hairline),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      picked
                          ? '${scheduled!.day.toString().padLeft(2, '0')}/${scheduled!.month.toString().padLeft(2, '0')}/${scheduled!.year}  ${AppTime.clockMinutes(scheduled!.hour * 60 + scheduled!.minute)}'
                          : 'pick_live_datetime'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFieldTextStyle(context).copyWith(
                        color: picked ? c.textDark : c.textLight,
                        fontWeight: picked ? FontWeight.w500 : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Icon(
                    picked ? Icons.check_circle_rounded : Icons.event_rounded,
                    color: picked ? c.success : c.textLight,
                    size: AppIconSize.md,
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xs),
            child: Text(
              errorText!,
              style: AppType.meta(context).copyWith(color: c.danger, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type selector (Live / Pre-recorded) — the kit's pill track
// ─────────────────────────────────────────────────────────────────────────────

class _TypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  static const _values = ['live', 'pre-recorded'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFieldLabel('t1_cp_sf_type'.tr),
        AppTabs(
          expand: true,
          index: selected == 'live' ? 0 : 1,
          items: [
            AppTabItem('live_type'.tr, icon: Icons.live_tv_rounded),
            AppTabItem('t1_cp_sf_prerec'.tr, icon: Icons.play_circle_outline_rounded),
          ],
          onChanged: (i) {
            onChanged(_values[i]);
          },
        ),
      ],
    );
  }
}
