// Tiny AR/EN helper for the new screens (swap for your .tr keys whenever you like).
import 'package:flutter_education_app/config/app_config.dart';

String gt(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
