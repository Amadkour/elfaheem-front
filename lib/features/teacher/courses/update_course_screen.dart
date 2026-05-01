// ─────────────────────────────────────────────────────────────────────────────
// update_course_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/primary_menue.dart';
import '../../../utils/widget/text_field.dart';
import '../home/teacher_models.dart';
import '../home/teacher_provider.dart';
import '../schedules/schedules_provider.dart';
import '../schedules/schedules_screen.dart';
import 'component/add_item_dialog.dart';
import 'component/gradient_button.dart';
import 'component/section_card.dart';

class UpdateCourseScreen extends StatefulWidget {
  final TeacherCourse course;

  const UpdateCourseScreen({super.key, required this.course});

  @override
  State<UpdateCourseScreen> createState() => _UpdateCourseScreenState();
}

class _UpdateCourseScreenState extends State<UpdateCourseScreen> {
  // ── Pure-UI state (controllers only) ────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _hoursCtrl;
  final ExpansibleController _categoryCtrl = ExpansibleController();

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _titleCtrl = TextEditingController(text: c.title);
    _descCtrl = TextEditingController(text: c.description ?? '');
    _priceCtrl = TextEditingController(text: c.price.toString());
    _hoursCtrl = TextEditingController(text: c.totalHours.toString());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherProvider>().initUpdateCourse(context, widget.course);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
  bool get showButton {
    return _titleCtrl.text != widget.course.title ||
        _descCtrl.text != (widget.course.description??'') ||
        double.parse(_priceCtrl.text) != widget.course.price ||
        double.parse(_hoursCtrl.text) != widget.course.totalHours;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<TeacherProvider>();

    final updated = await provider.submitUpdateCourse(
      widget.course,
      name: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      fees: double.tryParse(_priceCtrl.text),
      totalHours: double.tryParse(_hoursCtrl.text),
    );

    if (!mounted) return;

    if (updated != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الدورة بنجاح'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'حدث خطأ أثناء التحديث'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherProvider>();
    final form = provider.form;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              const ScreenAppBar(title: 'تعديل الدورة'),

              // ── Scrollable form ───────────────────────────────────────────
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Basic fields ──────────────────────────────────

                        ...TextFieldWithTitle(
                          controller: _titleCtrl,
                          label: 'عنوان الدورة',
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'يرجى إدخال عنوان الدورة'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        ...TextFieldWithTitle(
                          controller: _descCtrl,
                          label: 'وصف الدورة',
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),

                        ...TextFieldWithTitle(
                          controller: _priceCtrl,
                          label: 'course_fees'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'category'.tr,
                          style: TextStyle(fontSize: 14, fontFamily: 'bahji'),
                        ),
                        MyPrimaryMenu(
                          controller: _categoryCtrl,
                          initValue: provider.selectedSpecialization,
                          options: provider.specializations,
                          haveLogo: false,
                          onChange: (i) =>
                              provider.onChangeSpecialization(i, _categoryCtrl),
                          label: 'category'.tr,
                        ),
                        const SizedBox(height: 16),

                        ...TextFieldWithTitle(
                          controller: _hoursCtrl,
                          label: 'expected_hours'.tr,
                          keyboard: TextInputType.number,
                        ),
                        const SizedBox(height: 20),

                        // ── Schedule ──────────────────────────────────────
                        ChangeNotifierProvider.value(
                          value: context.watch<TeacherSchedulesProvider>()
                            ..initCourse(widget.course.id),
                          child: SectionCard(
                            icon: Icons.calendar_month_rounded,
                            title: 'الجدول الأسبوعي',
                            items: context
                                .read<TeacherSchedulesProvider>()
                                .schedules
                                .map((s) =>
                                    '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                                .toList(),
                            onAdd: () => TeacherSchedulesScreen
                                .openAddScheduleScreenSheet(context),
                            onRemove: (int index) => context
                                .read<TeacherSchedulesProvider>()
                                .removeSchedule(context
                                    .read<TeacherSchedulesProvider>()
                                    .schedules[index]
                                    .id),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Certificates ──────────────────────────────────
                        SectionCard(
                          icon: Icons.workspace_premium_rounded,
                          title: 'الشهادات',
                          items: form.certificates,
                          onAdd: () => addItemDialog('أضف شهادة',
                              provider.addFormCertificate, context),
                          onRemove: provider.removeFormCertificate,
                        ),
                        const SizedBox(height: 16),

                        // ── Tools ─────────────────────────────────────────
                        SectionCard(
                          icon: Icons.build_rounded,
                          title: 'الأدوات المطلوبة',
                          items: form.tools,
                          onAdd: () => addItemDialog(
                              'أضف أداة', provider.addFormTool, context),
                          onRemove: provider.removeFormTool,
                        ),
                        const SizedBox(height: 16),

                        // ── Prerequisites ─────────────────────────────────
                        SectionCard(
                          icon: Icons.checklist_rounded,
                          title: 'المتطلبات السابقة',
                          items: form.prerequisites,
                          onAdd: () => addItemDialog('أضف متطلب',
                              provider.addFormPrerequisite, context),
                          onRemove: provider.removeFormPrerequisite,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Save button ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  boxShadow: AppTheme.bottomNavShadow,
                ),
                child: GradientButton(
                  label:showButton? 'حفظ التعديلات':'لا يوجد تعديلات للحفظ',
                  isLoading: provider.isLoading,
                  enable: showButton,

                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget> TextFieldWithTitle(
    {required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text}) {
  return [
    Text(
      label,
      style: TextStyle(fontSize: 14, fontFamily: 'bahji'),
    ),
    SizedBox(
      height: 5,
    ),
    MyTextField(
      controller: controller,
      label: label,
      validator: validator,
      maxLine: maxLines,
      keyboard: keyboard,
    )
  ];
}
