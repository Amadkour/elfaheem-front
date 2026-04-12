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
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durCtrl = TextEditingController(text: '60');
  final _orderCtrl = TextEditingController(text: '0');
  String _type = 'pre-recorded';
  DateTime? _scheduled;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _nameCtrl.text = s.name;
      _descCtrl.text = s.description ?? '';
      _durCtrl.text = s.durationMinutes.toString();
      _orderCtrl.text = s.order.toString();
      _type = s.type ?? 'pre-recorded';
      if (s.scheduledAt != null) _scheduled = DateTime.tryParse(s.scheduledAt!);
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
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_scheduled ?? DateTime.now()));
    if (time == null || !mounted) return;
    setState(() => _scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final p = context.read<TeacherSessionsProvider>();
    bool ok;
    if (_isEdit) {
      final r = await p.updateSession(widget.existing!.id,
          name: _nameCtrl.text.trim(),
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          type: _type,
          scheduledAt: _scheduled?.toUtc().toIso8601String(),
          durationMinutes: int.tryParse(_durCtrl.text),
          order: int.tryParse(_orderCtrl.text));
      ok = r != null;
    } else {
      final r = await p.createSession(
          courseId: widget.courseId,
          name: _nameCtrl.text.trim(),
          type: _type,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          scheduledAt: _scheduled?.toUtc().toIso8601String(),
          durationMinutes: int.tryParse(_durCtrl.text) ?? 60,
          order: int.tryParse(_orderCtrl.text) ?? 0);
      ok = r != null;
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ok ? (_isEdit ? 'تم تعديل الدرس' : 'تم إضافة الدرس') : 'حدث خطأ',
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: ok ? AppTheme.success : AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
                          decoration: BoxDecoration(
                              color: AppTheme.divider,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Text(_isEdit ? 'تعديل الدرس' : 'إضافة درس جديد',
                      style: AppTheme.h2),
                  const SizedBox(height: 20),
                  MyTextField(
                      controller: _nameCtrl,
                      label: 'اسم الدرس',
                      validator: (v) =>
                          (v?.isEmpty ?? true) ? 'أدخل اسم الدرس' : null),
                  const SizedBox(height: 14),
                  MyTextField(
                      controller: _descCtrl,
                      label: 'وصف الدرس (اختياري)',
                      maxLine: 2),
                  const SizedBox(height: 14),
                  _TypeSelector(
                      selected: _type,
                      onChanged: (t) => setState(() => _type = t)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: MyTextField(
                            controller: _durCtrl,
                            label: 'المدة (دقيقة)',
                            keyboard: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: MyTextField(
                            controller: _orderCtrl,
                            label: 'الترتيب',
                            keyboard: TextInputType.number)),
                  ]),
                  if (_type == 'live') ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                        onTap: _pickDateTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium)),
                          child: Row(children: [
                            const Icon(Icons.calendar_month_rounded,
                                color: AppTheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Text(
                                _scheduled != null
                                    ? '${_scheduled!.day}/${_scheduled!.month}/${_scheduled!.year}  ${_scheduled!.hour.toString().padLeft(2, '0')}:${_scheduled!.minute.toString().padLeft(2, '0')}'
                                    : 'اختر موعد الحصة المباشرة',
                                style: AppTheme.label.copyWith(
                                    color: _scheduled != null
                                        ? AppTheme.textDark
                                        : AppTheme.textLight)),
                          ]),
                        )),
                  ],
                  const SizedBox(height: 20),
                  MyPrimaryButton(
                      label: _isEdit ? 'save_changes'.tr : 'add_session'.tr,
                      isLoading: isLoading,
                      onPressed: _submit),
                ])),
      ),
    );
  }
}

// ── Type selector (live / pre-recorded) ───────────────────────────────────────
class _TypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  static const _types = [
    ('pre-recorded', 'مسجّل مسبقاً', Icons.play_circle_outline_rounded),
    ('live', 'مباشر', Icons.live_tv_rounded)
  ];

  @override
  Widget build(BuildContext ctx) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('نوع الدرس',
            style: AppTheme.label.copyWith(
                color: AppTheme.textDark, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
            children: _types.map((t) {
          final (v, l, i) = t;
          final a = selected == v;
          return Expanded(
              child: Padding(
                  padding: EdgeInsets.only(
                      left: v == 'live' ? 0 : 6, right: v == 'live' ? 6 : 0),
                  child: GestureDetector(
                      onTap: () => onChanged(v),
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                              color: a
                                  ? AppTheme.primary.withValues(alpha: 0.1)
                                  : AppTheme.background,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(
                                  color:
                                      a ? AppTheme.primary : AppTheme.divider,
                                  width: a ? 2 : 1)),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(i,
                                    size: 18,
                                    color: a
                                        ? AppTheme.primary
                                        : AppTheme.textMedium),
                                const SizedBox(width: 6),
                                Text(l,
                                    style: AppTheme.label.copyWith(
                                        color: a
                                            ? AppTheme.primary
                                            : AppTheme.textMedium,
                                        fontWeight: a
                                            ? FontWeight.w700
                                            : FontWeight.w500))
                              ])))));
        }).toList()),
      ]);
}
