// lib/features/games/content/level_store_web.dart — the web has no device database: offline pools do not exist there
// (CONTRACT §4: the web never calls GET /pool). LevelCache is switched off on the web, this is only the stub.
import 'package:flutter_education_app/features/games/content/level_cache.dart';

Future<LevelStore> openLevelStore() async => MemoryLevelStore();
