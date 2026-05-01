// ─────────────────────────────────────────────────────────────────────────────
// add_course_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/schedules/schedules_provider.dart';
import 'package:flutter_education_app/features/teacher/schedules/schedules_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/primary_menue.dart';
import '../../../utils/widget/text_field.dart';
import '../home/teacher_provider.dart';
import 'component/add_item_dialog.dart';
import 'component/gradient_button.dart';
import 'component/section_card.dart';

class AddCourseScreen extends StatefulWidget {
  const AddCourseScreen({super.key});

  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  // ── Pure-UI state (controllers & image) ─────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final ExpansibleController _categoryCtrl = ExpansibleController();
  final ExpansibleController _teachingCtrl = ExpansibleController();
  File? _logoFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherProvider>().initAddCourse(context);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _hoursCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  // ── Step 1 submit ────────────────────────────────────────────────────────────

  Future<void> _submitStep1({required bool publishNow}) async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<TeacherProvider>();

    final created = await provider.submitAddCourseStep1(
      title: _titleCtrl.text.trim(),
      type: provider.selectedTeachingType?['text'] ?? 'recorded',
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      fees: double.tryParse(_priceCtrl.text) ?? 0,
      totalHours: double.tryParse(_hoursCtrl.text),
      maxStudents: int.tryParse(_maxCtrl.text),
      logoFile: _logoFile,
      publishNow: publishNow,
    );

    if (!mounted) return;

    if (created == null) {
      _snack(
          provider.errorMessage ?? 'حدث خطأ، حاول مرة أخرى', AppTheme.danger);
    }
    // On success the provider sets addStep = 2 and notifies → build re-runs.
  }

  // ── Step 2 submit ────────────────────────────────────────────────────────────

  Future<void> _submitStep2() async {
    await context.read<TeacherProvider>().submitAddCourseStep2();
    if (!mounted) return;
    _snack('تم حفظ الدورة بنجاح 🎉', AppTheme.success);
    Navigator.of(context).pop();
  }

  // ── Image picker ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (xFile != null) setState(() => _logoFile = File(xFile.path));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(
                title: provider.addStep == 1
                    ? 'إضافة دورة جديدة'
                    : 'تفاصيل الدورة',
              ),
              _StepIndicator(currentStep: provider.addStep),
              const SizedBox(height: 4),
              if (provider.isLoading && provider.addStep == 1)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: provider.addStep == 1
                      ? _buildStep1(provider)
                      : _buildStep2(provider),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1 UI ─────────────────────────────────────────────────────────────────

  Widget _buildStep1(TeacherProvider provider) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MyTextField(
                    controller: _titleCtrl,
                    label: 'course_title'.tr,
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'أدخل عنوان الدورة'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  MyTextField(
                    controller: _descCtrl,
                    label: 'course_description'.tr,
                    maxLine: 3,
                  ),
                  const SizedBox(height: 12),
                  MyTextField(
                    controller: _priceCtrl,
                    label: 'course_fees'.tr,
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: false),
                  ),
                  const SizedBox(height: 12),
                  MyPrimaryMenu(
                    controller: _categoryCtrl,
                    initValue: provider.selectedSpecialization,
                    options: provider.specializations,
                    haveLogo: false,
                    onChange: (i) =>
                        provider.onChangeSpecialization(i, _categoryCtrl),
                    label: 'category'.tr,
                  ),
                  const SizedBox(height: 12),
                  MyPrimaryMenu(
                    controller: _teachingCtrl,
                    initValue: provider.selectedTeachingType,
                    options: provider.teachingTypes,
                    haveLogo: false,
                    onChange: (i) =>
                        provider.onChangeTeachingType(i, _teachingCtrl),
                    label: 'teaching_type'.tr,
                  ),
                  const SizedBox(height: 12),
                  MyTextField(
                    controller: _hoursCtrl,
                    label: 'course_hours'.tr,
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: false),
                  ),
                  const SizedBox(height: 20),
                  Text('رفع صورة الدورة',
                      style: AppTheme.h3.copyWith(fontSize: 15)),
                  const SizedBox(height: 8),
                  _ImageUploader(
                      hasImage: _logoFile != null, onTap: _pickImage),
                ],
              ),
            ),
          ),
        ),
        _BottomButtons(
          isLoading: provider.isLoading,
          onDraft: () => _submitStep1(publishNow: false),
          onPublish: () => _submitStep1(publishNow: true),
        ),
      ],
    );
  }

  // ── Step 2 UI ─────────────────────────────────────────────────────────────────

  Widget _buildStep2(TeacherProvider provider) {
    final form = provider.form;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChangeNotifierProvider.value(
                  value: context.read<TeacherSchedulesProvider>(),
                  child: SectionCard(
                    icon: Icons.calendar_month_rounded,
                    title: 'الجدول الأسبوعي',
                    items: context.read<TeacherSchedulesProvider>().schedules
                        .map((s) =>
                            '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                        .toList(),
                    onAdd: () =>
                        TeacherSchedulesScreen.openAddScheduleScreenSheet(
                            context),
                    onRemove: provider.removeFormSchedule,
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.workspace_premium_rounded,
                  title: 'الشهادات',
                  items: form.certificates,
                  onAdd: () => addItemDialog(
                      'أضف شهادة', provider.addFormCertificate, context),
                  onRemove: provider.removeFormCertificate,
                ),
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.build_rounded,
                  title: 'الأدوات المطلوبة',
                  items: form.tools,
                  onAdd: () =>
                      addItemDialog('أضف أداة', provider.addFormTool, context),
                  onRemove: provider.removeFormTool,
                ),
                const SizedBox(height: 16),
                SectionCard(
                  icon: Icons.checklist_rounded,
                  title: 'المتطلبات السابقة',
                  items: form.prerequisites,
                  onAdd: () => addItemDialog(
                      'أضف متطلب', provider.addFormPrerequisite, context),
                  onRemove: provider.removeFormPrerequisite,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
              color: AppTheme.cardBg, boxShadow: AppTheme.bottomNavShadow),
          child: Row(
            children: [
              Expanded(
                child: _OutlineButton(
                  label: 'تخطي',
                  onTap: provider.isLoading
                      ? null
                      : () {
                          _snack('تم حفظ الدورة', AppTheme.primary);
                          Navigator.of(context).pop();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'حفظ التفاصيل',
                  isLoading: provider.isLoading,
                  onTap: _submitStep2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local UI-only widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;

  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            _Dot(label: '١', active: currentStep >= 1, done: currentStep > 1),
            Expanded(
              child: Container(
                height: 2,
                color: currentStep > 1 ? AppTheme.primary : AppTheme.divider,
              ),
            ),
            _Dot(label: '٢', active: currentStep >= 2, done: false),
          ],
        ),
      );
}

class _Dot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _Dot({required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppTheme.primary : AppTheme.divider,
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
        ),
      );
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _OutlineButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.primary, width: 1.5),
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'Cairo',
                )),
          ),
        ),
      );
}

class _ImageUploader extends StatelessWidget {
  final bool hasImage;
  final VoidCallback onTap;

  const _ImageUploader({required this.hasImage, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
          ),
          child: hasImage
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 48, color: AppTheme.success),
                    const SizedBox(height: 8),
                    Text('تم اختيار الصورة',
                        style:
                            AppTheme.label.copyWith(color: AppTheme.success)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Text('تغيير الصورة',
                          style: TextStyle(
                              color: AppTheme.textMedium,
                              fontSize: 12,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_rounded,
                        size: 48,
                        color: AppTheme.primary.withValues(alpha: 0.6)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Text('تحميل الصورة',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
        ),
      );
}

class _BottomButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onDraft;
  final VoidCallback onPublish;

  const _BottomButtons({
    required this.isLoading,
    required this.onDraft,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
            color: AppTheme.cardBg, boxShadow: AppTheme.bottomNavShadow),
        child: Row(children: [
          Expanded(
              child: _OutlineButton(
                  label: 'حفظ كمسودة', onTap: isLoading ? null : onDraft)),
          const SizedBox(width: 12),
          Expanded(
              child: GradientButton(
                  label: 'نشر الدورة', isLoading: isLoading, onTap: onPublish)),
        ]),
      );
}
