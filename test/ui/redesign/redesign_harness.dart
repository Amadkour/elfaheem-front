// Shared helpers of the redesign kit tests: a themed host with an optional area scope and Reduce motion.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_area.dart';

/// [child] inside the theme, a MaterialApp page, an optional [area] scope and [reduce] motion.
Widget kitHost(Widget child,
    {AppArea? area, AppRoleAccent? role, bool reduce = false, bool budget = true, TextDirection dir = TextDirection.rtl}) {
  Widget body = child;
  if (area != null) body = AppAreaScope(area: area, budget: budget, child: body);
  if (role != null) body = AppAreaScope.role(role: role, budget: budget, child: body);
  return ThemeConfigScope(
    provider: ThemeConfigProvider(api: ApiClient()),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: Scaffold(body: Center(child: body)),
    ),
  );
}

/// True when no Transform under [root] carries a non-identity matrix and no Opacity is below 1.
bool atRest(Iterable<Element> elements) {
  for (final e in elements) {
    final w = e.widget;
    if (w is Transform && !w.transform.isIdentity()) return false;
    if (w is Opacity && w.opacity < 1) return false;
  }
  return true;
}
