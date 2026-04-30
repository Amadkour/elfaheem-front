import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';

import '../../../config/app_config.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../home/teacher_provider.dart';
import 'component/day_dropdown.dart';
import 'component/gradient_button.dart';

class AddCourseScreen extends StatefulWidget {
  const AddCourseScreen({super.key});

  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<TeacherProvider>().initAddCourse(context);
    });
  }

  // Step tracking
  int _step = 1; // 1 = basic info, 2 = extras
  int? _createdCourseId;

  // Step 1 controllers
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final ExpansibleController categoryController = ExpansibleController();
  final ExpansibleController teachingController = ExpansibleController();

  int? _selectedCategoryId;
  final String _courseType = 'recorded';
  File? _logoFile;

  // Step 2 state (pending extras — sent to API after course creation)
  final List<_PendingSchedule> _pendingSchedules = [];
  final List<String> _pendingCertificates = [];
  final List<String> _pendingTools = [];
  final List<String> _pendingPrerequisites = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _hoursCtrl.dispose();
    _maxCtrl.dispose();
    _disposeVideoController();
    maxWidthController.dispose();
    maxHeightController.dispose();
    qualityController.dispose();
    super.dispose();
  }

  // ── Step 1: create course ─────────────────────────────────────────────────────

  Future<void> _submitStep1({required bool publishNow}) async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<TeacherProvider>();
    final created = await context.read<TeacherProvider>().createCourse(
          title: _titleCtrl.text.trim(),
          type: _courseType,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          fees: double.tryParse(_priceCtrl.text) ?? 0,
          totalHours: double.tryParse(_hoursCtrl.text),
          categoryId: provider.selectedSpecialization?['id'] ?? '-1',
          maxStudents: int.tryParse(_maxCtrl.text),
          logoFile: _logoFile,
          publishNow: publishNow,
        );

    if (!mounted) return;

    if (created != null) {
      setState(() {
        _createdCourseId = created.id;
        _step = 2;
      });
    } else {
      log('================================================');
      log(provider.errorMessage.toString());
      log('================================================');
      _snack(
          provider.errorMessage ?? 'حدث خطأ، حاول مرة أخرى', AppTheme.danger);
    }
  }

  // ── Step 2: save extras then close ───────────────────────────────────────────

  Future<void> _submitStep2() async {
    final id = _createdCourseId!;
    final provider = context.read<TeacherProvider>();

    // Fire all API calls concurrently
    await Future.wait([
      for (final s in _pendingSchedules)
        provider.addSchedule(id,
            day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in _pendingCertificates)
        provider.addCertificate(id, title: t),
      for (final t in _pendingTools) provider.addTool(id, name: t),
      for (final p in _pendingPrerequisites)
        provider.addPrerequisite(id, title: p),
    ]);

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

  Future<void> _pickImage() async {
    // Replace with image_picker in production
    setState(() => _logoFile = File('/placeholder/course_logo.jpg'));
    await _onImageButtonPressed(ImageSource.camera,
        context: context, isMedia: false);
    _logoFile = File(_mediaFileList?.first.path ?? '');

    _snack('اختر صورة من المعرض', AppTheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final TeacherProvider provider = context.watch<TeacherProvider>();

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(
                title: _step == 1 ? 'إضافة دورة جديده' : 'تفاصيل الدورة',
              ),
              // ── Step indicator ───────────────────────────────────────────
              _StepIndicator(currentStep: _step),
              const SizedBox(height: 4),
              provider.isLoading
                  ? Center(
                      child: CircularProgressIndicator(),
                    )
                  : Expanded(
                      child: _step == 1
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
                      validator: (v) =>
                          (v?.isEmpty ?? true) ? 'أدخل عنوان الدورة' : null),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: MyTextField(
                        controller: _descCtrl,
                        label: 'course_description'.tr,
                        maxLine: 3),
                  ),
                  MyTextField(
                    controller: _priceCtrl,
                    label: 'course_fees'.tr,
                    keyboard: const TextInputType.numberWithOptions(
                        decimal: true, signed: false),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: context.read<CategoriesProvider>().isLoadingCategory
                        ? CircularProgressIndicator()
                        : MyPrimaryMenu(
                            controller: categoryController,
                            initValue: provider.selectedSpecialization,
                            options: provider.specializations,
                            haveLogo: false,
                            onChange: (i) => provider.onChangeSpecialization(
                                i, categoryController),
                            label: 'category'.tr),
                  ),
                  MyPrimaryMenu(
                      controller: teachingController,
                      initValue: provider.selectedTeachingType,
                      options: provider.teachingTypes,
                      haveLogo: false,
                      onChange: (i) =>
                          provider.onChangeTeachingType(i, teachingController),
                      label: 'teaching_type'.tr),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: MyTextField(
                      controller: _hoursCtrl,
                      label: 'course_hours'.tr,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true, signed: false),
                    ),
                  ),
                  _Label('رفع صوره الدوره'),
                  const SizedBox(height: 8),
                  _ImageUploader(
                      hasImage: _logoFile != null, onTap: _pickImage),
                  const SizedBox(height: 32),
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Schedule ────────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.calendar_month_rounded,
                  title: 'الجدول الأسبوعي',
                  items: _pendingSchedules
                      .map((s) => '${s.dayLabel}  '
                          '${s.startTime} – ${s.endTime}')
                      .toList(),
                  onAdd: () => addScheduleDialog(context, (String? selectedDay,
                      String? startTime, String? endTime) {
                    if (selectedDay != null) {
                      setState(() => _pendingSchedules.add(_PendingSchedule(
                            day: selectedDay,
                            startTime: startTime!,
                            endTime: endTime!,
                          )));
                      Navigator.pop(context);
                    }
                  }),
                  onRemove: (i) =>
                      setState(() => _pendingSchedules.removeAt(i)),
                ),
                const SizedBox(height: 16),

                // ── Certificates ─────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.workspace_premium_rounded,
                  title: 'الشهادات',
                  items: _pendingCertificates,
                  onAdd: () => _addItemDialog('أضف شهادة',
                      (v) => setState(() => _pendingCertificates.add(v))),
                  onRemove: (i) =>
                      setState(() => _pendingCertificates.removeAt(i)),
                ),
                const SizedBox(height: 16),

                // ── Tools ─────────────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.build_rounded,
                  title: 'الأدوات المطلوبة',
                  items: _pendingTools,
                  onAdd: () => _addItemDialog(
                      'أضف أداة', (v) => setState(() => _pendingTools.add(v))),
                  onRemove: (i) => setState(() => _pendingTools.removeAt(i)),
                ),
                const SizedBox(height: 16),

                // ── Prerequisites ─────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.checklist_rounded,
                  title: 'المتطلبات السابقة',
                  items: _pendingPrerequisites,
                  onAdd: () => _addItemDialog('أضف متطلب',
                      (v) => setState(() => _pendingPrerequisites.add(v))),
                  onRemove: (i) =>
                      setState(() => _pendingPrerequisites.removeAt(i)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        // Bottom: skip or save
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

  // ── Dialogs ───────────────────────────────────────────────────────────────────

  Future<void> _addItemDialog(String hint, void Function(String) onAdd) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          title: Text(hint,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontFamily: 'Cairo'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.caption,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: AppTheme.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('إضافة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) onAdd(result);
  }

  List<XFile>? _mediaFileList;

  void _setImageFileListFromFile(XFile? value) {
    _mediaFileList = value == null ? null : <XFile>[value];
  }

  dynamic _pickImageError;
  bool isVideo = false;

  VideoPlayerController? _controller;
  VideoPlayerController? _toBeDisposed;
  String? _retrieveDataError;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController maxWidthController = TextEditingController();
  final TextEditingController maxHeightController = TextEditingController();
  final TextEditingController qualityController = TextEditingController();
  final TextEditingController limitController = TextEditingController();

  Future<void> _playVideo(XFile? file) async {
    if (file != null && mounted) {
      await _disposeVideoController();
      final VideoPlayerController controller;
      if (kIsWeb) {
        controller = VideoPlayerController.networkUrl(Uri.parse(file.path));
      } else {
        controller = VideoPlayerController.file(File(file.path));
      }
      _controller = controller;
      // In web, most browsers won't honor a programmatic call to .play
      // if the video has a sound track (and is not muted).
      // Mute the video so it auto-plays in web!
      // This is not needed if the call to .play is the result of user
      // interaction (clicking on a "play" button, for example).
      const double volume = kIsWeb ? 0.0 : 1.0;
      await controller.setVolume(volume);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      setState(() {});
    }
  }

  Future<void> _onImageButtonPressed(
    ImageSource source, {
    required BuildContext context,
    bool allowMultiple = false,
    bool isMedia = false,
  }) async {
    if (_controller != null) {
      await _controller!.setVolume(0.0);
    }
    if (context.mounted) {
      if (isVideo) {
        final List<XFile> files;
        if (allowMultiple) {
          files = await _picker.pickMultiVideo();
        } else {
          final XFile? file = await _picker.pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 10),
          );
          files = <XFile>[if (file != null) file];
        }
        // Just play the first file, to keep the example simple.
        await _playVideo(files.firstOrNull);
      } else if (allowMultiple) {
        await _displayPickImageDialog(context, true, (
          double? maxWidth,
          double? maxHeight,
          int? quality,
          int? limit,
        ) async {
          try {
            final List<XFile> pickedFileList = isMedia
                ? await _picker.pickMultipleMedia(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    imageQuality: quality,
                    limit: limit,
                  )
                : await _picker.pickMultiImage(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    imageQuality: quality,
                    limit: limit,
                  );
            setState(() {
              _mediaFileList = pickedFileList;
            });
          } catch (e) {
            setState(() {
              _pickImageError = e;
            });
          }
        });
      } else if (isMedia) {
        await _displayPickImageDialog(context, false, (
          double? maxWidth,
          double? maxHeight,
          int? quality,
          int? limit,
        ) async {
          try {
            final List<XFile> pickedFileList = <XFile>[];
            final XFile? media = await _picker.pickMedia(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
              imageQuality: quality,
            );
            if (media != null) {
              pickedFileList.add(media);
              setState(() {
                _mediaFileList = pickedFileList;
              });
            }
          } catch (e) {
            setState(() {
              _pickImageError = e;
            });
          }
        });
      } else {
        try {
          final XFile? pickedFile = await _picker.pickImage(
            source: source,
            maxWidth: 300,
            maxHeight: 500,
            imageQuality: 70,
          );
          setState(() {
            _setImageFileListFromFile(pickedFile);
          });
        } catch (e) {
          setState(() {
            _pickImageError = e;
          });
        }
      }
    }
  }

  Future<void> _displayPickImageDialog(
    BuildContext context,
    bool isMulti,
    OnPickImageCallback onPick,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add optional parameters'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: maxWidthController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter maxWidth if desired',
                ),
              ),
              TextField(
                controller: maxHeightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter maxHeight if desired',
                ),
              ),
              TextField(
                controller: qualityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter quality if desired',
                ),
              ),
              if (isMulti)
                TextField(
                  controller: limitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Enter limit if desired',
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('CANCEL'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('PICK'),
              onPressed: () {
                final double? width = maxWidthController.text.isNotEmpty
                    ? double.parse(maxWidthController.text)
                    : null;
                final double? height = maxHeightController.text.isNotEmpty
                    ? double.parse(maxHeightController.text)
                    : null;
                final int? quality = qualityController.text.isNotEmpty
                    ? int.parse(qualityController.text)
                    : null;
                final int? limit = limitController.text.isNotEmpty
                    ? int.parse(limitController.text)
                    : null;
                onPick(width, height, quality, limit);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void deactivate() {
    if (_controller != null) {
      _controller!.setVolume(0.0);
      _controller!.pause();
    }
    super.deactivate();
  }

  Future<void> _disposeVideoController() async {
    if (_toBeDisposed != null) {
      await _toBeDisposed!.dispose();
    }
    _toBeDisposed = _controller;
    _controller = null;
  }

  Text? _getRetrieveErrorWidget() {
    if (_retrieveDataError != null) {
      final Text result = Text(_retrieveDataError!);
      _retrieveDataError = null;
      return result;
    }
    return null;
  }

  Widget _previewVideo() {
    final Text? retrieveError = _getRetrieveErrorWidget();
    if (retrieveError != null) {
      return retrieveError;
    }
    if (_controller == null) {
      return const Text(
        'You have not yet picked a video',
        textAlign: TextAlign.center,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: AspectRatioVideo(_controller),
    );
  }

  Widget _previewImages() {
    final Text? retrieveError = _getRetrieveErrorWidget();
    if (retrieveError != null) {
      return retrieveError;
    }
    if (_mediaFileList != null) {
      return Semantics(
        label: 'image_picker_example_picked_images',
        child: ListView.builder(
          key: UniqueKey(),
          itemBuilder: (BuildContext context, int index) {
            final String? mime = lookupMimeType(_mediaFileList![index].path);

            // Why network for web?
            // See https://pub.dev/packages/image_picker_for_web#limitations-on-the-web-platform
            return Semantics(
              label: 'image_picker_example_picked_image',
              child: kIsWeb
                  ? Image.network(_mediaFileList![index].path)
                  : (mime == null || mime.startsWith('image/')
                      ? Image.file(
                          File(_mediaFileList![index].path),
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return const Center(
                              child: Text('This image type is not supported'),
                            );
                          },
                        )
                      : _buildInlineVideoPlayer(index)),
            );
          },
          itemCount: _mediaFileList!.length,
        ),
      );
    } else if (_pickImageError != null) {
      return Text(
        'Pick image error: $_pickImageError',
        textAlign: TextAlign.center,
      );
    } else {
      return const Text(
        'You have not yet picked an image.',
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _buildInlineVideoPlayer(int index) {
    final VideoPlayerController controller = VideoPlayerController.file(
      File(_mediaFileList![index].path),
    );
    const double volume = kIsWeb ? 0.0 : 1.0;
    controller.setVolume(volume);
    controller.initialize();
    controller.setLooping(true);
    controller.play();
    return Center(child: AspectRatioVideo(controller));
  }

  Widget _handlePreview() {
    if (isVideo) {
      return _previewVideo();
    } else {
      return _previewImages();
    }
  }

  Future<void> retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return;
    }
    if (response.file != null) {
      if (response.type == RetrieveType.video) {
        isVideo = true;
        await _playVideo(response.file);
      } else {
        isVideo = false;
        setState(() {
          if (response.files == null) {
            _setImageFileListFromFile(response.file);
          } else {
            _mediaFileList = response.files;
          }
        });
      }
    } else {
      _retrieveDataError = response.exception!.code;
    }
  }
}
// ── Pending schedule (local only, before API call) ────────────────────────────

class _PendingSchedule {
  final String day;
  final String startTime;
  final String endTime;

  /// Arabic name for this day.
  String get dayLabel {
    const map = {
      'monday': 'الاثنين',
      'tuesday': 'الثلاثاء',
      'wednesday': 'الأربعاء',
      'thursday': 'الخميس',
      'friday': 'الجمعة',
      'saturday': 'السبت',
      'sunday': 'الأحد',
    };
    return map[day.toLowerCase()] ?? day;
  }

  /// "الاثنين  10:00 — 12:00"
  String get displayLabel => '$dayLabel   $startTime — $endTime';

  const _PendingSchedule(
      {required this.day, required this.startTime, required this.endTime});
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppTheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: AppTheme.h3.copyWith(fontSize: 15)),
                ),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text('إضافة',
                            style: AppTheme.caption.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isNotEmpty) const Divider(height: 1),
          // Items
          ...items.asMap().entries.map((e) => _ItemRow(
                label: e.value,
                onRemove: () => onRemove(e.key),
              )),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text('لم يتم الإضافة بعد',
                  style: AppTheme.caption.copyWith(color: AppTheme.textLight)),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ItemRow({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(label,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        trailing: GestureDetector(
          onTap: onRemove,
          child:
              const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
        ),
      );
}

// ── Step Indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;

  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _Dot(label: '١', active: currentStep >= 1, done: currentStep > 1),
          Expanded(
              child: Container(
                  height: 2,
                  color:
                      currentStep > 1 ? AppTheme.primary : AppTheme.divider)),
          _Dot(label: '٢', active: currentStep >= 2, done: false),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _Dot({required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

// ── Time Field ────────────────────────────────────────────────────────────────

// ── Outline / Gradient Buttons ────────────────────────────────────────────────

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

// ── Shared small widgets (kept identical to original) ─────────────────────────

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTheme.h3.copyWith(fontSize: 15));
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
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 48, color: AppTheme.success),
                  const SizedBox(height: 8),
                  Text('تم اختيار الصورة',
                      style: AppTheme.label.copyWith(color: AppTheme.success)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_rounded,
                      size: 48, color: AppTheme.primary.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Text('تحميل الصوره',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
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
                  label: 'حفظ كمسوده', onTap: isLoading ? null : onDraft)),
          const SizedBox(width: 12),
          Expanded(
              child: GradientButton(
                  label: 'نشر الدوره', isLoading: isLoading, onTap: onPublish)),
        ]),
      );
}

typedef OnPickImageCallback = void Function(
  double? maxWidth,
  double? maxHeight,
  int? quality,
  int? limit,
);

class AspectRatioVideo extends StatefulWidget {
  const AspectRatioVideo(this.controller, {super.key});

  final VideoPlayerController? controller;

  @override
  AspectRatioVideoState createState() => AspectRatioVideoState();
}

class AspectRatioVideoState extends State<AspectRatioVideo> {
  VideoPlayerController? get controller => widget.controller;
  bool initialized = false;

  void _onVideoControllerUpdate() {
    if (!mounted) {
      return;
    }
    if (initialized != controller!.value.isInitialized) {
      initialized = controller!.value.isInitialized;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    controller!.addListener(_onVideoControllerUpdate);
  }

  @override
  void dispose() {
    controller!.removeListener(_onVideoControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller!.value.aspectRatio,
          child: VideoPlayer(controller!),
        ),
      );
    } else {
      return Container();
    }
  }
}
