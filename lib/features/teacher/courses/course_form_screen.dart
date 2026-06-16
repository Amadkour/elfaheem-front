import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/primary_menue.dart';
import '../../../utils/widget/text_field.dart';
import '../home/teacher_models.dart';
import '../home/teacher_provider.dart';
import '../schedules/schedules_screen.dart';
import 'component/add_item_dialog.dart';
import 'component/section_card.dart';
import 'course_form_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point  — wraps the inner screen in a scoped provider
// ─────────────────────────────────────────────────────────────────────────────

class CourseFormScreen extends StatelessWidget {
  /// null → CREATE mode,  non-null → EDIT mode
  final TeacherCourse? course;

  const CourseFormScreen({super.key, this.course});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CourseFormProvider(api: ApiClient()),
    child: _CourseFormInner(course: course),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner stateful widget  (has access to the scoped provider)
// ─────────────────────────────────────────────────────────────────────────────

class _CourseFormInner extends StatefulWidget {
  final TeacherCourse? course;

  const _CourseFormInner({required this.course});

  @override
  State<_CourseFormInner> createState() => _CourseFormInnerState();
}

class _CourseFormInnerState extends State<_CourseFormInner>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _hoursCtrl;
  final ExpansibleController _categoryCtrl = ExpansibleController();
  final ExpansibleController _typeCtrl = ExpansibleController();

  XFile? _logoFile;
  Uint8List? _logoBytes;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool get _isEdit => widget.course != null;

  @override
  void initState() {
    super.initState();

    final c = widget.course;
    _titleCtrl = TextEditingController(text: c?.title ?? '');
    _descCtrl = TextEditingController(text: c?.description ?? '');
    _priceCtrl =
        TextEditingController(text: c != null ? c.price.toString() : '');
    _hoursCtrl =
        TextEditingController(text: c != null ? c.totalHours.toString() : '');

    for (final ctrl in [_titleCtrl, _descCtrl, _priceCtrl, _hoursCtrl]) {
      ctrl.addListener(_rebuild);
    }

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<CourseFormProvider>();
      if (_isEdit) {
        await p.initUpdate(context, widget.course!);
      } else {
        await p.initCreate(context);
      }
      _fadeCtrl.forward();
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    for (final ctrl in [_titleCtrl, _descCtrl, _priceCtrl, _hoursCtrl]) {
      ctrl.removeListener(_rebuild);
      ctrl.dispose();
    }
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Dirty check — enable Save button ─────────────────────────────────────

  bool get _hasChanges {
    if (!_isEdit) {
      return _titleCtrl.text.trim().isNotEmpty;
    }
    final c = widget.course!;
    final newPrice = double.tryParse(_priceCtrl.text) ?? c.price;
    final newHours = double.tryParse(_hoursCtrl.text) ?? c.totalHours;
    return _titleCtrl.text.trim() != c.title ||
        _descCtrl.text.trim() != (c.description ?? '') ||
        newPrice != c.price ||
        newHours != c.totalHours ||
        _logoFile != null;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final formProvider = context.read<CourseFormProvider>();
    final listProvider = context.read<TeacherProvider>();

    TeacherCourse? result;

    if (_isEdit) {
      result = await formProvider.submitUpdate(
        widget.course!,
        name: _titleCtrl.text.trim(),
        description:
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        fees: double.tryParse(_priceCtrl.text),
        totalHours: double.tryParse(_hoursCtrl.text),
        logoFile: _logoFile,
      );
    } else {
      final type =
          (formProvider.selectedTeachingType?['text'] as String?) ?? 'recorded';
      result = await formProvider.submitCreate(
        title: _titleCtrl.text.trim(),
        type: type,
        description:
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        fees: double.tryParse(_priceCtrl.text) ?? 0,
        totalHours: double.tryParse(_hoursCtrl.text),
        logoFile: _logoFile,
      );
    }

    if (!mounted) return;

    if (result != null) {
      if (_isEdit) {
        listProvider.onCourseUpdated(result);
      } else {
        listProvider.onCourseCreated(result);
      }
      _showSnack(
        _isEdit ? 'course_updated_success'.tr : 'course_created_success'.tr,
        context.themeConfig.success,
      );
      Navigator.pop(context, result);
    } else {
      _showSnack(
        formProvider.errorMessage ?? 'error_please_retry'.tr,
        context.themeConfig.danger,
      );
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    final canSave = (_hasChanges || provider.listsChanged) &&
        _titleCtrl.text.trim().isNotEmpty;

    return BasePage(
      useWebCard: true,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          // ── Gradient hero header ───────────────────────────────────────
          _HeroHeader(
            isEdit: _isEdit,
            logoBytes: _logoBytes,
            imageUrl: widget.course?.imageUrl,
            logoFile: _logoFile,
            onChange: (XFile file) async {
              _logoBytes = await file.readAsBytes();
              setState(() {
                _logoFile = file;
              });
            },
          ),
          // ── Scrollable form ────────────────────────────────────────────
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic info card
                    _FormCard(
                      icon: Icons.info_outline_rounded,
                      title: 'basic_info_card_title'.tr,
                      children: [
                        _LabeledField(
                          label: 'course_title'.tr,
                          child: MyTextField(
                            controller: _titleCtrl,
                            label: 'course_title'.tr,
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'course_title_validator'.tr
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: 'course_description'.tr,
                          child: MyTextField(
                            controller: _descCtrl,
                            label: 'course_description'.tr,
                            maxLine: 4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pricing & hours card
                    _FormCard(
                      icon: Icons.attach_money_rounded,
                      title: 'price_and_duration_title'.tr,
                      children: [
                        Row(children: [
                          Expanded(
                            child: _LabeledField(
                              label: 'price_label'.tr,
                              child: MyTextField(
                                controller: _priceCtrl,
                                label: 'price_label'.tr,
                                keyboard:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LabeledField(
                              label: 'expected_hours_label'.tr,
                              child: MyTextField(
                                controller: _hoursCtrl,
                                label: 'hours_label'.tr,
                                keyboard: TextInputType.number,
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Classification card
                    _FormCard(
                      icon: Icons.category_rounded,
                      title: 'classification_card_title'.tr,
                      children: [
                        _LabeledField(
                          label: 'Specialization'.tr,
                          child: MyPrimaryMenu(
                            controller: _categoryCtrl,
                            initValue: provider.selectedSpecialization,
                            options: provider.specializations,
                            haveLogo: false,
                            onChange: (i) => provider.onChangeSpecialization(
                                i, _categoryCtrl),
                            label: 'choose_specialization'.tr,
                          ),
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 14),
                          _LabeledField(
                            label: 'course_type_label'.tr,
                            child: MyPrimaryMenu(
                              controller: _typeCtrl,
                              initValue: provider.selectedTeachingType,
                              options: provider.teachingTypes
                                  .cast<Map<String, dynamic>>(),
                              haveLogo: false,
                              onChange: (i) =>
                                  provider.onChangeTeachingType(i, _typeCtrl),
                              label: 'course_type_hint'.tr,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Extras cards
                    SectionCard(
                      icon: Icons.workspace_premium_rounded,
                      title: 'certificates_section'.tr,
                      items: provider.form.certificates,
                      onAdd: () => addItemDialog(
                          'add_certificate'.tr, provider.addFormCertificate, context),
                      onRemove: provider.removeFormCertificate,
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      icon: Icons.build_rounded,
                      title: 'tools_section'.tr,
                      items: provider.form.tools,
                      onAdd: () => addItemDialog(
                          'add_tool'.tr, provider.addFormTool, context),
                      onRemove: provider.removeFormTool,
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      icon: Icons.checklist_rounded,
                      title: 'prerequisites_section'.tr,
                      items: provider.form.prerequisites,
                      onAdd: () => addItemDialog(
                          'add_prerequisite'.tr, provider.addFormPrerequisite, context),
                      onRemove: provider.removeFormPrerequisite,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // ── Sticky footer ──────────────────────────────────────────────
          _StickyFooter(
            isEdit: _isEdit,
            canSave: canSave,
            isLoading: provider.isLoading,
            onSave: _submit,
            course: widget.course,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero header with gradient + image picker
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final bool isEdit;
  final Uint8List? logoBytes;
  final XFile? logoFile;
  final String? imageUrl;
  final Future<void> Function(XFile file) onChange;

  const _HeroHeader({
    required this.isEdit,
    required this.logoBytes,
    required this.imageUrl,
    this.logoFile,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final unit = context.height / 12;
    return SizedBox(
      height: (3 * unit) + top,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient background
          Positioned(
            top: 0, right: 0, left: 0,
            child: Container(
              height: unit * 2,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1A3C6E),
                    Color(0xFF0D6EFD),
                    Color(0xFF4F9FFF)
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0, right: 0, left: 0,
            child: Container(height: unit, color: context.themeConfig.background),
          ),
          // Decorative circles
          Positioned(
            top: -30, left: -30,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30, right: -20,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Back button + title
          Positioned(
            top: top + 12, right: 16, left: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEdit ? 'edit_course_title'.tr : 'create_new_course_title'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'bahji',
                    ),
                  ),
                ),
                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Text(
                    isEdit ? 'edit_badge'.tr : 'new_badge'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'bahji',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentGeometry.bottomCenter,
            child: EditableImage(
              onChange: onChange,
              imageUrl: imageUrl,
              imageByte: logoBytes,
              imageFile: logoFile,
              size: context.height / 6,
            ),
          )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable form card with icon + title
// ─────────────────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _FormCard(
      {required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.themeConfig.cardBg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: context.themeConfig.linearPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'bahji',
                  color: Color(0xFF1A1A2E),
                )),
          ]),
        ),
        Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Labeled field
// ─────────────────────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'bahji',
            color: Colors.black.withValues(alpha: 0.55),
          )),
      const SizedBox(height: 6),
      child,
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky footer
// ─────────────────────────────────────────────────────────────────────────────

class _StickyFooter extends StatelessWidget {
  final bool isEdit;
  final bool canSave;
  final bool isLoading;
  final VoidCallback onSave;
  final TeacherCourse? course;

  const _StickyFooter({
    required this.isEdit,
    required this.canSave,
    required this.isLoading,
    required this.onSave,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
      decoration: BoxDecoration(
        color: context.themeConfig.cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(children: [
        // Save button
        Expanded(
          child: GestureDetector(
            onTap: (canSave && !isLoading) ? onSave : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 52,
              decoration: BoxDecoration(
                gradient: canSave
                    ? context.themeConfig.linearPrimary
                    : const LinearGradient(
                    colors: [Color(0xFFCDD5E0), Color(0xFFCDD5E0)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: canSave ? context.themeConfig.primaryShadow(isDark:context.colors.isDark) : null,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : Text(
                  canSave
                      ? (isEdit ? 'btn_save_edits'.tr : 'create_course_btn'.tr)
                      : (isEdit
                      ? 'no_changes_to_save'.tr
                      : 'enter_course_title_first'.tr),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFamily: 'bahji',
                  ),
                ),
              ),
            ),
          ),
        ),

        // Schedule button (edit mode only)
        if (isEdit && course != null) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeacherSchedulesScreen(course: course!))),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: context.themeConfig.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: context.themeConfig.primary.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.calendar_month_rounded,
                  size: 22, color: context.themeConfig.primary),
            ),
          ),
        ],
      ]),
    );
  }
}