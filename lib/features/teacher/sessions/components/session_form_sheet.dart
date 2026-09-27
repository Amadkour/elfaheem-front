import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../auth/auth_widgets.dart';
import '../../../student/models.dart';
import '../sessions_provider.dart';

// Screens at/above this width get the centered "card" treatment instead of a
// full-width bottom sheet — covers desktop web and tablets in landscape.
const double _kWideBreakpoint = 720;

/// Opens the Add/Edit Lesson UI, picking the right chrome for the current
/// screen size: a bottom sheet on phones, a centered card on wide screens.
Future<void> showSessionFormSheet(
    BuildContext context, {
      TeacherSessionItem? existing,
      bool? openLive,
    }) async {
  final provider = context.read<TeacherCourseScreenProvider>();
  final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  final sheet = ChangeNotifierProvider.value(
    value: provider,
    child: SessionFormSheet(
      existing: existing,
      provider: provider,
      openLive: openLive,
      isWide: isWide,
    ),
  );

  if (isWide) {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: sheet,
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }
}

class SessionFormSheet extends StatefulWidget {
  final TeacherSessionItem? existing;
  final TeacherCourseScreenProvider provider;
  final bool? openLive;
  final bool isWide;

  const SessionFormSheet({
    super.key,
    this.existing,
    required this.provider,
    this.openLive,
    this.isWide = false,
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
      _scheduled = s.scheduledAt;
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
          colorScheme: ColorScheme.light(primary: context.colors.primary),
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
          colorScheme: ColorScheme.light(primary: context.colors.primary),
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
    final detailsOpen = liveProvider.openMoreDetailsForAddSession;
    final radius = context.colors.radiusXL;

    return PopScope(
      canPop: !loading,
      child: Container(
        constraints:
        widget.isWide ? const BoxConstraints(maxHeight: 680) : null,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: widget.isWide
              ? BorderRadius.circular(radius)
              : BorderRadius.vertical(top: Radius.circular(radius)),
          boxShadow: widget.isWide
              ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ]
              : null,
        ),
        child: Directionality(
          textDirection: Helpers.pageDirection,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: widget.isWide ? 20 : 10,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  (widget.isWide ? 20 : 28),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.isWide) _DragHandle(),
                  _Header(isEdit: _isEdit, loading: loading),
                  const SizedBox(height: 20),

                  _PremiumField(
                    controller: _nameCtrl,
                    label: 'session_name_label'.tr,
                    icon: Icons.badge_outlined,
                    errorText: _nameError,
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                  ),
                  const SizedBox(height: 14),

                  _ExpandableDetails(
                    expanded: detailsOpen,
                    onToggle: () => context
                        .read<TeacherCourseScreenProvider>()
                        .onToggleOpenDetails(),
                    children: [
                      _PremiumField(
                        controller: _descCtrl,
                        label: 'session_description_label'.tr,
                        icon: Icons.notes_rounded,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
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
                        const SizedBox(height: 14),
                        _LiveDateTimePicker(
                          scheduled: _scheduled,
                          errorText: _dateError,
                          onTap: _pickDateTime,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: _PremiumField(
                            controller: _durCtrl,
                            label: 'duration_minutes_label'.tr,
                            icon: Icons.timer_outlined,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PremiumField(
                            controller: _orderCtrl,
                            label: 'order_label'.tr,
                            icon: Icons.sort_rounded,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ]),
                    ],
                  ),

                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: _isEdit ? 'save_changes'.tr : 'add_session'.tr,
                    isLoading: loading,
                    iconBefore: true,
                    onPressed: _submit,
                    icon: Icons.add_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag handle (bottom-sheet only)
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: context.colors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — icon avatar, title, subtitle, close button
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isEdit;
  final bool loading;

  const _Header({required this.isEdit, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: context.colors.primaryShadow,
          ),
          child: Icon(
            isEdit ? Icons.edit_rounded : Icons.add_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'edit_session_title'.tr : 'new_session_title'.tr,
                style: context.colors.h2,
              ),
              const SizedBox(height: 2),
              Text(
                isEdit ? 'edit_session_subtitle'.tr : 'new_session_subtitle'.tr,
                style: context.colors.body.copyWith(
                  fontSize: 12,
                  color: context.colors.textLight,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: loading ? null : () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.close_rounded,
            size: 20,
            color: loading
                ? context.colors.textLight.withValues(alpha: 0.4)
                : context.colors.textMedium,
          ),
          tooltip: 'close'.tr,
          splashRadius: 20,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable "session details" section
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableDetails extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _ExpandableDetails({
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        border: Border.all(
          color: context.colors.textLight.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(Icons.tune_rounded, size: 16, color: context.colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'session_details'.tr,
                    style: context.colors.label.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: expanded ? 0.5 : 0,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: context.colors.primary),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium text field (mirrors the one used in add_material_sheet.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? errorText;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.icon,
    this.errorText,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'bahji',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.colors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            border: Border.all(
              color: hasError
                  ? context.colors.danger
                  : context.colors.textLight.withValues(alpha: 0.18),
              width: hasError ? 1.4 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13.5,
              color: context.colors.textDark,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: context.colors.textLight),
              border: InputBorder.none,
              contentPadding:
              const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                color: context.colors.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live date/time picker button
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
    final picked = scheduled != null;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: picked
                  ? context.colors.primaryLight
                  : context.colors.cardBg,
              borderRadius: BorderRadius.circular(context.colors.radiusMedium),
              border: Border.all(
                color: hasError
                    ? context.colors.danger
                    : (picked
                    ? context.colors.primary.withValues(alpha: 0.35)
                    : context.colors.textLight.withValues(alpha: 0.18)),
                width: picked || hasError ? 1.4 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event_rounded,
                    color: context.colors.primary, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  picked
                      ? '${scheduled!.day.toString().padLeft(2, '0')}/${scheduled!.month.toString().padLeft(2, '0')}/${scheduled!.year}  ${scheduled!.hour.toString().padLeft(2, '0')}:${scheduled!.minute.toString().padLeft(2, '0')}'
                      : 'pick_live_datetime'.tr,
                  style: context.colors.label.copyWith(
                    color: picked
                        ? context.colors.primary
                        : context.colors.textLight,
                  ),
                ),
              ),
              Icon(
                picked ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: picked ? context.colors.success : context.colors.textLight,
                size: 18,
              ),
            ]),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              errorText!,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 11,
                color: context.colors.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type Selector (Live / Pre-recorded)
// ─────────────────────────────────────────────────────────────────────────────

class _TypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final types = [
      ('live', 'live_type'.tr, Icons.live_tv_rounded),
      (
      'pre-recorded',
      'pre_recorded_type'.tr,
      Icons.play_circle_outline_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'session_type_label'.tr,
          style: context.colors.label.copyWith(
            color: context.colors.textDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: types.map((t) {
            final (v, l, i) = t;
            final isSelected = selected == v;
            final isFirst = v == 'live';

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: isFirst ? 6 : 0,
                  left: isFirst ? 0 : 6,
                ),
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? (v == 'live'
                          ? context.colors.dangerGradient
                          : context.colors.primaryGradient)
                          : null,
                      color: isSelected ? null : context.colors.cardBg,
                      borderRadius: BorderRadius.circular(
                        context.colors.radiusMedium,
                      ),
                      border: isSelected
                          ? null
                          : Border.all(
                          color: context.colors.textLight.withValues(alpha: 0.18)),
                      boxShadow: isSelected
                          ? [
                        BoxShadow(
                          color: (v == 'live'
                              ? context.colors.danger
                              : context.colors.primary)
                              .withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i,
                          size: 17,
                          color: isSelected
                              ? Colors.white
                              : context.colors.textMedium,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          l,
                          style: context.colors.label.copyWith(
                            color: isSelected
                                ? Colors.white
                                : context.colors.textMedium,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}