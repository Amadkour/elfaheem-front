// lib/design/app_username.dart
//
// The @username in people lists and pickers (D-071 v2: the server's people searches also match `users.username`,
// and their rows carry `"username"`).
//
//   usernameFrom(row)                 the row's username, read defensively (also from a nested user / student map)
//   AppUsernameLine(username)         "@name" under a person's name: muted, left to right, nothing when absent
//
// Both follow the kill switch `auth.username` (the line hides itself).
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../core/display/app_fonts.dart';

/// The username of a people row: `username` on the row, else on its `user` / `student` map. Null when missing,
/// empty or not a string; a leading "@" is dropped.
String? usernameFrom(Object? row) {
  String? read(Object? m) {
    if (m is! Map) return null;
    final v = m['username'];
    if (v is! String) return null;
    var s = v.trim();
    if (s.startsWith('@')) s = s.substring(1);
    return s.isEmpty ? null : s;
  }

  if (row is! Map) return null;
  return read(row) ?? read(row['user']) ?? read(row['student']);
}

/// "@name" in small muted ink, always left to right (also in Arabic). Nothing when [username] is null / empty or the
/// kill switch `auth.username` is on.
class AppUsernameLine extends StatelessWidget {
  const AppUsernameLine(this.username, {super.key, this.fontSize = 12});

  final String? username;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final u = username;
    if (u == null || u.isEmpty || AppConfig.disableList.contains('auth.username')) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return Text(
      '@$u',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontFamily: AppFonts.family,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: c.isDark ? c.primaryLight : c.primary,
      ),
    );
  }
}
