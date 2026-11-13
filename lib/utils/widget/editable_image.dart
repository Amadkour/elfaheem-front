// ── Image picking ──────────────────────────────────────────────────────────
import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appConfirm, AppSheetContent, AppSpace, AppRadius, AppBorder, AppIconSize, AppElevation, AppType, AppBlockColors, AppBlockTone;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';

class EditableImage extends StatelessWidget {
  const EditableImage(
      {super.key,
      required this.onChange,
      this.imageUrl,
      this.imageByte,
      this.imageFile, required this.size, this.isCircle=false, this.name,
      this.onRemove, this.removeMessage});

  final Future<void> Function(XFile file) onChange;
  final String? imageUrl;
  final XFile? imageFile;
  final Uint8List? imageByte;
  final double size;
  final bool isCircle;

  /// The person's name for an avatar without a photo: its first letter, like every other avatar of the app
  /// (N10), with the camera badge to add one. Null keeps the "add a picture" placeholder (covers, logos).
  final String? name;

  /// Shows "Remove picture" under the two sources while a picture is shown (D-880). Called after an `appConfirm`
  /// that reads [removeMessage]; the caller deletes it (or drops an unsaved pick) and shows the fallback.
  final Future<void> Function()? onRemove;

  /// What the confirm says will be removed (and what shows instead); a generic sentence when null.
  final String? removeMessage;

  bool get _hasPicture => imageByte != null || (imageUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
        padding: const EdgeInsets.all(AppSpace.xs),
        child: Stack(
          clipBehavior : Clip.none,
      children: [
        // Image picker — overlaps bottom of header
        Positioned(
          child: Center(
            child: GestureDetector(
              onTap: () => _pickImage(context,onChange),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape:isCircle? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isCircle ? null : BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: context.colors.cardBg, width: AppBorder.focus),
                  boxShadow: AppElevation.of(context, 2),
                ),
                child: isCircle? ClipOval(
                  child: _imageChild(context, imageByte, imageUrl),
                ):ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  clipBehavior: Clip.hardEdge,
                  child: _imageChild(context, imageByte, imageUrl),
                ),
              ),
            ),
          ),
        ),
        if (_hasPicture || name != null)
          Positioned(
            bottom: isCircle?0 :0,
            left:isCircle? (size/1.7): - 10,
            child: InkWell(
              customBorder: isCircle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
              onTap: () => _pickImage(context,onChange),
              child: Container(
                width: AppIconSize.xl,
                height: AppIconSize.xl,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape:isCircle? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isCircle ? null : BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: context.colors.cardBg, width: AppBorder.focus),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: AppIconSize.sm,
                  color: context.colors.onHero,
                ),
              ),
            ),
          ),
      ],
    ));
  }

  Widget _imageChild(BuildContext context, Uint8List? bytes, String? url) {
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    if (url != null && url.isNotEmpty) {
      return AppNetworkImage( url: url,);
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final n = name?.trim() ?? '';
    if (name != null) {
      // An avatar without a photo: the first letter in ink on the person's own block tone (stable per name).
      final block = AppBlockColors.of(context, AppBlockTone.forKey('person-$n'));
      return Container(
        color: block.surface,
        alignment: Alignment.center,
        child: Text(n.isNotEmpty ? n.characters.first.toUpperCase() : '?',
            style: AppType.figureLarge(context).copyWith(fontSize: size * 0.36, height: 1, color: block.ink)),
      );
    }
    return _addPicture(context);
  }

  Widget _addPicture(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          color: context.colors.inputBg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_rounded,
                size: AppIconSize.lg, color: context.colors.primary),
            const SizedBox(height: AppSpace.xxs),
            Flexible(
              child: Text('صورة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.overline(context).copyWith(color: context.colors.textMedium)),
            ),
          ],
        ),
      );

  Future<void> _pickImage(BuildContext context,Future<void> Function(XFile file) onChange) async {
    final canRemove = onRemove != null && _hasPicture;
    final choice = await showAppSideSheet<ImageSheetChoice>(context,
        builder: (_) => ImageSourceSheet(canRemove: canRemove));
    if (choice == null || !context.mounted) return;
    if (choice == ImageSheetChoice.remove) {
      final ar = AppConfig.lang == 'ar';
      final ok = await appConfirm(context,
          message: removeMessage ?? (ar ? 'إزالة هذه الصورة؟' : 'Remove this picture?'),
          danger: true,
          confirmLabel: ar ? 'إزالة' : 'Remove');
      if (ok && context.mounted) await onRemove!();
      return;
    }

    final xFile = await ImagePicker().pickImage(
      source: choice == ImageSheetChoice.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,          // the cropper decides the final size
      maxHeight: 2400,
      imageQuality: 92,
    );
    if (xFile == null) return;

    if (!context.mounted) return;

    // Crop / zoom / circle / output size before uploading (the app-wide cropper).
    final cropped = await showAppImageCropper(context, await xFile.readAsBytes());
    if (cropped == null || !context.mounted) return;
    onChange(XFile.fromData(cropped, name: 'photo.png', mimeType: 'image/png'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image source bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// What the picture sheet answered: a source for a new picture, or remove the current one (D-880).
enum ImageSheetChoice { gallery, camera, remove }

/// The sheet behind every picture picker: Gallery, Camera and, while a picture is shown, Remove (public so a layout
/// test can pump it).
class ImageSourceSheet extends StatelessWidget {
  const ImageSourceSheet({super.key, this.canRemove = false});

  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return AppSheetContent(
      title: ar ? 'صورة' : 'Picture',
      children: [
        _SheetTile(
          icon: Icons.photo_library_rounded,
          label: ar ? 'من المعرض' : 'From the gallery',
          color: context.colors.primary,
          onTap: () => Navigator.pop(context, ImageSheetChoice.gallery),
        ),
        _SheetTile(
          icon: Icons.camera_alt_rounded,
          label: ar ? 'الكاميرا' : 'Camera',
          color: context.colors.success,
          onTap: () => Navigator.pop(context, ImageSheetChoice.camera),
        ),
        if (canRemove)
          _SheetTile(
            key: const ValueKey('image_remove'),
            icon: Icons.delete_outline_rounded,
            label: ar ? 'إزالة الصورة' : 'Remove picture',
            color: context.colors.danger,
            onTap: () => Navigator.pop(context, ImageSheetChoice.remove),
          ),
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          width: AppIconSize.hero,
          height: AppIconSize.hero,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Icon(icon, color: color, size: AppIconSize.md),
        ),
        title: Text(label,
            style: AppType.row(context)),
      );
}
