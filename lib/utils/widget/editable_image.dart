// ── Image picking ──────────────────────────────────────────────────────────
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class EditableImage extends StatelessWidget {
  const EditableImage(
      {super.key,
      required this.onChange,
      this.imageUrl,
      this.imageByte,
      this.imageFile, required this.size, this.isCircle=false});

  final Future<void> Function(XFile file) onChange;
  final String? imageUrl;
  final XFile? imageFile;
  final Uint8List? imageByte;
  final double size;
  final bool isCircle;
  @override
  Widget build(BuildContext context) {
    print(context.height/10);
    return Container(
      height: size,
      width: size,
        padding: EdgeInsets.all(10),
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
                  borderRadius:isCircle?null: BorderRadius.all(Radius.circular(20)),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: isCircle? ClipOval(
                  child: _imageChild(context, imageByte, imageUrl),
                ):ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.hardEdge,
                  child: _imageChild(context, imageByte, imageUrl),
                ),
              ),
            ),
          ),
        ),
        if (imageByte != null || imageUrl != null)
          Positioned(
            bottom: isCircle?0 :0,
            left:isCircle? (size/1.7): - 10,
            child: InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              onTap: () => _pickImage(context,onChange),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  shape:isCircle? BoxShape.circle : BoxShape.rectangle,
                  borderRadius:isCircle?null: BorderRadius.all(Radius.circular(10)),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: Colors.white,
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

  Widget _placeholder(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape:isCircle? BoxShape.circle : BoxShape.rectangle,
            color: context.colors.primary.withValues(alpha: 0.10),

  ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_rounded,
                size: 26, color: context.colors.primary),
            SizedBox(height: 4),
            Text('صورة',
                style: TextStyle(
                    fontSize: 9,
                    color: context.colors.primary,
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _pickImage(BuildContext context,Future<void> Function(XFile file) onChange) async {
    final source = await showModalBottomSheet<ImageSource>(
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageSourceSheet(),
    );
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        // Material, not a coloured Container: the ListTiles paint their ink on it (Flutter reports
        // "ListTile background color or ink splashes may be invisible" under a coloured box).
        child: Material(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('اختر مصدر الصورة',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.display,
                    color: context.colors.textDark)),
            const SizedBox(height: 16),
            _SheetTile(
              icon: Icons.photo_library_rounded,
              label: 'من المعرض',
              color: context.colors.primary,
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            _SheetTile(
              icon: Icons.camera_alt_rounded,
              label: 'الكاميرا',
              color: context.colors.success,
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 16),
          ],
        ),
          ),
        ),
      );
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label,
            style: TextStyle(fontFamily: AppFonts.display, fontSize: 14)),
      );
}
