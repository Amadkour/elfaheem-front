// ─────────────────────────────────────────────────────────────────────────────
// add_course_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';

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
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final ExpansibleController _categoryCtrl = ExpansibleController();
  final ExpansibleController _teachingCtrl = ExpansibleController();

  // FIX: store both XFile and pre-read bytes.
  // Bytes are read once on pick → Image.memory() renders synchronously
  // on both Web and Mobile (no dart:io File needed anywhere).
  XFile? _logoFile;
  Uint8List? _logoBytes;

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

  // ── Image picker ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const ImageSourceSheet(),
    );
    if (source == null) return;

    final xFile = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xFile == null) return;

    // FIX: read bytes right away — works on Web + Mobile, no dart:io needed
    final bytes = await xFile.readAsBytes();
    setState(() {
      _logoFile = xFile;
      _logoBytes = bytes;
    });
  }

  // ── Step 1 submit ────────────────────────────────────────────────────────────

  Future<void> _submitStep1({required bool publishNow}) async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<TeacherProvider>();

    final created = await provider.submitAddCourseStep1(
      title: _titleCtrl.text.trim(),
      type: provider.selectedTeachingType?['text'] ?? 'recorded',
      description:
      _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
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
  }

  // ── Step 2 submit ────────────────────────────────────────────────────────────

  Future<void> _submitStep2() async {
    await context.read<TeacherProvider>().submitAddCourseStep2();
    if (!mounted) return;
    _snack('تم حفظ الدورة بنجاح 🎉', AppTheme.success);
    Navigator.of(context).pop();
  }

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

  Widget _buildStep1(TeacherProvider provider) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // FIX: pass pre-read bytes — purely synchronous, no dart:io
                  CourseImagePicker(
                    imageBytes: _logoBytes,
                    imageUrl: null,
                    onTap: _pickImage,
                  ),
                  const SizedBox(height: 20),
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
                  onAdd: () => addItemDialog(
                      'أضف أداة', provider.addFormTool, context),
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
// CourseImagePicker — shared between add & update screens
//
// FIX: accepts pre-read [imageBytes] (Uint8List) instead of XFile.
// Image.memory() is fully synchronous — no FutureBuilder, no dart:io,
// works identically on Web and Mobile.
// ─────────────────────────────────────────────────────────────────────────────

class CourseImagePicker extends StatelessWidget {
  /// Bytes from XFile.readAsBytes() — set by the parent after picking.
  final Uint8List? imageBytes;

  /// Existing network URL shown when [imageBytes] is null (update screen).
  final String? imageUrl;

  final VoidCallback onTap;

  const CourseImagePicker({
    super.key,
    required this.imageBytes,
    required this.imageUrl,
    required this.onTap,
  });

  bool get _hasImage =>
      imageBytes != null || (imageUrl?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                  color: _hasImage
                      ? AppTheme.primary
                      : AppTheme.primary.withValues(alpha: 0.3),
                  width: _hasImage ? 3 : 1.5,
                ),
                boxShadow: _hasImage
                    ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
                    : null,
              ),
              child: ClipOval(child: _imageContent()),
            ),
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageContent() {
    // Priority 1: newly picked bytes — synchronous, Web + Mobile ✅
    if (imageBytes != null) {
      return Image.memory(imageBytes!, fit: BoxFit.cover);
    }
    // Priority 2: existing network image (update screen)
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 2));
        },
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_rounded,
          size: 36, color: AppTheme.primary.withValues(alpha: 0.55)),
      const SizedBox(height: 4),
      Text(
        'صورة الدورة',
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'Cairo',
          color: AppTheme.primary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageSourceSheet
// ─────────────────────────────────────────────────────────────────────────────

class ImageSourceSheet extends StatelessWidget {
  const ImageSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('اختر مصدر الصورة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_rounded,
                  color: AppTheme.primary),
            ),
            title: const Text('من المعرض',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_rounded,
                  color: AppTheme.primary),
            ),
            title: const Text('من الكاميرا',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local helpers
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
              color: currentStep > 1
                  ? AppTheme.primary
                  : AppTheme.divider),
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
  const _Dot(
      {required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppTheme.primary : AppTheme.divider),
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
                fontFamily: 'Cairo')),
      ),
    ),
  );
}

class _BottomButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onDraft;
  final VoidCallback onPublish;
  const _BottomButtons(
      {required this.isLoading,
        required this.onDraft,
        required this.onPublish});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    decoration: BoxDecoration(
        color: AppTheme.cardBg, boxShadow: AppTheme.bottomNavShadow),
    child: Row(children: [
      Expanded(
          child: _OutlineButton(
              label: 'حفظ كمسودة',
              onTap: isLoading ? null : onDraft)),
      const SizedBox(width: 12),
      Expanded(
          child: GradientButton(
              label: 'نشر الدورة',
              isLoading: isLoading,
              onTap: onPublish)),
    ]),
  );
}