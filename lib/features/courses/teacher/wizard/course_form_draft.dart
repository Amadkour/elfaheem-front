// features/courses/teacher/wizard/course_form_draft.dart — what the course form holds besides the provider: the text
// controllers, the picked cover, the reel controller and the small flags. It was the private state of
// course_form_screen.dart; the step widgets read it so each step is a widget of its own. Any change notifies, the
// screen rebuilds (as the old `ctrl.addListener(_rebuild)` did).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_reel_field.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseStatus;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:image_picker/image_picker.dart';

class CourseFormDraft extends ChangeNotifier {
  CourseFormDraft(this.course) {
    final c = course;
    isPrivate = c?.isPrivate ?? false;
    reelCtrl = CourseReelController(courseId: c?.id);
    if (c != null) reelCtrl.loadExisting(); // the stored reel, so it can be watched, replaced or removed

    titleAr = TextEditingController(text: (c?.titleAr ?? c?.titleEn) ?? '');
    titleEn = TextEditingController(text: (c?.titleEn ?? c?.titleAr) ?? '');
    descAr = TextEditingController(text: (c?.descriptionAr ?? c?.descriptionEn) ?? '');
    descEn = TextEditingController(text: (c?.descriptionEn ?? c?.descriptionAr) ?? '');
    price = TextEditingController(text: c != null ? (c.priceYearly ?? c.price).toString() : '');
    priceMonthly = TextEditingController(text: c?.priceMonthly != null ? c!.priceMonthly.toString() : '');
    priceSixMonths = TextEditingController(text: c?.priceSixMonths != null ? c!.priceSixMonths.toString() : '');
    hours = TextEditingController(text: c != null ? c.expectedHours.toString() : '');
    discountPercent = TextEditingController(
        text: c?.discountPercentage != null && c!.discountPercentage! > 0 ? c.discountPercentage.toString() : '');
    discountDays = TextEditingController(text: c?.discountDays?.toString() ?? '');
    for (final ctrl in _listened) {
      ctrl.addListener(notifyListeners);
    }
    // Rebuild on pick/replace/remove so the Save button and the preview update immediately.
    reelCtrl.addListener(notifyListeners);
    isPublished = c?.isPublished ?? false;
    progressStatus = c?.status ?? CourseStatus.inProgress;
    certTitle = TextEditingController(text: 'default_certificate_title'.tr);
  }

  /// null → CREATE mode, non-null → EDIT mode.
  final TeacherCourse? course;
  bool get isEdit => course != null;

  late bool isPrivate;
  final accessCode = TextEditingController();
  final address = TextEditingController(); // the in-person address (D-1314)
  late final TextEditingController titleAr, titleEn, descAr, descEn;
  late final TextEditingController price; // YEARLY price
  late final TextEditingController priceMonthly, priceSixMonths, hours;
  late final TextEditingController discountPercent, discountDays;
  final ExpansibleController categoryCtrl = ExpansibleController();
  final ExpansibleController typeCtrl = ExpansibleController();
  bool removeDiscount = false;
  XFile? logoFile;
  Uint8List? logoBytes;

  /// The stored cover was removed on this visit (D-880): the form shows the default cover from now on.
  bool coverRemoved = false;
  String? get coverUrl => coverRemoved ? null : course?.imageUrl;

  /// Optional course reel (عرض أولي), uploads itself; the form only calls commit() once the course id is known.
  late final CourseReelController reelCtrl;

  /// Optional certificate template, create mode only. A title with no file is ignored (submitCreate).
  XFile? certTemplateFile;
  late final TextEditingController certTitle;

  /// Edit-mode publish/draft status, and the course's content status (in_progress / completed).
  late bool isPublished;
  bool statusLoading = false;
  late CourseStatus progressStatus;
  bool progressStatusLoading = false;

  List<TextEditingController> get _listened =>
      [titleAr, titleEn, descAr, descEn, price, priceMonthly, priceSixMonths, hours, discountPercent, discountDays];

  bool get hasBasics => titleAr.text.trim().isNotEmpty || titleEn.text.trim().isNotEmpty;

  /// Rebuild the screen after a flag changed.
  void touch() => notifyListeners();

  /// The Save button's dirty check.
  bool hasChanges(CourseFormProvider p) {
    if (!isEdit) return hasBasics;
    final c = course!;
    final oldYearly = c.priceYearly ?? c.price;
    final newPrice = double.tryParse(price.text) ?? oldYearly;
    final newMonthly = double.tryParse(priceMonthly.text);
    final newSixMonths = double.tryParse(priceSixMonths.text);
    final newHours = double.tryParse(hours.text) ?? c.expectedHours;
    final newDiscount = double.tryParse(discountPercent.text);
    final oldDiscount = c.discountPercentage;
    final newDays = int.tryParse(discountDays.text);
    final oldDays = c.discountDays;
    return titleAr.text.trim() != (c.titleAr ?? '') ||
        titleEn.text.trim() != (c.titleEn ?? '') ||
        newPrice != oldYearly ||
        newMonthly != c.priceMonthly ||
        newSixMonths != c.priceSixMonths ||
        newHours != c.expectedHours ||
        newDiscount != oldDiscount ||
        newDays != oldDays ||
        p.defaultPlanIndex != c.defaultPricePlanIndex ||
        removeDiscount ||
        logoFile != null ||
        p.setupDirty ||
        reelCtrl.hasChanges;
  }

  @override
  void dispose() {
    reelCtrl.removeListener(notifyListeners);
    reelCtrl.dispose();
    for (final ctrl in _listened) {
      ctrl.removeListener(notifyListeners);
      ctrl.dispose();
    }
    certTitle.dispose();
    accessCode.dispose();
    address.dispose();
    super.dispose();
  }
}
