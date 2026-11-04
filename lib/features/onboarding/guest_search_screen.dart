// The interactive guest search: "I want to learn [subject] for [level], studying [anywhere / online / at a center]"
// with a live "N courses · M teachers" count, a primary "Show courses" (guest mode + the explorer) and Log in /
// Create account underneath. Every landing call fails soft: no counts, the button still works.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/plural.dart';
import '../../design/app_kit.dart' show AppDropdown, appText;
import '../../design/app_tokens.dart';
import '../../utils/widget/primary_button.dart';
import 'explore_launcher.dart';
import 'landing_api.dart';
import 'onboarding_store.dart';

class GuestSearchScreen extends StatefulWidget {
  const GuestSearchScreen({super.key, this.loadOptions, this.loadMatch, this.onShow, this.onLogin, this.onRegister});

  final LandingOptionsLoader? loadOptions;
  final LandingMatchLoader? loadMatch;

  /// (category id: level, else subject; mode). Default: guest mode + the explorer.
  final void Function(int? categoryId, String mode)? onShow;
  final VoidCallback? onLogin;
  final VoidCallback? onRegister;

  @override
  State<GuestSearchScreen> createState() => _GuestSearchScreenState();
}

class _GuestSearchScreenState extends State<GuestSearchScreen> {
  List<LandingSubject> _subjects = const [];
  bool _loading = true;
  int _subject = 0; // 0 = any
  int _level = 0;
  String _mode = 'any';
  LandingCount? _count;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    OnboardingStore.markSeen();
    _loadOptions();
    _scheduleMatch(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final list = await (widget.loadOptions ?? LandingApi.options)();
    if (!mounted) return;
    setState(() {
      _subjects = list;
      _loading = false;
    });
  }

  void _scheduleMatch({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 250), _runMatch);
  }

  Future<void> _runMatch() async {
    final seq = ++_seq;
    final r = await (widget.loadMatch ?? LandingApi.match)(
        subject: _subject == 0 ? null : _subject, level: _level == 0 ? null : _level, mode: _mode);
    if (!mounted || seq != _seq) return;
    setState(() => _count = r);
  }

  LandingSubject? get _current {
    for (final s in _subjects) {
      if (s.id == _subject) return s;
    }
    return null;
  }

  String _countLine() {
    final n = _count;
    if (n == null) return '';
    final courses = countText(n.courses,
        ar1: 'دورة واحدة', ar2: 'دورتان', arFew: '${n.courses} دورات', arMany: '${n.courses} دورة', en1: '1 course', en: '${n.courses} courses',
        ar0: 'لا توجد دورات', en0: 'No courses');
    final teachers = countText(n.teachers,
        ar1: 'معلم واحد', ar2: 'معلمان', arFew: '${n.teachers} معلمين', arMany: '${n.teachers} معلمًا', en1: '1 teacher', en: '${n.teachers} teachers',
        ar0: 'لا معلمين', en0: 'no teachers');
    return '$courses · $teachers';
  }

  void _show() {
    final id = _level != 0 ? _level : (_subject != 0 ? _subject : null);
    if (widget.onShow != null) return widget.onShow!(id, _mode);
    openGuestExplore(Navigator.of(context), categoryId: id, mode: _mode);
  }

  void _go(String route, VoidCallback? override) {
    if (override != null) return override();
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final levels = _current?.levels ?? const <LandingLevel>[];
    final line = _countLine();
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: AppSpace.md),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                    child: Image.asset('assets/images/logo_mark.png',
                        errorBuilder: (_, _, _) => Icon(Icons.school_outlined, size: 32, color: c.primary)),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Text('ob_search_title'.tr, textAlign: TextAlign.center, style: AppType.pageTitle(context).copyWith(fontSize: 24)),
                const SizedBox(height: AppSpace.xs),
                Text('ob_search_sub'.tr, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(fontSize: 14)),
                const SizedBox(height: AppSpace.lg),
                Container(
                  padding: AppSpace.card,
                  decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, boxShadow: AppShadow.card(context)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _Label('ob_i_want'.tr),
                    AppDropdown<int>(
                      value: _subject,
                      enabled: !_loading && _subjects.isNotEmpty,
                      decoration: InputDecoration(labelText: 'ob_subject_sheet'.tr, hintText: 'ob_subject_hint'.tr),
                      items: [
                        DropdownMenuItem(value: 0, child: Text('ob_subject_hint'.tr)),
                        for (final s in _subjects) DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _subject = v ?? 0;
                          _level = 0;
                        });
                        _scheduleMatch();
                      },
                    ),
                    const SizedBox(height: AppSpace.md),
                    _Label('ob_for_level'.tr),
                    AppDropdown<int>(
                      value: _level,
                      enabled: levels.isNotEmpty,
                      decoration: InputDecoration(labelText: 'ob_level_sheet'.tr, hintText: 'ob_level_hint'.tr),
                      items: [
                        DropdownMenuItem(value: 0, child: Text('ob_level_hint'.tr)),
                        for (final l in levels) DropdownMenuItem(value: l.id, child: Text(l.name)),
                      ],
                      onChanged: (v) {
                        setState(() => _level = v ?? 0);
                        _scheduleMatch();
                      },
                    ),
                    const SizedBox(height: AppSpace.md),
                    _Label('ob_how'.tr),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                      for (final m in const ['any', 'online', 'center'])
                        ChoiceChip(
                          label: Text('ob_mode_$m'.tr),
                          selected: _mode == m,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) {
                            setState(() => _mode = m);
                            _scheduleMatch();
                          },
                        ),
                    ]),
                    AnimatedSize(
                      duration: AppMotion.of(context).base,
                      child: line.isEmpty
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: AppSpace.md),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.auto_stories_outlined, size: 18, color: c.primary),
                                const SizedBox(width: AppSpace.xs),
                                Flexible(child: Text(line, textAlign: TextAlign.center, style: appText(14, w: FontWeight.w600, c: c.textDark))),
                              ]),
                            ),
                    ),
                  ]),
                ),
                const SizedBox(height: AppSpace.lg),
                PrimaryButton(isLoading: false, label: 'ob_show_courses'.tr, icon: Icons.search_rounded, iconBefore: true, onPressed: _show),
                const SizedBox(height: AppSpace.md),
                Text('ob_have_account'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xs),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                      onPressed: () => _go('/login', widget.onLogin),
                      child: Text('login'.tr),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                      onPressed: () => _go('/register', widget.onRegister),
                      child: Text('auth_create_account'.tr, textAlign: TextAlign.center),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Text(text, style: AppType.meta(context).copyWith(fontSize: 13)),
      );
}
