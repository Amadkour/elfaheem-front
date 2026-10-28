// shared/session/components/add_material_sheet.dart
//
// Bottom sheet (mobile) / centered dialog (wide screens & web) for adding a
// new material (file upload or external link).
// Scoped to TeacherCourseScreenProvider via context.read — no extra provider
// wrapper needed since it's always opened from within the provider scope.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../utils/helpers.dart';
import '../../../../teacher/sessions/sessions_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

// Screens at/above this width get the centered "card" treatment instead of a
// full-width bottom sheet — covers desktop web and tablets in landscape.
const double _kWideBreakpoint = 720;

// ─────────────────────────────────────────────────────────────────────────────
// Public entry — small button that opens the sheet/dialog
// ─────────────────────────────────────────────────────────────────────────────

class AddMaterialButton extends StatelessWidget {
  final int sessionId;

  const AddMaterialButton({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showAddMaterialSheet(context, sessionId: sessionId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: context.colors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: context.colors.primaryShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 15, color: context.colors.onHero),
            const SizedBox(width: 5),
            Text(
              'add_material'.tr,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                color: context.colors.onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the Add Material UI, picking the right chrome for the current
/// screen size: a bottom sheet on phones, a centered card on wide screens.
Future<void> showAddMaterialSheet(
    BuildContext context, {
      required int sessionId,
    }) async {
  final provider = context.read<TeacherCourseScreenProvider>();
  final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  if (isWide) {
    await showDialog(
      context: context,
      barrierColor: context.colors.heroShade.withValues(alpha: 0.45),
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AddMaterialSheet(sessionId: sessionId, isWide: true),
            ),
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: AddMaterialSheet(sessionId: sessionId, isWide: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sheet / dialog content
// ─────────────────────────────────────────────────────────────────────────────

class AddMaterialSheet extends StatefulWidget {
  final int sessionId;
  final bool isWide;

  const AddMaterialSheet({
    super.key,
    required this.sessionId,
    this.isWide = false,
  });

  @override
  State<AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<AddMaterialSheet> {
  int _mode = 0; // 0 = file, 1 = link
  int _fileTypeIdx = 0;
  PlatformFile? _pickedFile;
  int _pickedSize = 0; // PlatformFile.size was removed in file_picker v12
  bool _saving = false;

  String? _nameError;
  String? _fileError;
  String? _urlError;
  String? _submitError;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  // The colours follow the live theme, so the list is built on read (it is tiny).
  List<_FileTypeOption> get _fileTypeOptions {
    final c = context.colors;
    return [
    _FileTypeOption(
      labelKey: 'material_type_image',
      icon: Icons.image_rounded,
      fileType: FileType.image,
      color: c.success,
    ),
    _FileTypeOption(
      labelKey: 'material_type_video',
      icon: Icons.play_circle_rounded,
      fileType: FileType.video,
      color: c.primary,
    ),
    _FileTypeOption(
      labelKey: 'pdf_document',
      icon: Icons.description_rounded,
      fileType: FileType.custom,
      color: c.danger,
    ),
    // ANY other file: .py .java .txt .zip .csv ... (no extension filter).
    // Add the translation key 'other_file' (e.g. "ملف آخر" / "Other file").
    _FileTypeOption(
      labelKey: 'other_file',
      icon: Icons.insert_drive_file_rounded,
      fileType: FileType.any,
      color: c.textMedium,
    ),
  ];
  }

  static const _documentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'csv',
    'py',
    'txt',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ── File picker ────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final opt = _fileTypeOptions[_fileTypeIdx];
    // file_picker v12+: pickFile() returns PlatformFile? (null if cancelled).
    // Nothing is buffered here — mobile streams from disk via the background
    // upload queue (see _submit); on web the bytes are read in _submit.
    final f = await FilePicker.pickFile(
      type: opt.fileType,
      allowedExtensions: opt.fileType == FileType.custom
          ? _documentExtensions
          : null,
    );
    if (f == null) return;
    final size = f.lengthSync() ?? await f.length() ?? 0;

    if (mounted) {
      setState(() {
        _pickedFile = f;
        _pickedSize = size;
        final title = _prettifyFileName(f.name);
        _nameCtrl.text=title;
        _descCtrl.text = '${opt.fileType.name} about $title';
        _fileError = null;
      });
      HapticFeedback.selectionClick();
    }
  }
  /// Turns a raw file name into a clean, human-friendly title.
  /// "lecture_03-intro_to_AI.final.pdf" -> "Lecture 03 Intro To AI Final"
  String _prettifyFileName(String fileName) {
    // 1. Remove the extension
    final dot = fileName.lastIndexOf('.');
    var name = dot > 0 ? fileName.substring(0, dot) : fileName;

    // 2. Replace separators with spaces
    name = name.replaceAll(RegExp(r'[_\-.]+'), ' ');

    // 3. Split camelCase: "introToAI" -> "intro To AI"
    name = name.replaceAllMapped(
      RegExp(r'(?<=[a-z])(?=[A-Z])'),
          (_) => ' ',
    );

    // 4. Collapse extra whitespace
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 5. Capitalize each word (no effect on Arabic, which has no casing)
    return name
        .split(' ')
        .map((w) => w.isEmpty
        ? w
        : w == w.toUpperCase() && w.length <= 4
        ? w // keep acronyms like AI, PDF, ML
        : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
  /// Video length in whole seconds (mobile/desktop only; null on web / on error).
  Future<int?> _probeDuration(PlatformFile f) async {
    if (kIsWeb || f.path == null) return null;
    final c = VideoPlayerController.file(File(f.path!));
    try {
      await c.initialize();
      final s = c.value.duration.inSeconds;
      return s > 0 ? s : null;
    } catch (_) {
      return null;
    } finally {
      await c.dispose();
    }
  }

  void _clearFile() {
    setState(() => _pickedFile = null);
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) {
      setState(() {
        _urlCtrl.text = text;
        _urlError = null;
      });
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() {
      _submitError = null;
      _nameError = _nameCtrl.text.trim().isEmpty
          ? 'please_enter_name'.tr
          : null;
      _fileError = _mode == 0 && _pickedFile == null
          ? 'please_pick_file'.tr
          : null;
      _urlError = _mode == 1 && _urlCtrl.text.trim().isEmpty
          ? 'please_enter_url'.tr
          : null;
    });

    if (_nameError != null || _fileError != null || _urlError != null) {
      HapticFeedback.selectionClick();
      return;
    }

    final name = _nameCtrl.text.trim();
    final prov = context.read<TeacherCourseScreenProvider>();

    if (_mode == 0) {
      final isVideo = _fileTypeOptions[_fileTypeIdx].fileType == FileType.video;
      // `path` is only valid on mobile / desktop; on web read the bytes.
      final path = kIsWeb ? null : _pickedFile!.path;
      Uint8List? bytes;
      if (kIsWeb) {
        try {
          bytes = await _pickedFile!.readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }

      // `kIsWeb` is the reliable platform check — file_picker can hand back
      // a non-null `.path` on web too (a blob reference, not a filesystem
      // path), and dart:io.File(path) throws on web the instant it's built.
      //   • mobile/desktop -> stream from `path`
      //   • web            -> upload the picked `bytes`
      final bool canUpload = kIsWeb ? bytes != null : path != null;
      if (!canUpload) {
        setState(() => _fileError = 'file_load_failed'.tr);
        return;
      }

      final int? durationSeconds =
      isVideo ? await _probeDuration(_pickedFile!) : null;

      // Every file type now goes through the app-wide background upload
      // queue: the sheet closes immediately and progress / failures show in
      // UploadProgressFooter on any screen (presign -> PUT -> confirm).
      prov.uploadFileMaterialInBackground(
        sessionId: widget.sessionId,
        filePath: path ?? '',
        bytes: kIsWeb ? bytes : null,
        durationSeconds: durationSeconds,
        fileName: _pickedFile!.name,
        name: name,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
      return;
    } else {
      setState(() => _saving = true);
      try {
        await prov.addLinkMaterial(
          sessionId: widget.sessionId,
          name: name,
          url: _urlCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
        );
        if (mounted) Navigator.pop(context);
      } catch (_) {
        if (mounted) setState(() => _submitError = 'generic_error'.tr);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  bool get _isValid {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_mode == 0) return _pickedFile != null;
    return _urlCtrl.text.trim().isNotEmpty;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final radius = widget.isWide
        ? context.colors.radiusXL
        : context.colors.radiusXL;

    return PopScope(
      canPop: !_saving,
      child: Container(
        margin: widget.isWide
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: widget.isWide
            ? const BoxConstraints(maxHeight: 640)
            : null,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: widget.isWide
              ? BorderRadius.circular(radius)
              : BorderRadius.circular(radius),
          boxShadow: widget.isWide
              ? [
            BoxShadow(
              color: context.colors.heroShade.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ]
              : null,
        ),
        child: Directionality(
          textDirection: Helpers.pageDirection,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.isWide ? 20 : 12,
              20,
              20 + (widget.isWide ? 0 : bottomInset),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.isWide) _DragHandle(),
                  _Header(isWide: widget.isWide, saving: _saving),
                  const SizedBox(height: 18),

                  // Mode toggle (file / link)
                  _ModeToggle(
                    selected: _mode,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _mode = v;
                        _fileError = null;
                        _urlError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 18),

                  if (_mode == 0) ...[
                    _FileTypeSelector(
                      options: _fileTypeOptions,
                      selectedIndex: _fileTypeIdx,
                      onChanged: (i) => setState(() {
                        _fileTypeIdx = i;
                        _pickedFile = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _FilePickerZone(
                      pickedFile: _pickedFile,
                      pickedSize: _pickedSize,
                      color: _fileTypeOptions[_fileTypeIdx].color,
                      icon: _fileTypeOptions[_fileTypeIdx].icon,
                      errorText: _fileError,
                      onTap: _pickFile,
                      onClear: _clearFile,
                    ),
                  ] else
                    _PremiumField(
                      controller: _urlCtrl,
                      label: 'url_label'.tr,
                      hint: 'link_url_hint'.tr,
                      icon: Icons.link_rounded,
                      errorText: _urlError,
                      keyboardType: TextInputType.url,
                      onChanged: (_) {
                        if (_urlError != null) setState(() => _urlError = null);
                      },
                      trailing: TextButton(
                        onPressed: _pasteUrl,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'paste_url'.tr,
                          style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                  _PremiumField(
                    controller: _nameCtrl,
                    label: 'name_label'.tr,
                    hint: 'material_name_hint'.tr,
                    icon: Icons.badge_outlined,
                    errorText: _nameError,
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                  ),
                  const SizedBox(height: 10),
                  _PremiumField(
                    controller: _descCtrl,
                    label: 'description_optional'.tr,
                    hint: 'material_description_hint'.tr,
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                  ),

                  if (_submitError != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBanner(message: _submitError!),
                  ],

                  const SizedBox(height: 20),

                  _SubmitButton(
                    saving: _saving,
                    enabled: _isValid,
                    onPressed: _submit,
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
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.colors.textLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — icon avatar, title, subtitle, close button
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isWide;
  final bool saving;

  const _Header({required this.isWide, required this.saving});

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
            borderRadius: BorderRadius.circular(14),
            boxShadow: context.colors.primaryShadow,
          ),
          child: Icon(
            Icons.upload_file_rounded,
            color: context.colors.onHero,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('add_material_title'.tr, style: context.colors.h3),
              const SizedBox(height: 2),
              Text(
                'add_material_subtitle'.tr,
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
          onPressed: saving ? null : () => Navigator.pop(context),
          icon: Icon(
            Icons.close_rounded,
            size: 20,
            color: saving
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
// File / Link mode toggle — animated sliding pill
// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.colors.textLight.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          _segment('file_mode'.tr, 0, Icons.upload_file_rounded, context),
          _segment('link_mode'.tr, 1, Icons.link_rounded, context),
        ],
      ),
    );
  }

  Widget _segment(
      String label,
      int index,
      IconData icon,
      BuildContext context,
      ) {
    final sel = selected == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(index),
        child: Container(
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: sel ? context.colors.primaryGradient : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            textAlign: TextAlign.center,

            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: sel ? context.colors.onHero : context.colors.secondText,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: sel ? context.colors.onHero : context.colors.secondText,
                ),
                const SizedBox(width: 5),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File type selector chips (image / video / document)
// ─────────────────────────────────────────────────────────────────────────────

class _FileTypeSelector extends StatelessWidget {
  final List<_FileTypeOption> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FileTypeSelector({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(options.length, (i) {
        final opt = options[i];
        final selected = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              margin: EdgeInsetsDirectional.only(end: i < options.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? opt.color.withValues(alpha: 0.22)
                    : context.colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? opt.color
                      : context.colors.textLight.withValues(alpha: 0.18),
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    opt.icon,
                    color: selected ? opt.color : context.colors.textLight,
                    size: 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    opt.labelKey.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? opt.color : context.colors.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop-zone / picked-file card
// ─────────────────────────────────────────────────────────────────────────────

class _FilePickerZone extends StatelessWidget {
  final PlatformFile? pickedFile;
  final int pickedSize;
  final Color color;
  final IconData icon;
  final String? errorText;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _FilePickerZone({
    required this.pickedFile,
    required this.pickedSize,
    required this.color,
    required this.icon,
    required this.onTap,
    required this.onClear,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final picked = pickedFile != null;
    final borderColor = errorText != null
        ? context.colors.danger
        : (picked ? color : context.colors.textLight.withValues(alpha: 0.35));

    Widget content;
    if (picked) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickedFile!.name,
                    style: context.colors.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _humanFileSize(pickedSize),
                    style: context.colors.body.copyWith(
                      fontSize: 11,
                      color: context.colors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.autorenew_rounded,
                  size: 18,
                  color: context.colors.primary,
                ),
              ),
            ),
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.colors.danger,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 22,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'tap_to_pick_file'.tr,
              style: context.colors.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: picked ? null : onTap,
          child: CustomPaint(
            painter: picked
                ? null
                : _DashedRRectPainter(
              color: borderColor,
              radius: context.colors.radiusMedium,
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: picked
                    ? color.withValues(alpha: 0.06)
                    : context.colors.background,
                borderRadius: BorderRadius.circular(
                  context.colors.radiusMedium,
                ),
                border: picked
                    ? Border.all(color: borderColor, width: 1.4)
                    : null,
              ),
              child: content,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
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

/// Lightweight dashed rounded-rect border, drawn without any extra package.
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth = 1.4;
  final double dashLength = 6;
  final double gapLength = 5;

  _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final basePath = Path()..addRRect(rrect);
    final dashedPath = Path();

    for (final metric in basePath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        dashedPath.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

String _humanFileSize(int bytes) {
  if (bytes <= 0) return '0 KB';
  const units = ['B', 'KB', 'MB', 'GB'];
  var i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  final decimals = (i == 0 || size >= 10) ? 0 : 1;
  return '${size.toStringAsFixed(decimals)} ${units[i]}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium text field
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final String? errorText;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  const _PremiumField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.errorText,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.trailing,
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
            color: context.colors.background,
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
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                color: context.colors.textLight.withValues(alpha: 0.7),
              ),
              prefixIcon: Icon(icon, size: 18, color: context.colors.textLight),
              suffixIcon: trailing,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 13,
                horizontal: 4,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
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
// Submit button
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool saving;
  final bool enabled;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.saving,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: GestureDetector(
        onTap: saving ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            gradient: enabled ? context.colors.primaryGradient : null,
            color: enabled
                ? null
                : context.colors.textLight.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            boxShadow: enabled ? context.colors.primaryShadow : null,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: saving
                  ? AppLoadingIndicator(showLogo: false,)
                  : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: context.colors.onHero,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'add_material_btn'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 14,
                      color: context.colors.onHero,
                      fontWeight: FontWeight.w700,
                    ),
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
// Inline error banner (submit failures)
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: context.colors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                color: context.colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────

class _FileTypeOption {
  final String labelKey;
  final IconData icon;
  final FileType fileType;
  final Color color;

  const _FileTypeOption({
    required this.labelKey,
    required this.icon,
    required this.fileType,
    required this.color,
  });
}