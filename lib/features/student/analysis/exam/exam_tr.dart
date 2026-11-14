import 'package:flutter_education_app/config/app_config.dart';

/// Translates [key] (from translation.json) and fills `{placeholders}`.
///
///   tx('exam_n_questions', {'n': 10})  ->  "10 questions" / "10 سؤال"
String tx(String key, [Map<String, Object?> params = const {}]) {
  var s = key.tr;
  params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}
