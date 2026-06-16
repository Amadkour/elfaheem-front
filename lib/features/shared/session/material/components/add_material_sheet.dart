// shared/session/components/add_material_sheet.dart
//
// Bottom sheet for adding a new material (file upload or external link).
// Scoped to TeacherCourseScreenProvider via context.read — no extra provider
// wrapper needed since it's always opened from within the provider scope.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/app_theme.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../teacher/sessions/sessions_provider.dart';
import 'session_shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry — small button that opens the sheet
// ─────────────────────────────────────────────────────────────────────────────

class AddMaterialButton extends StatelessWidget {
  final int sessionId;

  const AddMaterialButton({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<TeacherCourseScreenProvider>(),
          child: AddMaterialSheet(sessionId: sessionId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.themeConfig.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: context.themeConfig.primary.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, size: 14, color: context.themeConfig.primary),
          const SizedBox(width: 4),
          Text(
            'add_material'.tr,
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 11,
              color: context.themeConfig.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sheet itself
// ─────────────────────────────────────────────────────────────────────────────

class AddMaterialSheet extends StatefulWidget {
  final int sessionId;

  const AddMaterialSheet({super.key, required this.sessionId});

  @override
  State<AddMaterialSheet> createState() => _AddMaterialSheetState();
}

class _AddMaterialSheetState extends State<AddMaterialSheet> {
  int _mode = 0; // 0 = file, 1 = link
  int _fileTypeIdx = 0;
  PlatformFile? _pickedFile;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  static const _fileTypeOptions = [
    _FileTypeOption(
      labelKey: 'material_type_image',
      icon: Icons.image_rounded,
      fileType: FileType.image,
      color: Color(0xFF4CAF50),
    ),
    _FileTypeOption(
      labelKey: 'material_type_video',
      icon: Icons.play_circle_rounded,
      fileType: FileType.video,
      color: Color(0xFF2196F3),
    ),
    _FileTypeOption(
      labelKey: 'pdf_document',
      icon: Icons.description_rounded,
      fileType: FileType.custom,
      color: Color(0xFFF44336),
    ),
  ];

  static const _documentExtensions = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt',
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
    final result = await FilePicker.pickFiles(
      type: opt.fileType,
      allowedExtensions:
          opt.fileType == FileType.custom ? _documentExtensions : null,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _pickedFile = result.files.first);
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text =
            _pickedFile!.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('please_enter_name'.tr);
      return;
    }

    final prov = context.read<TeacherCourseScreenProvider>();
    setState(() => _saving = true);

    try {
      if (_mode == 0) {
        if (_pickedFile == null) {
          _showError('please_pick_file'.tr);
          return;
        }
        final bytes = _pickedFile!.bytes;
        if (bytes == null) {
          _showError('file_load_failed'.tr);
          return;
        }
        await prov.uploadFileMaterial(
          sessionId: widget.sessionId,
          fileName: _pickedFile!.name,
          fileBytes: bytes,
          name: name,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
      } else {
        final url = _urlCtrl.text.trim();
        if (url.isEmpty) {
          _showError('please_enter_url'.tr);
          return;
        }
        await prov.addLinkMaterial(
          sessionId: widget.sessionId,
          name: name,
          url: url,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
      backgroundColor: context.themeConfig.danger,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: context.themeConfig.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.themeConfig.textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text('add_material_title'.tr, style: context.colors.h3),
            const SizedBox(height: 16),

            // Mode toggle (file / link)
            _ModeToggle(
              selected: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 16),

            if (_mode == 0) ...[
              _FileTypeSelector(
                options: _fileTypeOptions,
                selectedIndex: _fileTypeIdx,
                onChanged: (i) => setState(() => _fileTypeIdx = i),
              ),
              const SizedBox(height: 14),
              _FilePickerZone(pickedFile: _pickedFile, onTap: _pickFile),
            ] else
              SessionField(ctrl: _urlCtrl, label: 'url_label'.tr),

            const SizedBox(height: 12),
            SessionField(ctrl: _nameCtrl, label: 'name_label'.tr),
            const SizedBox(height: 10),
            SessionField(ctrl: _descCtrl, label: 'description_optional'.tr),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _saving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        key: const ValueKey('submit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.themeConfig.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _submit,
                        child: Text(
                          'add_material_btn'.tr,
                          style: const TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File / Link mode toggle
// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeConfig.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: context.themeConfig.textLight.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        _segment('file_mode'.tr, 0, Icons.upload_file_rounded, context),
        _segment('link_mode'.tr, 1, Icons.link_rounded, context),
      ]),
    );
  }

  Widget _segment(
      String label, int index, IconData icon, BuildContext context) {
    final sel = selected == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? context.themeConfig.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 15,
                color:
                    sel ? Colors.white : context.themeConfig.textMedium),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    sel ? Colors.white : context.themeConfig.textMedium,
              ),
            ),
          ]),
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
              margin: EdgeInsets.only(left: i < options.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? opt.color.withValues(alpha: 0.15)
                    : context.themeConfig.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? opt.color
                      : context.themeConfig.textLight.withValues(alpha: 0.2),
                ),
              ),
              child: Column(children: [
                Icon(opt.icon,
                    color: selected
                        ? opt.color
                        : context.themeConfig.textLight,
                    size: 22),
                const SizedBox(height: 4),
                Text(
                  opt.labelKey.tr,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? opt.color
                        : context.themeConfig.textLight,
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop-zone / picked-file indicator
// ─────────────────────────────────────────────────────────────────────────────

class _FilePickerZone extends StatelessWidget {
  final PlatformFile? pickedFile;
  final VoidCallback onTap;

  const _FilePickerZone({required this.pickedFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final picked = pickedFile != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: picked
              ? context.themeConfig.success.withValues(alpha: 0.08)
              : context.themeConfig.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: picked
                ? context.themeConfig.success.withValues(alpha: 0.4)
                : context.themeConfig.textLight.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Icon(
            picked
                ? Icons.check_circle_rounded
                : Icons.upload_file_rounded,
            size: 28,
            color:
                picked ? context.themeConfig.success : context.themeConfig.textMedium,
          ),
          const SizedBox(height: 6),
          Text(
            picked ? pickedFile!.name : 'tap_to_pick_file'.tr,
            style: context.colors.body.copyWith(
              fontSize: 13,
              color: picked
                  ? context.themeConfig.success
                  : context.themeConfig.textMedium,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
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
