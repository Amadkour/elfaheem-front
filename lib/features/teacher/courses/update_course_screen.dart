// ─────────────────────────────────────────────────────────────────────────────
// Update Course Screen
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseModel;
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/primary_menue.dart';
import '../../../utils/widget/text_field.dart';
import '../home/teacher_models.dart';
import '../home/teacher_provider.dart';
import 'component/gradient_button.dart';

class UpdateCourseScreen extends StatefulWidget {
  final TeacherCourse course;

  const UpdateCourseScreen({
    super.key,
    required this.course,
  });

  @override
  State<UpdateCourseScreen> createState() => _UpdateCourseScreenState();
}

class _UpdateCourseScreenState extends State<UpdateCourseScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _maxCtrl;

  final ExpansibleController categoryController = ExpansibleController();

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();

    final course = widget.course;

    _titleCtrl = TextEditingController(text: course.title ?? '');
    _descCtrl = TextEditingController(text: course.description ?? '');
    _priceCtrl = TextEditingController(
      text: course.price.toString() ?? '',
    );
    _maxCtrl = TextEditingController(
      text: course.studentsCount.toString() ?? '',
    );


    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<TeacherProvider>();
      await provider.initAddCourse(context);

      if (course.categoryName != null) {
        final category = provider.specializations.firstWhere(
              (e) => e['title'] == course.categoryName,
          orElse: () => {},
        );

        if (category.isNotEmpty) {
          provider.selectedSpecialization = category;
        }
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateCourse() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<TeacherProvider>();

    final TeacherCourse? success = await provider.updateCourse(
      widget.course.id,
      name: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim(),
      fees: double.tryParse(_priceCtrl.text),
      categoryId: provider.selectedSpecialization?['id'],
      maxStudents: int.tryParse(_maxCtrl.text),
    );

    if (!mounted) return;

    if (success!=null) {
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
          content: Text(
            provider.errorMessage ?? 'حدث خطأ أثناء التحديث',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              const ScreenAppBar(title: 'تعديل الدورة'),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        MyTextField(
                          controller: _titleCtrl,
                          label: 'عنوان الدورة',
                          validator: (v) =>
                          (v?.trim().isEmpty ?? true)
                              ? 'يرجى إدخال عنوان الدورة'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        MyTextField(
                          controller: _descCtrl,
                          label: 'وصف الدورة',
                          maxLine: 4,
                        ),
                        const SizedBox(height: 16),

                        MyTextField(
                          controller: _priceCtrl,
                          label: 'رسوم الدورة',
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 16),

                        MyPrimaryMenu(
                          controller: categoryController,
                          initValue: provider.selectedSpecialization,
                          options: provider.specializations,
                          haveLogo: false,
                          onChange: (value) =>
                              provider.onChangeSpecialization(
                                value,
                                categoryController,
                              ),
                          label: 'التصنيف',
                        ),
                        const SizedBox(height: 16),

                        MyTextField(
                          controller: _maxCtrl,
                          label: 'الحد الأقصى للطلاب',
                          keyboard: TextInputType.number,
                        ),


                      ],
                    ),
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  boxShadow: AppTheme.bottomNavShadow,
                ),
                child: GradientButton(
                  label: 'حفظ التعديلات',
                  isLoading: provider.isLoading,
                  onTap: _updateCourse,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}