// ── Image picking ──────────────────────────────────────────────────────────
import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSheetContent, AppSpace, AppRadius, AppBorder, AppIconSize, AppElevation, AppType, AppBlockColors, AppBlockTone;
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
      this.imageFile, required this.size, this.isCircle=false, this.name});

  final Future<void> Function(XFile file) onChange;
  final String? imageUrl;
  final XFile? imageFile;
  final Uint8List? imageByte;
  final double size;
  final bool isCircle;

  /// The person's name for an avatar without a photo: its first letter, like every other avatar of the app
  /// (N10), with the camera badge to add one. Null keeps the "add a picture" placeholder (covers, logos).
  final String? name;

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
        if (imageByte != null || (imageUrl ?? '').isNotEmpty || name != null)
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
    final source = await showAppSideSheet<ImageSource>(context, builder: (_) => _ImageSourceSheet());
    if (source == null) return;

    final xFile = await ImagePicker().pickImage(
      source: source,
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

class _ImageSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return AppSheetContent(
      title: ar ? 'اختر مصدر الصورة' : 'Choose an image source',
      children: [
        _SheetTile(
          icon: Icons.photo_library_rounded,
          label: ar ? 'من المعرض' : 'From the gallery',
          color: context.colors.primary,
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
        _SheetTile(
          icon: Icons.camera_alt_rounded,
          label: ar ? 'الكاميرا' : 'Camera',
          color: context.colors.success,
          onTap: () => Navigator.pop(context, ImageSource.camera),
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
      {required this.icon,
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
