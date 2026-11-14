// features/certificates/studio/cert_engine_photo_option.dart
//
// The student photo's setting in the certificate studio (D-386): required (the default for every photo, the issue flow
// asks for a photo of each person) or optional (a person with no photo keeps the space empty). Stored as
// `photo_optional: true` on the element, absent when required.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/studio/studio.dart' show StudioController;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

const String kPhotoOptionalKey = 'photo_optional';

bool certElementIsPhoto(LayoutElement el) => el.kind == 'image' && el.bind?.field == 'photo';

/// The switch under a selected student photo; null for any other element.
Widget? certPhotoOption(LayoutElement el, StudioController<LayoutElement> ctl) {
  if (!certElementIsPhoto(el)) return null;
  return _PhotoOption(el: el, ctl: ctl);
}

class _PhotoOption extends StatelessWidget {
  const _PhotoOption({required this.el, required this.ctl});
  final LayoutElement el;
  final StudioController<LayoutElement> ctl;

  @override
  Widget build(BuildContext context) {
    final required = el.extra[kPhotoOptionalKey] != true;
    return AppSwitchTile(
      key: const ValueKey('cert-photo-required'),
      value: required,
      icon: Icons.account_box_outlined,
      title: t('الصورة مطلوبة لكل مستلم', 'Photo required for every recipient'),
      subtitle: required
          ? t('لن تُصدر الشهادة حتى تتوفر صورة كل شخص', 'Certificates are not issued until every person has a photo')
          : t('من لا صورة له تبقى مساحة صورته فارغة', 'People with no photo keep this space empty'),
      onChanged: (v) => ctl.record('photo', () {
        if (v) {
          el.extra.remove(kPhotoOptionalKey);
        } else {
          el.extra[kPhotoOptionalKey] = true;
        }
      }),
    );
  }
}
