// The Super Admin's switches of the automatic exam tools (D-301), on the app side: a switched-off key hides its UI
// (`ParentComponent(featureKey:)`), and an action reached another way stops here with one notice instead of a 403.
// The services refuse them too (403 `feature_disabled`), which [examFeatureCodeText] words.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_notice.dart';

import '../../admin/admin_common.dart' show t;
import 'exam_gen_api.dart' show kExamAutoCorrectKey, kExamAutoCreateKey;

export 'exam_gen_api.dart' show kExamAutoCorrectKey, kExamAutoCreateKey;

/// False (after a notice) when the Super Admin switched automatic correction off.
bool examAutoCorrectAllowed() {
  if (!AppConfig.disableList.contains(kExamAutoCorrectKey)) return true;
  showAppNotice(t('التصحيح التلقائي متوقف حالياً من إدارة المنصة', 'Automatic correction is switched off by the platform right now'), error: true);
  return false;
}

/// The text of a `feature_disabled` refusal, by the key the server names; null for any other code.
String? examFeatureCodeText(String? code, [String? feature]) {
  if (code != 'feature_disabled') return null;
  return switch (feature) {
    kExamAutoCreateKey => t('إنشاء الأسئلة تلقائياً متوقف حالياً', 'Automatic question generation is switched off right now'),
    kExamAutoCorrectKey => t('التصحيح التلقائي متوقف حالياً', 'Automatic correction is switched off right now'),
    _ => t('هذه الميزة متوقفة حالياً', 'This feature is switched off right now'),
  };
}
