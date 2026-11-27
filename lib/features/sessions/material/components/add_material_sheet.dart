// shared/session/components/add_material_sheet.dart
//
// Bottom sheet (mobile) / centered dialog (wide screens & web) for adding a
// new material (file upload or external link).
// Scoped to TeacherCourseScreenProvider via context.read — no extra provider
// wrapper needed since it's always opened from within the provider scope.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle, AppFieldLabel;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/design/app_tabs.dart' show AppTabs, AppTabItem;
import 'package:flutter_education_app/design/app_tokens.dart';

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
    // a tonal action in the panel header: the emerald tint with emerald ink (the gradient pill is gone, D-622)
    return AppButton.tonal(
      label: 'add_material'.tr,
      icon: Icons.add_rounded,
      size: AppButtonSize.sm,
      onPressed: () => showAddMaterialSheet(context, sessionId: sessionId),
    );
  }
}

/// Opens the Add Material UI, picking the right chrome for the current
/// screen size: a bottom sheet on phones, a centered card on wide screens.
Future<void> showAddMaterialSheet(
    BuildContext context, {
      required int sessionId,
      int initialMode = 0,
      int initialFileType = 0,
    }) async {
  final provider = context.read<TeacherCourseScreenProvider>();
  final isWide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;

  if (isWide) {
    await showDialog(
      context: context,
      barrierColor: appScrimColor(context),
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(AppSpace.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AddMaterialSheet(sessionId: sessionId, isWide: true, initialMode: initialMode, initialFileType: initialFileType),
            ),
          ),
        ),
      ),
    );
  } else {
    await showAppModalSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: AddMaterialSheet(sessionId: sessionId, isWide: false, initialMode: initialMode, initialFileType: initialFileType),
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

  /// 0 = file, 1 = link; [initialFileType] indexes image · video · pdf · other (the Add materials page opens a
  /// recording as video, a link on the link tab).
  final int initialMode, initialFileType;

  const AddMaterialSheet({
    super.key,
    required this.sessionId,
    this.isWide = false,
    this.initialMode = 0,
    this.initialFileType = 0,
  });

  @override
  State<AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<AddMaterialSheet> {
  late int _mode = widget.initialMode; // 0 = file, 1 = link
  late int _fileTypeIdx = widget.initialFileType;
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

    return PopScope(
      canPop: !_saving,
      child: Container(
        constraints: widget.isWide
            ? const BoxConstraints(maxHeight: 640)
            : null,
        decoration: widget.isWide
            ? BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                boxShadow: AppElevation.of(context, 4),
              )
            : BoxDecoration(color: context.colors.cardBg, borderRadius: AppRadius.sheetTop),
        child: Directionality(
          textDirection: Helpers.pageDirection,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.lg,
              widget.isWide ? AppSpace.lg : AppSpace.md,
              AppSpace.lg,
              AppSpace.lg + (widget.isWide ? 0 : bottomInset),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(isWide: widget.isWide, saving: _saving),
                  const SizedBox(height: AppSpace.lg),

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
                  const SizedBox(height: AppSpace.md),

                  if (_mode == 0) ...[
                    _FileTypeSelector(
                      options: _fileTypeOptions,
                      selectedIndex: _fileTypeIdx,
                      onChanged: (i) => setState(() {
                        _fileTypeIdx = i;
                        _pickedFile = null;
                      }),
                    ),
                    const SizedBox(height: AppSpace.sm),
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
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                          minimumSize: const Size(AppTouch.min, AppTouch.min),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                        ),
                        child: Text(
                          'paste_url'.tr,
                          style: AppType.label(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.colors.blockAccentInk(context.colors.primary, context.colors.inputBg),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: AppSpace.md),
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
                  const SizedBox(height: AppSpace.sm),
                  _PremiumField(
                    controller: _descCtrl,
                    label: 'description_optional'.tr,
                    hint: 'material_description_hint'.tr,
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                  ),

                  if (_submitError != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    _ErrorBanner(message: _submitError!),
                  ],

                  const SizedBox(height: AppSpace.sm),
                  Row(children: [
                    Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: context.colors.textMedium),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text('t1_cp_mat_bg'.tr, style: AppType.meta(context))),
                  ]),
                  const SizedBox(height: AppSpace.lg),

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
// Header — title in the editorial face, subtitle, close button
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isWide;
  final bool saving;

  const _Header({required this.isWide, required this.saving});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('t1_cp_mat_title'.tr, style: AppType.pageTitle(context))),
              const SizedBox(height: 2),
              Text(
                't1_cp_mat_sub'.tr,
                style: AppType.meta(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          style: IconButton.styleFrom(backgroundColor: c.inputBg),
          icon: Icon(
            Icons.close_rounded,
            size: AppIconSize.md,
            color: saving ? c.textLight.withValues(alpha: 0.4) : c.textMedium,
          ),
          tooltip: 'close'.tr,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File / Link mode toggle — the kit's pill track
// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AppTabs(
      expand: true,
      index: selected,
      onChanged: onChanged,
      items: [
        AppTabItem('file_mode'.tr, icon: Icons.upload_file_rounded),
        AppTabItem('link_mode'.tr, icon: Icons.link_rounded),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File type selector (image / video / document): wells on the paper, the chosen one tinted with its type
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
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Row(
      children: List.generate(options.length, (i) {
        final opt = options[i];
        final selected = i == selectedIndex;
        final surface = selected ? Color.alphaBlend(opt.color.withValues(alpha: 0.14), c.cardBg) : c.inputBg;
        final ink = selected ? c.blockAccentInk(opt.color, surface) : c.textMedium;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: i < options.length - 1 ? AppSpace.xs : 0),
            child: Semantics(
              button: true,
              selected: selected,
              child: AppPressScale(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadius.cardAll,
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: motion.fast,
                      curve: AppMotion.curve,
                      constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xxs),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: AppRadius.cardAll,
                        border: Border.all(
                          color: selected ? opt.color : c.divider,
                          width: selected ? AppBorder.strong : AppBorder.hairline,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(opt.icon, color: ink, size: AppIconSize.lg - 2),
                          const SizedBox(height: AppSpace.xxs + 1),
                          Text(
                            opt.labelKey.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
    final c = context.colors;
    final picked = pickedFile != null;
    final borderColor = errorText != null
        ? c.danger
        : (picked ? color : Color.lerp(c.divider, c.textLight, 0.5)!);
    final well = Color.alphaBlend(color.withValues(alpha: 0.12), c.cardBg);

    Widget content;
    if (picked) {
      content = Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
        child: Row(
          children: [
            Container(
              width: AppSpace.xl + AppSpace.xs,
              height: AppSpace.xl + AppSpace.xs,
              decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
              child: Icon(icon, color: c.blockAccentInk(color, well), size: AppIconSize.md),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickedFile!.name,
                    style: AppType.row(context).copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _humanFileSize(pickedSize),
                    textDirection: TextDirection.ltr,
                    style: AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onTap,
              tooltip: 'tap_to_pick_file'.tr,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.autorenew_rounded, size: AppIconSize.md - 2, color: c.blockAccentInk(c.primary, c.cardBg)),
            ),
            IconButton(
              onPressed: onClear,
              tooltip: 'close'.tr,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.close_rounded, size: AppIconSize.md - 2, color: c.textMedium),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: Column(
          children: [
            Container(
              width: AppSpace.xxl - AppSpace.xxs,
              height: AppSpace.xxl - AppSpace.xxs,
              decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
              child: Icon(Icons.cloud_upload_outlined, size: AppIconSize.lg - 2, color: c.blockAccentInk(c.primary, c.cardBg)),
            ),
            const SizedBox(height: AppSpace.xs),
            Text('tap_to_pick_file'.tr, style: AppType.bodyStrong(context).copyWith(color: c.textMedium)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: !picked,
          child: GestureDetector(
            onTap: picked ? null : onTap,
            child: CustomPaint(
              painter: picked
                  ? null
                  : _DashedRRectPainter(
                color: borderColor,
                radius: AppRadius.card,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: picked ? Color.alphaBlend(color.withValues(alpha: 0.05), c.cardBg) : c.inputBg,
                  borderRadius: AppRadius.cardAll,
                  border: picked ? Border.all(color: borderColor, width: AppBorder.hairline) : null,
                ),
                child: content,
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpace.xs - 2),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs),
            child: Text(errorText!, style: AppType.meta(context).copyWith(color: c.danger)),
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
  final double strokeWidth = AppBorder.strong;
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
// Text field: the kit's label above a warm well
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFieldLabel(label),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context, hint: hint, icon: icon, suffix: trailing, errorText: errorText),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit button — the sheet's one primary action
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool saving;
  final bool enabled;
  final VoidCallback onPressed;

  /// Below this width Cancel and Add stack (the two large buttons need about 300 px side by side at 1.3× text).
  static const double _stackBelow = 340;

  const _SubmitButton({
    required this.saving,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // a faded look while the form is incomplete; a tap still runs [onPressed] so its checks explain what is missing
    return AnimatedOpacity(
      opacity: enabled || saving ? 1 : 0.5,
      duration: AppMotion.of(context).fast,
      child: LayoutBuilder(builder: (context, box) {
        Widget cancel({bool expand = false}) => AppButton.secondary(
              label: 't1_cp_cancel'.tr,
              size: AppButtonSize.lg,
              expand: expand,
              onPressed: saving ? null : () => Navigator.pop(context),
            );
        final add = AppButton.primary(
          label: 't1_cp_mat_add'.tr,
          icon: Icons.upload_rounded,
          size: AppButtonSize.lg,
          expand: true,
          busy: saving,
          onPressed: saving ? null : onPressed,
        );
        // a narrow phone (or large text) stacks them: the primary on top, Cancel under it
        if (box.maxWidth < _stackBelow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [add, AppSpace.gapXs, cancel(expand: true)]);
        }
        return Row(children: [cancel(), const SizedBox(width: AppSpace.sm), Expanded(child: add)]);
      }),
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
    final c = context.colors;
    final tint = Color.alphaBlend(c.dangerTint, c.cardBg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm - 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: c.danger.withValues(alpha: 0.3), width: AppBorder.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: AppIconSize.sm, color: c.blockAccentInk(c.danger, tint)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(message, style: AppType.label(context).copyWith(color: c.blockAccentInk(c.danger, tint)))),
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