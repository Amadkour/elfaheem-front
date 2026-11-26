// lib/design/gallery/kit_gallery_sections.dart
//
// The sections of the kit gallery (KIT_SPEC §7.1). Demo people and times come from docs/redesign/CAST.md. The
// labels here are the kit's own role names (developer facing), so most stay as code words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_area.dart';
import '../app_contrast.dart';
import '../app_kit.dart';
import '../app_motion_kit.dart';

typedef KitGallerySection = ({String title, Widget Function(BuildContext context) build});

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

List<KitGallerySection> kitGallerySections() => [
      (title: 'kit_gallery_colours'.tr, build: (c) => const _Colours()),
      (title: 'kit_gallery_type'.tr, build: (c) => const _Type()),
      (title: 'kit_gallery_buttons'.tr, build: (c) => const _Buttons()),
      (title: 'kit_gallery_cards'.tr, build: (c) => const _Cards()),
      (title: 'kit_gallery_hero'.tr, build: (c) => const _Hero()),
      (title: 'kit_gallery_chips'.tr, build: (c) => const _Chips()),
      (title: 'kit_gallery_states'.tr, build: (c) => const _States()),
      (title: 'kit_gallery_progress'.tr, build: (c) => const _Progress()),
      (title: 'kit_gallery_live'.tr, build: (c) => const _Live()),
      (title: 'kit_gallery_sheets'.tr, build: (c) => const _Sheets()),
      (title: 'kit_gallery_motion'.tr, build: (c) => const _Motion()),
    ];

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppType.section(context)),
          const SizedBox(height: AppSpace.sm),
          ...children,
        ]),
      );
}

Widget _wrap(List<Widget> children) =>
    Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: children);

// ── Colours ───────────────────────────────────────────────────────────────────────────────────────────────────────

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.tone);

  final String name;
  final KitTone tone;

  @override
  Widget build(BuildContext context) {
    final r = contrastRatio(tone.ink, tone.tint);
    return Container(
      width: _swatchW,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(children: [
        Container(
          width: AppIconSize.lg,
          height: AppIconSize.lg,
          decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text('$name  ${r.toStringAsFixed(2)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: tone.ink)),
        ),
      ]),
    );
  }
}

const double _swatchW = 168;

class _Colours extends StatelessWidget {
  const _Colours();

  @override
  Widget build(BuildContext context) {
    final k = context.colors.kit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(title: 'brand', children: [
        _wrap([
          _Swatch('primary', k.primaryTone),
          _Swatch('partner', k.partnerTone),
          _Swatch('warm', k.warmTone),
          _Swatch('hot', k.hotTone),
          _Swatch('live', k.live),
          _Swatch('ok', k.ok),
          _Swatch('warn', k.warn),
          _Swatch('error', k.error),
        ]),
      ]),
      _Section(title: 'accents', children: [
        _wrap([for (final a in AppAccent.values) _Swatch(a.name, k.accent(a))]),
      ]),
      _Section(title: 'subjects', children: [
        _wrap([for (final s in kSubjectKeys) _Swatch(s, k.subject(s).tone)]),
      ]),
      _Section(title: 'areas · roles', children: [
        for (final a in AppArea.values) _AreaStrip(name: a.name, set: k.area(a)),
        for (final r in AppRoleAccent.values) _AreaStrip(name: r.key, set: k.role(r)),
      ]),
    ]);
  }
}

class _AreaStrip extends StatelessWidget {
  const _AreaStrip({required this.name, required this.set});

  final String name;
  final KitSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
      child: AppHeroSurface(
        set: set,
        shapes: false,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Expanded(
              child: Text(name, style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
            ),
            AppAreaScope(
              area: AppArea.home,
              budget: false,
              child: _SetButton(set: set, label: _t('ابدأ', 'Start')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A button drawn in [set]'s stops (the strip shows every area's button, whatever the scope).
class _SetButton extends StatelessWidget {
  const _SetButton({required this.set, required this.label});

  final KitSet set;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(gradient: set.button, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Text(label, style: AppType.label(context).copyWith(color: set.btnFg, fontWeight: FontWeight.w600)),
      );
}

// ── Type ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class _Type extends StatelessWidget {
  const _Type();

  @override
  Widget build(BuildContext context) {
    final rows = <(String, TextStyle)>[
      ('display', AppType.display(context)),
      ('headline', AppType.headline(context)),
      ('pageTitle', AppType.pageTitle(context)),
      ('section', AppType.section(context)),
      ('kicker', AppType.kicker(context).copyWith(color: context.colors.kit.warmInkOn(context))),
      ('tileTitle', AppType.tileTitle(context)),
      ('body', AppType.body(context)),
      ('label', AppType.label(context)),
      ('meta', AppType.meta(context)),
      ('overline', AppType.overline(context)),
      ('statFigure', AppType.statFigure(context, wide: true)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (name, style) in rows)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppType.overline(context)),
            Text(name == 'statFigure' ? '1,240' : _t('حصة الرياضيات شغّالة الحين', 'Your maths class is on now'),
                style: style),
          ]),
        ),
    ]);
  }
}

extension on KitColors {
  /// The gold kicker reads on a hero; on the page the warm ink stands in.
  Color warmInkOn(BuildContext context) => warmTone.ink;
}

// ── Buttons ───────────────────────────────────────────────────────────────────────────────────────────────────────

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    void tap() {}
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final size in AppButtonSize.values)
        _Section(title: size.name, children: [
          _wrap([
            AppButton.primary(label: _t('احجز مقعدك', 'Book your seat'), onPressed: tap, size: size),
            AppButton.hot(
                label: _t('ادخل الحصة', 'Join the class'), icon: Icons.play_arrow_rounded, onPressed: tap, size: size),
            AppButton.secondary(label: _t('التفاصيل', 'Details'), onPressed: tap, size: size),
            AppButton.tonal(label: _t('حفظ', 'Save'), onPressed: tap, size: size),
            AppButton.ghost(label: _t('كل دوراتي', 'All my courses'), onPressed: tap, size: size),
            AppButton.danger(label: _t('إلغاء الحجز', 'Cancel booking'), onPressed: tap, size: size),
            AppButton.primary(label: _t('جارٍ', 'Busy'), onPressed: tap, size: size, busy: true),
            AppButton.primary(label: _t('معطّل', 'Disabled'), onPressed: null, size: size),
          ]),
        ]),
      _Section(title: 'icon buttons', children: [
        _wrap([
          AppIconButton(icon: Icons.notifications_none_rounded, tooltip: 'notifications', onPressed: tap, badge: 5),
          AppIconButton(icon: Icons.chat_bubble_outline_rounded, tooltip: 'messages', onPressed: tap, badge: 2),
          AppHeroSurface(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            shapes: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: AppIconButton(icon: Icons.search_rounded, tooltip: 'search', onPressed: tap, onHero: true),
            ),
          ),
        ]),
      ]),
      Text('kit_gallery_rule'.tr, style: AppType.meta(context)),
    ]);
  }
}

// ── Cards and tiles ───────────────────────────────────────────────────────────────────────────────────────────────

class _Cards extends StatelessWidget {
  const _Cards();

  @override
  Widget build(BuildContext context) {
    void tap() {}
    final title = _t('كمّل من وين وقفت', 'Pick up where you left off');
    final more = AppButton.ghost(label: _t('كل دوراتي', 'All my courses'), onPressed: tap, size: AppButtonSize.sm);
    Widget body() => Text(_t('الرياضيات: الدوال الأسية', 'Maths: exponential functions'), style: AppType.body(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final v in AppCardVariant.values)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm),
          child: AppCard(variant: v, title: '$title (${v.name})', action: more, onTap: tap, child: body()),
        ),
      _Section(title: 'tiles', children: [
        AppTile(
          icon: Icons.functions_rounded,
          tone: context.colors.kit.subject('math').tone,
          title: _t('الرياضيات', 'Maths'),
          subtitle: _t('الدوال الأسية', 'Exponential functions'),
          trailing: const AppProgressRing(value: .38),
          onTap: tap,
        ),
        const SizedBox(height: AppSpace.xs),
        AppTile(
          icon: Icons.science_outlined,
          tone: context.colors.kit.subject('physics').tone,
          title: _t('الفيزياء', 'Physics'),
          subtitle: _t('قوانين نيوتن', "Newton's laws"),
          selected: true,
          onTap: tap,
        ),
        const SizedBox(height: AppSpace.xs),
        AppTile(icon: Icons.translate_rounded, title: _t('الإنجليزي من الصفر', 'English from zero'), locked: true),
      ]),
      _Section(title: 'stat tiles', children: [
        _wrap([
          SizedBox(
              width: _statW,
              child: AppStatTile(icon: Icons.local_fire_department_outlined, label: _t('أيام ورا بعض', 'Day streak'), value: 5, delta: '+1')),
          SizedBox(
              width: _statW,
              child: AppStatTile(icon: Icons.star_outline_rounded, label: _t('نقاطك', 'Your points'), value: '1,240')),
        ]),
      ]),
      _Section(title: 'rules', children: [
        AppRules(items: [
          (icon: Icons.timer_outlined, text: _t('٢٠ دقيقة', '20 minutes')),
          (icon: Icons.quiz_outlined, text: _t('١٠ أسئلة', '10 questions')),
          (icon: Icons.replay_rounded, text: _t('محاولتين', 'Two attempts')),
        ]),
      ]),
    ]);
  }
}

const double _statW = 200;

// ── Hero ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    void tap() {}
    final word = _t('شغّالة', 'on');
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.cardFor(MediaQuery.sizeOf(context).width)),
      child: AppHeroOverlap(
        hero: AppHero(
          kicker: _t('صباح الخير يا فيصل', 'Good morning, Faisal'),
          title: _t('حصة الرياضيات $word الحين', 'Your maths class is $word now'),
          squiggle: word,
          subtitle: _t('مع أ. ماجد الشهري، ٧:٣٠ إلى ٨:٢٠ م', 'With Mr Majed Alshehri, 7:30 to 8:20 pm'),
          stats: [
            AppHeroStat(icon: Icons.menu_book_outlined, value: '4', label: _t('دورات', 'courses')),
            AppHeroStat(icon: Icons.trending_up_rounded, value: '62%', label: _t('تقدّمك', 'progress')),
            AppHeroStat(icon: Icons.local_fire_department_outlined, value: '5', label: _t('أيام', 'days'), delta: '+1'),
            AppHeroStat(icon: Icons.star_outline_rounded, value: '1,240', label: _t('نقاط', 'points')),
          ],
          actions: [AppButton.hot(label: _t('ادخل الحصة', 'Join the class'), onPressed: tap)],
        ),
        body: AppCard(
          title: _t('كمّل من وين وقفت', 'Pick up where you left off'),
          child: Text(_t('الرياضيات: الدوال الأسية', 'Maths: exponential functions'), style: AppType.body(context)),
        ),
      ),
    );
  }
}

// ── Chips and tabs ────────────────────────────────────────────────────────────────────────────────────────────────

class _Chips extends StatefulWidget {
  const _Chips();

  @override
  State<_Chips> createState() => _ChipsState();
}

class _ChipsState extends State<_Chips> {
  int _two = 0, _four = 1, _many = 2, _chip = 0;

  @override
  Widget build(BuildContext context) {
    final labels = [_t('الكل', 'All'), _t('مباشر', 'Live'), _t('مسجّل', 'Recorded'), _t('اختبارات', 'Exams')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Section(title: 'tabs', children: [
        AppTabs(
            items: [AppTabItem(_t('القادمة', 'Upcoming')), AppTabItem(_t('السابقة', 'Past'))],
            index: _two,
            expand: true,
            onChanged: (i) => setState(() => _two = i)),
        const SizedBox(height: AppSpace.sm),
        AppTabs(items: [for (final l in labels) AppTabItem(l)], index: _four, onChanged: (i) => setState(() => _four = i)),
        const SizedBox(height: AppSpace.sm),
        AppTabs(
            items: [for (var i = 0; i < 9; i++) AppTabItem('${labels[i % 4]} ${i + 1}')],
            index: _many,
            onChanged: (i) => setState(() => _many = i)),
      ]),
      _Section(title: 'chips', children: [
        _wrap([
          for (var i = 0; i < labels.length; i++)
            AppChip(label: labels[i], selected: _chip == i, onTap: () => setState(() => _chip = i), count: i == 1 ? 3 : null),
          AppChip(label: _t('فيصل', 'Faisal'), leading: const CircleAvatar(child: Text('ف')), selected: true),
        ]),
      ]),
      _Section(title: 'tags', children: [
        _wrap([
          for (final t in AppTone.values) AppStatusBadge(label: t.name, tone: t),
          for (final a in AppAccent.values) AppStatusBadge(label: a.name, accent: a),
          AppStatusBadge(label: _t('رياضيات', 'Maths'), subject: 'math'),
        ]),
      ]),
    ]);
  }
}

// ── States ────────────────────────────────────────────────────────────────────────────────────────────────────────

class _States extends StatelessWidget {
  const _States();

  @override
  Widget build(BuildContext context) {
    void tap() {}
    Widget box(Widget child) =>
        Padding(padding: const EdgeInsetsDirectional.only(bottom: AppSpace.md), child: AppCard(child: child));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      box(AppEmpty(
          icon: Icons.event_available_outlined,
          title: _t('ما عندك حصص اليوم', 'No classes today'),
          message: _t('احجز حصتك الجاية من جدولك', 'Book your next class from your schedule'),
          actionLabel: _t('افتح جدولي', 'Open my schedule'),
          onAction: tap)),
      box(AppErrorState(onRetry: tap)),
      box(AppNeedsConnection(onRetry: tap)),
      box(const SizedBox(height: _loadingH, child: AppLoadingState(items: 3))),
      box(AppSuccess(
          title: _t('تم حجز مقعدك', 'Your seat is booked'),
          message: _t('الأحد والثلاثاء، ٧:٣٠ إلى ٨:٢٠ م', 'Sunday and Tuesday, 7:30 to 8:20 pm'),
          actionLabel: _t('افتح جدولي', 'Open my schedule'),
          onAction: tap)),
    ]);
  }
}

const double _loadingH = 260;

// ── Progress ──────────────────────────────────────────────────────────────────────────────────────────────────────

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Section(title: 'rings', children: [
          _wrap(const [
            AppProgressRing(value: .38, size: _ring28, showPercent: false),
            AppProgressRing(value: .64),
            AppProgressRing(value: .81, size: AppDashSize.ring),
            AppProgressRing(value: 1),
          ]),
        ]),
        _Section(title: 'countdown', children: [
          AppCountdown(until: DateTime.now().toUtc().add(const Duration(days: 1, hours: 3, minutes: 12))),
        ]),
        _Section(title: 'odometer', children: [
          AppOdometer('1,240', style: AppType.figureLarge(context), memoryKey: 'kit_gallery_points'),
        ]),
      ]);
}

const double _ring28 = 28;

// ── Live and badges ───────────────────────────────────────────────────────────────────────────────────────────────

class _Live extends StatelessWidget {
  const _Live();

  @override
  Widget build(BuildContext context) {
    void tap() {}
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppLiveBanner(
        tag: _t('مباشر، من ١٢ دقيقة', 'Live, 12 minutes in'),
        title: _t('الرياضيات: الدوال الأسية', 'Maths: exponential functions'),
        subtitle: _t('مع أ. ماجد الشهري، ٥٠ دقيقة', 'With Mr Majed Alshehri, 50 minutes'),
        hostInitial: _t('م', 'M'),
        actionLabel: _t('ادخل الحصة', 'Join the class'),
        onAction: tap,
      ),
      const SizedBox(height: AppSpace.md),
      _wrap([
        const AppLiveTag(),
        AppHeroSurface(
          shapes: false,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          child: const Padding(padding: EdgeInsets.all(AppSpace.xs), child: AppLiveTag(onDark: true)),
        ),
        const AppCountBadge(count: 1),
        const AppCountBadge(count: 12),
        const AppCountBadge(count: 120),
        const AppCountBadge(count: 3, tone: AppTone.gold),
        AppCountBadge(count: 5, child: Icon(Icons.notifications_none_rounded, color: context.colors.textDark)),
      ]),
    ]);
  }
}

// ── Sheets ────────────────────────────────────────────────────────────────────────────────────────────────────────

class _Sheets extends StatelessWidget {
  const _Sheets();

  @override
  Widget build(BuildContext context) {
    Widget content(BuildContext c) => AppSheetContent(
          title: _t('احجز مقعدك', 'Book your seat'),
          children: [
            Text(_t('المجموعة أ: الأحد والثلاثاء، ٧:٣٠ إلى ٨:٢٠ م', 'Group A: Sunday and Tuesday, 7:30 to 8:20 pm'),
                style: AppType.body(c)),
          ],
        );
    return _wrap([
      for (final m in AppSheetMode.values)
        AppButton.secondary(label: m.name, onPressed: () => showAppSheet<void>(context, content, mode: m)),
    ]);
  }
}

// ── Motion ────────────────────────────────────────────────────────────────────────────────────────────────────────

class _Motion extends StatefulWidget {
  const _Motion();

  @override
  State<_Motion> createState() => _MotionState();
}

class _MotionState extends State<_Motion> {
  final Map<String, int> _runs = {};
  final _feedback = AppFeedbackController();
  final _burstAnchor = GlobalKey();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Widget _demo(String name, Widget Function() child) {
    final run = _runs[name] ?? 0;
    return AppCard(
      variant: AppCardVariant.flat,
      title: name,
      action: AppButton.ghost(
          label: 'kit_gallery_replay'.tr, size: AppButtonSize.sm, onPressed: () => setState(() => _runs[name] = run + 1)),
      // a fresh budget and a fresh played-once key on every replay
      child: AppMotionBudget(
        key: ValueKey('$name-$run'),
        child: Center(child: KeyedSubtree(key: ValueKey(run), child: child())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    Widget card(String text) => Container(
          width: _demoW,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: set.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Text(text, style: AppType.label(context).copyWith(color: set.ink)),
        );
    String g(String name) => '$name-${_runs[name] ?? 0}';
    final demos = <Widget>[
      _demo('M1 flip', () => Column(children: [for (var i = 0; i < 3; i++) AppFlipIn(index: i, group: g('M1'), child: card('#$i'))])),
      _demo('M2 ink', () => _wrap([
            AppInkRing(key: ValueKey(g('M2')), value: .64, color: set.a, track: set.tint),
            const AppInkCheck(size: _check),
          ])),
      _demo('M3 pop', () => AppPop(group: g('M3'), child: card('pop'))),
      _demo('M4 slap', () => AppSlap(group: g('M4'), child: const AppStatusBadge(label: 'NEW', tone: AppTone.gold))),
      _demo('M5 deal', () => Column(children: [for (var i = 0; i < 3; i++) AppDeal(index: i, group: g('M5'), child: card('#$i'))])),
      _demo('M6 wipe', () => AppWipe(group: g('M6'), child: card(_t('مسح من البداية', 'Wipe from the start')))),
      _demo('M7 squiggle', () => AppSquiggle(child: Text(_t('شغّالة', 'now'), style: AppType.headline(context)))),
      _demo('M8 breathe', () => AppBreathe(child: card(_t('مباشر', 'Live')))),
      _demo('M9 jelly', () => AppJelly(child: AppButton.primary(label: _t('اضغط', 'Press'), onPressed: () {}))),
      _demo('M10 odometer', () => AppOdometer('${1240 + (_runs['M10 odometer'] ?? 0) * 17}', style: AppType.figureLarge(context))),
      _demo('M11 burst', () => AppButton.hot(
          key: _burstAnchor,
          label: _t('اطلق', 'Fire'),
          onPressed: () => AppBurst.fire(context, BurstMoment.levelUp, anchor: _burstAnchor))),
      _demo('M12 wobble', () => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++) AppWobble(index: i, group: g('M12'), child: AppIconBox(icon: Icons.star_rounded)),
          ])),
      _demo('M13 pill', () => const _PillDemo()),
      _demo('M15 feedback', () => Column(mainAxisSize: MainAxisSize.min, children: [
            AppFeedback(controller: _feedback, borderRadius: BorderRadius.circular(AppRadius.tile), child: card('A / B')),
            const SizedBox(height: AppSpace.xs),
            _wrap([
              AppButton.secondary(label: 'shake', size: AppButtonSize.sm, onPressed: _feedback.shake),
              AppButton.secondary(label: 'nod', size: AppButtonSize.sm, onPressed: _feedback.nod),
            ]),
          ])),
      _demo('M16 drift', () => SizedBox(
            height: _driftH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              child: AppHeroSurface(child: Center(child: Text('M16', style: AppType.section(context).copyWith(color: c.onHero)))),
            ),
          )),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in demos) Padding(padding: const EdgeInsetsDirectional.only(bottom: AppSpace.sm), child: d),
      Text(_t('M14: افتح ورقة من قسم الأوراق على الجوال.', 'M14: open a sheet from the Sheets section on a phone.'),
          style: AppType.meta(context)),
    ]);
  }
}

const double _demoW = 220;
const double _check = 72;
const double _driftH = 160;

class _PillDemo extends StatefulWidget {
  const _PillDemo();

  @override
  State<_PillDemo> createState() => _PillDemoState();
}

class _PillDemoState extends State<_PillDemo> {
  int _i = 0;

  @override
  Widget build(BuildContext context) => AppTabs(
        items: [AppTabItem(_t('الرئيسية', 'Home')), AppTabItem(_t('دوراتي', 'Courses')), AppTabItem(_t('جدولي', 'Schedule'))],
        index: _i,
        expand: true,
        onChanged: (i) => setState(() => _i = i),
      );
}
