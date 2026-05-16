import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/primary_button.dart';
import '../../../../utils/widget/text_field.dart';
import '../../../student/models.dart';
import '../sessions_provider.dart';

class SessionFormSheet extends StatefulWidget {
  final TeacherSessionItem? existing;
  final int courseId;

  const SessionFormSheet({super.key, this.existing, required this.courseId});

  @override
  State<SessionFormSheet> createState() => _SessionFormSheetState();
}

class _SessionFormSheetState extends State<SessionFormSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durCtrl  = TextEditingController(text: '60');
  final _orderCtrl = TextEditingController(text: '0');
  String _type = 'pre-recorded';
  DateTime? _scheduled;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _nameCtrl.text  = s.name;
      _descCtrl.text  = s.description ?? '';
      _durCtrl.text   = s.durationMinutes.toString();
      _orderCtrl.text = s.order.toString();
      _type = s.type ?? 'pre-recorded';
      _scheduled =s.scheduledAt;
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
          colorScheme:  ColorScheme.light(primary: context.colors.primary),
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
          colorScheme:  ColorScheme.light(primary: context.colors.primary),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    if(mounted) setState(() => _scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final p = context.read<TeacherSessionsProvider>();
    bool ok;
    if (_isEdit) {
      final r = await p.updateSession(
        widget.existing!.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        type: _type,
        scheduledAt: _scheduled?.toUtc().toIso8601String(),
        durationMinutes: int.tryParse(_durCtrl.text),
        order: int.tryParse(_orderCtrl.text),
      );
      ok = r != null;
    } else {
      final r = await p.createSession(
        courseId: widget.courseId,
        name: _nameCtrl.text.trim(),
        type: _type,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        scheduledAt: _scheduled?.toUtc().toIso8601String(),
        durationMinutes: int.tryParse(_durCtrl.text) ?? 60,
        order: int.tryParse(_orderCtrl.text) ?? 0,
      );
      ok = r != null;
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text(
            ok ? (_isEdit ? 'تم تعديل الدرس' : 'تم إضافة الدرس') : 'حدث خطأ',
            style: const TextStyle(
                fontFamily: 'Tajawal',
                color: Colors.white,
                fontWeight: FontWeight.w600),
          ),
        ]),
        backgroundColor: ok ? context.colors.success : context.colors.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<TeacherSessionsProvider>().isLoading;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius:
           BorderRadius.vertical(top: Radius.circular(context.colors.radiusXL)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: context.colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title row
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: context.colors.primaryShadow,
                  ),
                  child: Icon(
                    _isEdit ? Icons.edit_rounded : Icons.add_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isEdit ? 'تعديل الدرس' : 'درس جديد',
                  style: context.colors.h2,
                ),
              ]),

              const SizedBox(height: 22),

              // Fields
              MyTextField(
                controller: _nameCtrl,
                label: 'اسم الدرس',
                validator: (v) => (v?.isEmpty ?? true) ? 'أدخل اسم الدرس' : null,
              ),
              const SizedBox(height: 14),
              MyTextField(
                controller: _descCtrl,
                label: 'وصف الدرس (اختياري)',
                maxLine: 2,
              ),
              const SizedBox(height: 14),

              // Type selector
              _TypeSelector(
                selected: _type,
                onChanged: (t) { if(mounted) setState(() => _type = t);},
              ),

              const SizedBox(height: 14),

              // Duration + Order row
              Row(children: [
                Expanded(
                  child: MyTextField(
                    controller: _durCtrl,
                    label: 'المدة (دقيقة)',
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MyTextField(
                    controller: _orderCtrl,
                    label: 'الترتيب',
                    keyboard: TextInputType.number,
                  ),
                ),
              ]),

              // Date picker (live only)
              if (_type == 'live') ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _pickDateTime,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _scheduled != null
                          ? context.colors.primaryLight
                          : context.colors.background,
                      borderRadius:
                      BorderRadius.circular(context.colors.radiusMedium),
                      border: Border.all(
                        color: _scheduled != null
                            ? context.colors.primary.withValues(alpha: 0.35)
                            : context.colors.divider,
                        width: _scheduled != null ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child:  Icon(Icons.event_rounded,
                            color: context.colors.primary, size: 17),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _scheduled != null
                              ? '${_scheduled!.day}/${_scheduled!.month}/${_scheduled!.year}  ${_scheduled!.hour.toString().padLeft(2, '0')}:${_scheduled!.minute.toString().padLeft(2, '0')}'
                              : 'اختر موعد الحصة المباشرة',
                          style: context.colors.label.copyWith(
                            color: _scheduled != null
                                ? context.colors.primary
                                : context.colors.textLight,
                          ),
                        ),
                      ),
                      Icon(
                        _scheduled != null
                            ? Icons.check_circle_rounded
                            : Icons.chevron_left_rounded,
                        color: _scheduled != null
                            ? context.colors.success
                            : context.colors.textLight,
                        size: 18,
                      ),
                    ]),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              MyPrimaryButton(
                label: _isEdit ? 'save_changes'.tr : 'add_session'.tr,
                isLoading: isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Type Selector ──────────────────────────────────────────────────────────────
class _TypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  static const _types = [
    ('pre-recorded', 'مسجّل مسبقاً', Icons.play_circle_outline_rounded),
    ('live', 'مباشر', Icons.live_tv_rounded),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('نوع الدرس',
          style: context.colors.label.copyWith(
              color: context.colors.textDark, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Row(
        children: _types.map((t) {
          final (v, l, i) = t;
          final isSelected = selected == v;
          final isLast = v == 'live';

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: isLast ? 0 : 6,
                right: isLast ? 6 : 0,
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
                    color: isSelected ? null : context.colors.background,
                    borderRadius:
                    BorderRadius.circular(context.colors.radiusMedium),
                    border: isSelected
                        ? null
                        : Border.all(color: context.colors.divider, width: 1),
                    boxShadow: isSelected
                        ? [
                      BoxShadow(
                        color: (v == 'live'
                            ? context.colors.danger
                            : context.colors.primary)
                            .withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(i,
                          size: 17,
                          color: isSelected
                              ? Colors.white
                              : context.colors.textMedium),
                      const SizedBox(width: 7),
                      Text(l,
                          style: context.colors.label.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : context.colors.textMedium,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
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