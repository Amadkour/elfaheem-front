// "Show courses": guest mode, the guest home, and the course explorer on top of it (Back leads to the home).
library;

import 'package:flutter/material.dart';

import '../shared/category/categories_screen.dart';
import '../shared/guest/guest_state.dart';

/// Starts guest mode, lands on `/dashboard` and pushes the explorer for [categoryId] (a level, else a subject; null =
/// every course) filtered by [mode] ('any' | 'online' | 'center').
void openGuestExplore(NavigatorState nav, {int? categoryId, String mode = 'any'}) {
  GuestState.instance.start();
  nav.pushNamedAndRemoveUntil('/dashboard', (r) => false);
  openExplorer(nav, categoryId: categoryId, mode: mode);
}

/// The explorer over whatever is on screen (a signed-in person's home too).
void openExplorer(NavigatorState nav, {int? categoryId, String mode = 'any'}) {
  nav.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/explore-result'),
    builder: (_) => CategoriesScreen(selectedId: categoryId?.toString(), mode: mode),
  ));
}
