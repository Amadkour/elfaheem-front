// `/explore?subject=&level=&mode=&lang=` opened by URL (the landing website's hero search). Applies `lang`, then:
// signed out -> guest mode + the guest home + the explorer on top; signed in -> the person's home + the explorer.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_language_switch.dart';
import '../auth/auth_provider.dart';
import 'explore_launcher.dart';
import 'start_route.dart';

class ExploreEntryPage extends StatefulWidget {
  const ExploreEntryPage({super.key, required this.request});

  final ExploreRequest request;

  @override
  State<ExploreEntryPage> createState() => _ExploreEntryPageState();
}

class _ExploreEntryPageState extends State<ExploreEntryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final r = widget.request;
    final lang = r.lang;
    if (lang != null && lang != AppConfig.lang) {
      await context.read<LangProvider>().changeLang(lang);
      refreshWholeUi();
    }
    if (!mounted) return;
    final auth = context.read<MyAuthProvider>();
    final nav = Navigator.of(context);
    if (auth.isAuthenticated) {
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
      openExplorer(nav, categoryId: r.categoryId, mode: r.mode);
    } else {
      openGuestExplore(nav, categoryId: r.categoryId, mode: r.mode);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: context.colors.background, body: const Center(child: CircularProgressIndicator()));
}
