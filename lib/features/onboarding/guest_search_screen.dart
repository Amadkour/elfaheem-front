// The interactive guest search (redesign Stu1Auth?screen=guestsearch, S-A2): ONE sentence on a card, "أبي أتعلّم
// [subject] لصف [grade] وأدرس [any / remote / in person]", each choice a coloured pill that opens its sheet (the
// subject sheet is a searchable grid of subject tiles in their colours); the one "Show courses" button carries the
// live course count (guest mode + the explorer); Sign in / Create an account underneath. Every landing call fails
// soft: no counts, the button still works.
library;

import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/plural.dart';
import '../../design/app_kit.dart';
import '../../design/motion/motion.dart' show AppJelly;
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

  void _show() {
    final id = _level != 0 ? _level : (_subject != 0 ? _subject : null);
    if (widget.onShow != null) return widget.onShow!(id, _mode);
    openGuestExplore(Navigator.of(context), categoryId: id, mode: _mode);
  }

  void _go(String route, VoidCallback? override) {
    if (override != null) return override();
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _pickSubject() async {
    final id = await showAppSheet<int>(context, (_) => _SubjectSheet(subjects: _subjects, selected: _subject));
    if (id == null || !mounted || id == _subject) return;
    setState(() {
      _subject = id;
      _level = 0;
    });
    _scheduleMatch();
  }

  Future<void> _pickLevel(List<LandingLevel> levels) async {
    final id = await showAppSheet<int>(context, (_) => _LevelSheet(levels: levels, selected: _level));
    if (id == null || !mounted || id == _level) return;
    setState(() => _level = id);
    _scheduleMatch();
  }

  Future<void> _pickMode() async {
    final m = await showAppSheet<String>(context, (_) => _ModeSheet(selected: _mode));
    if (m == null || !mounted || m == _mode) return;
    setState(() => _mode = m);
    _scheduleMatch();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final levels = _current?.levels ?? const <LandingLevel>[];
    final level = levels.where((l) => l.id == _level).firstOrNull;
    final n = _count?.courses;
    final words = AppType.headline(context).copyWith(color: c.textDark);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SaHeroPage(area: AppArea.home, kicker: 'sa_gs_kicker'.tr, title: 'sa_gs_title'.tr, squiggle: 'sa_gs_squiggle'.tr, child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.md),
              // redesign (Stu1Auth?screen=guestsearch, S-A2): the search is ONE sentence on a card, each choice a
              // coloured pill that opens its sheet; the count rides on the one button
              child: AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('sa_gs_sub'.tr, style: AppType.body(context)),
                  AppSpace.gapLg,
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.sm,
                    children: [
                      Text('sa_gs_i_want'.tr, style: words),
                      _SentencePill(
                        key: const ValueKey('guest_search.subject'),
                        label: _current?.name ?? 'sa_gs_any_subject'.tr,
                        tone: _current == null ? kit.warmTone : kit.subject(subjectKeyFor(_current!.nameAr)).tone,
                        onTap: _loading || _subjects.isEmpty ? null : _pickSubject,
                      ),
                      Text('sa_gs_for'.tr, style: words),
                      _SentencePill(
                        key: const ValueKey('guest_search.level'),
                        label: level?.name ?? 'sa_gs_any_level'.tr,
                        tone: kit.accent(AppAccent.grape),
                        onTap: levels.isEmpty ? null : () => _pickLevel(levels),
                      ),
                      Text('sa_gs_study'.tr, style: words),
                      _SentencePill(
                        key: const ValueKey('guest_search.mode'),
                        label: 'sa_gs_mode_$_mode'.tr,
                        tone: kit.accent(AppAccent.sky),
                        onTap: _pickMode,
                      ),
                    ],
                  ),
                  AppSpace.gapLg,
                  AppButton.primary(
                    key: const ValueKey('guest_search.show'),
                    label: n == null ? 'sa_gs_show'.tr : '${'sa_gs_show'.tr} (${_courses(n)})',
                    icon: Icons.search_rounded,
                    expand: true,
                    size: AppButtonSize.lg,
                    onPressed: _show,
                  ),
                  AppSpace.gapSm,
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.xxs,
                    children: [
                      Text('sa_gs_have'.tr, style: AppType.meta(context)),
                      AppButton.ghost(
                        key: const ValueKey('guest_search.login'),
                        label: 'sa_gs_login'.tr,
                        size: AppButtonSize.sm,
                        onPressed: () => _go('/login', widget.onLogin),
                      ),
                      Text('•', style: AppType.meta(context)),
                      AppButton.ghost(
                        key: const ValueKey('guest_search.register'),
                        label: 'sa_gs_create'.tr,
                        size: AppButtonSize.sm,
                        onPressed: () => _go('/register', widget.onRegister),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        )),
      ),
    );
  }

  String _courses(int n) => countText(n,
      ar1: 'دورة واحدة', ar2: 'دورتان', arFew: '$n دورات', arMany: '$n دورة', en1: '1 course', en: '$n courses',
      ar0: 'لا توجد دورات', en0: 'no courses');
}

/// One choice inside the sentence: a pill in its own colour (the subject's, the grade's grape, the mode's sky) with
/// a chevron; a tap opens its sheet. Disabled (no choices yet) it stays drawn, a little faded.
class _SentencePill extends StatelessWidget {
  const _SentencePill({super.key, required this.label, required this.tone, required this.onTap});

  final String label;
  final KitTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: AppJelly(
          child: Material(
            color: tone.tint,
            shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: tone.color, width: AppBorder.focus)),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.section(context).copyWith(color: tone.ink)),
                    ),
                    const SizedBox(width: AppSpace.xxs),
                    Icon(Icons.keyboard_arrow_down_rounded, size: AppIconSize.md, color: tone.ink),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A subject's glyph, from its kit subject key.
IconData _subjectIcon(String key) => switch (key) {
      'math' => Icons.calculate_rounded,
      'physics' => Icons.bolt_rounded,
      'chem' => Icons.science_rounded,
      'bio' => Icons.eco_rounded,
      'english' => Icons.translate_rounded,
      'arabic' => Icons.menu_book_rounded,
      'qudurat' => Icons.psychology_rounded,
      'code' => Icons.code_rounded,
      'quran' => Icons.auto_stories_rounded,
      'islamic' => Icons.mosque_rounded,
      _ => Icons.school_rounded,
    };

/// "وش المادة؟": a search and a grid of subject tiles in their colours; "تم" returns the pick (0 = any subject).
class _SubjectSheet extends StatefulWidget {
  const _SubjectSheet({required this.subjects, required this.selected});

  final List<LandingSubject> subjects;
  final int selected;

  @override
  State<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<_SubjectSheet> {
  late int _picked = widget.selected;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final s in widget.subjects)
        if (q.isEmpty || s.nameAr.toLowerCase().contains(q) || s.nameEn.toLowerCase().contains(q)) s,
    ];
    final kit = context.colors.kit;
    Widget tile({required int id, required String name, required KitTone tone, required IconData icon}) => _SubjectTile(
          key: ValueKey('guest_search.subject.$id'),
          name: name,
          tone: tone,
          icon: icon,
          selected: _picked == id,
          onTap: () => setState(() => _picked = id),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader('sa_gs_subject_sheet'.tr),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          textInputAction: TextInputAction.search,
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context, hint: 'sa_gs_subject_search'.tr, icon: Icons.search_rounded),
        ),
      ),
      Flexible(
        child: shown.isEmpty && q.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text('sa_gs_none'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
              )
            : GridView.extent(
                shrinkWrap: true,
                maxCrossAxisExtent: AppDashSize.sidebar / 2,
                childAspectRatio: _SubjectTile.aspect,
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                children: [
                  if (q.isEmpty) tile(id: 0, name: 'sa_gs_any_subject'.tr, tone: kit.warmTone, icon: Icons.apps_rounded),
                  for (final s in shown)
                    tile(id: s.id, name: s.name, tone: kit.subject(subjectKeyFor(s.nameAr)).tone, icon: _subjectIcon(subjectKeyFor(s.nameAr))),
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppButton.primary(
          key: const ValueKey('guest_search.subject_done'),
          label: 'sa_gs_done'.tr,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ),
    ]);
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({super.key, required this.name, required this.tone, required this.icon, required this.selected, required this.onTap});

  /// A little taller than wide: the glyph, then a name of up to two lines at large text.
  static const double aspect = 0.68;

  final String name;
  final KitTone tone;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.tile);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: AppJelly(
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: selected ? tone.color : c.kit.line, width: selected ? AppBorder.focus : AppBorder.strong),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: AppTouch.min,
                    height: AppTouch.min,
                    decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(AppRadius.glyph)),
                    child: Icon(icon, size: AppIconSize.lg, color: c.onHero),
                  ),
                  if (selected)
                    PositionedDirectional(
                      top: -AppSpace.xs,
                      start: -AppSpace.xs,
                      child: Container(
                        decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: c.cardBg, width: AppBorder.focus)),
                        child: Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero),
                      ),
                    ),
                ]),
                AppSpace.gapXs,
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "أي صف؟": the subject's grades as chips; a tap picks and closes.
class _LevelSheet extends StatelessWidget {
  const _LevelSheet({required this.levels, required this.selected});

  final List<LandingLevel> levels;
  final int selected;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('sa_gs_level_sheet'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppChip(label: 'sa_gs_any_level'.tr, selected: selected == 0, onTap: () => Navigator.of(context).pop(0)),
              for (final l in levels)
                AppChip(
                  key: ValueKey('guest_search.level.${l.id}'),
                  label: l.name,
                  selected: selected == l.id,
                  onTap: () => Navigator.of(context).pop(l.id),
                ),
            ]),
          ),
        ),
      ]);
}

/// "كيف تبي تدرس؟": any · remote · in person; a tap picks and closes.
class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('sa_gs_mode_sheet'.tr),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
          child: Column(children: [
            for (final (m, icon) in const [
              ('any', Icons.all_inclusive_rounded),
              ('online', Icons.wifi_rounded),
              ('center', Icons.place_rounded),
            ]) ...[
              AppTile(
                key: ValueKey('guest_search.mode.$m'),
                icon: icon,
                title: 'sa_gs_mode_$m'.tr,
                selected: selected == m,
                onTap: () => Navigator.of(context).pop(m),
              ),
              AppSpace.gapXs,
            ],
          ]),
        ),
      ]);
}
