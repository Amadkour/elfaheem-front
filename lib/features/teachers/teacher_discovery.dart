// lib/features/teachers/teacher_discovery.dart — the student's side of Learning Hub v2 (CONTRACT.md §1, §2 +
// Corrections v2 C2 / C3; D-1629 .. D-1634). Kill switch `teacher_discovery` (the Learn tab and its pages),
// `packages` (Join).
//
//   TeachersTab          the Learn hub's "Teachers": search + filters (subject, gender, delivery, price range, rating,
//                        available) over GET /teachers, 20 a page, the next page loaded near the end of the list
//   TeacherProfilePage   GET /teachers/{id}: bio, subjects, qualifications, packages with seats left, reviews if any
//                        (TeacherProfileView: plain values, the CourseSpace slot style — the hero block, sections,
//                        the packages beside them on wide windows)
//   PackagePage          GET /packages/{id}: Join / Join the waiting list / Pay now, and the states full /
//                        waitlisted (position) / pending payment (a 30 min hold, counted down) / offered (24 h to
//                        pay, highlighted); Leave warns that a paid seat is not refunded automatically
//                        (PackageView: plain values)
//   MyTeachersPage       GET /me/teachers: my teachers with their active packages and the next session
//
// Paying: POST /packages/{id}/enroll answers `checkout` in the STORE's shape (`{url, token, …}`, Corrections v2 C2),
// so the seat is paid through the store's path (openPointsPaymentPage: the WebView / iframe), then the package is
// read again until it leaves pending_payment (or 30 s pass).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart' show openPointsPaymentPage;
import 'package:flutter_education_app/features/rewards/coupon_field.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart' show CouponQuote, CouponTarget, couponsOff;
import 'package:flutter_education_app/features/store/store_models.dart' show StoreCheckout;
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

const int kTeachersPageSize = 20;

// ── the tab ──────────────────────────────────────────────────────────────────

class TeachersTab extends StatefulWidget {
  const TeachersTab({super.key, this.api});

  final TeachersApi? api;

  @override
  State<TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<TeachersTab> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  TeacherFilters _f = TeacherFilters.none;
  final List<TeacherProfile> _items = [];
  int _page = 0, _total = 0, _gen = 0;
  bool _loading = true, _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool next = false}) async {
    if (next && (_more || _loading || _items.length >= _total)) return;
    final gen = next ? _gen : ++_gen;
    final page = next ? _page + 1 : 1;
    setState(() {
      if (next) {
        _more = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final r = await _api.teachers(_f, page: page, size: kTeachersPageSize);
      if (!mounted || gen != _gen) return;
      setState(() {
        if (!next) _items.clear();
        _items.addAll(r.items);
        _page = page;
        _total = r.items.isEmpty && next ? _items.length : r.total;
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _more = false;
        if (next) {
          showAppNotice(teachersErrorText(e), error: true);
        } else {
          _error = teachersErrorText(e);
        }
      });
    }
  }

  void _setFilters(TeacherFilters f) {
    _f = f;
    unawaited(_load());
  }

  void _open(TeacherProfile p) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/teachers/${p.userId}'),
        builder: (_) => TeacherProfilePage(teacherId: p.userId, initial: p, api: _api),
      ));

  void _mine() => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/me/teachers'),
        builder: (_) => MyTeachersPage(api: _api),
      ));

  @override
  Widget build(BuildContext context) => SdArea(
        area: AppArea.learn,
        child: BasePage(
          width: AppWidth.wide,
          appBar: ScreenAppBar(
            title: 'sd_teachers_title'.tr,
            showBack: false,
            actions: [
              AppIconButton(
                key: const ValueKey('teachers.mine'),
                tooltip: t('معلميّ', 'My teachers'),
                icon: Icons.how_to_reg_outlined,
                onPressed: _mine,
              ),
            ],
          ),
          child: SafeArea(
            child: TeachersBrowseView(
              filters: _f,
              onFilters: _setFilters,
              items: _items,
              total: _total,
              loading: _loading,
              loadingMore: _more,
              error: _error,
              onRetry: _load,
              onNearEnd: () => _load(next: true),
              onOpen: _open,
              onMine: _mine,
            ),
          ),
        ),
      );
}

/// The list with plain values (Stu2Teachers `screen=list`): the hero "لقِ معلمك" with the search and the filters
/// button (the screen's one forward button), the subject chips riding up over it, then the teacher cards, dealt in
/// (M5), one column on a phone, two or three on wider windows.
class TeachersBrowseView extends StatelessWidget {
  const TeachersBrowseView({
    super.key,
    required this.filters,
    required this.onFilters,
    required this.items,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.onRetry,
    this.onNearEnd,
    this.onOpen,
    this.onMine,
  });

  final TeacherFilters filters;
  final ValueChanged<TeacherFilters> onFilters;
  final List<TeacherProfile> items;
  final int total;
  final bool loading, loadingMore;
  final String? error;
  final Future<void> Function()? onRetry;
  final VoidCallback? onNearEnd;
  final ValueChanged<TeacherProfile>? onOpen;
  final VoidCallback? onMine;

  static const double _sideBySide = 420;

  Future<void> _more(BuildContext context) async {
    final f = await showAppSheet<TeacherFilters>(
      context,
      (_) => AppSheetContent(
        title: 'sd_teachers_filters'.tr,
        icon: Icons.tune_rounded,
        tone: AppTone.neutral,
        children: [TeacherFiltersForm(initial: filters)],
      ),
    );
    if (f != null) onFilters(f);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extra = filters.count - (filters.subject == null ? 0 : 1);
    final hero = AppHero(
      title: 'sd_teachers_hero'.tr,
      icon: Icons.person_search_outlined,
      wipe: false, // the cards are dealt in (M5): the screen's one hero move
      // the filter button sits beside the search, never at the end of the scrolling chips (off-screen in RTL, D-1654)
      bottom: LayoutBuilder(builder: (context, box) {
        final search = AppSearchField(
          key: const ValueKey('teachers.search'),
          hint: 'sd_teachers_search'.tr,
          onChanged: (q) => onFilters(filters.copyWith(q: q)),
        );
        final button = AppButton.hot(
          key: const ValueKey('teachers.filters'),
          label: extra > 0 ? '${'sd_teachers_filters'.tr} (${appDigits('$extra')})' : 'sd_teachers_filters'.tr,
          icon: Icons.filter_alt_outlined,
          onPressed: () => _more(context),
        );
        // a narrow phone stacks the button under the search
        if (box.maxWidth < _sideBySide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            search,
            const SizedBox(height: AppSpace.xs),
            Align(alignment: AlignmentDirectional.centerStart, child: button),
          ]);
        }
        return Row(children: [Expanded(child: search), const SizedBox(width: AppSpace.xs), button]);
      }),
    );
    final chips = AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          AppChip(
            key: const ValueKey('teachers.subject.all'),
            label: 'sd_teachers_all_subjects'.tr,
            selected: filters.subject == null,
            onTap: () => onFilters(filters.copyWith(subject: null)),
          ),
          for (final s in kTeacherSubjects) ...[
            const SizedBox(width: AppSpace.xs),
            AppChip(
              key: ValueKey('teachers.subject.$s'),
              label: teacherSubjectLabel(s),
              icon: teacherSubjectIcon(s),
              selected: filters.subject == s,
              onTap: () => onFilters(filters.copyWith(subject: filters.subject == s ? null : s)),
            ),
          ],
        ]),
      ),
    );
    final Widget body;
    if (loading && items.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null && items.isEmpty) {
      body = AppCard(child: AppErrorState(message: error, onRetry: onRetry));
    } else if (items.isEmpty) {
      final narrowed = filters.count > 0 || filters.q.isNotEmpty;
      body = AppCard(
        child: AppEmpty(
          icon: Icons.person_search_outlined,
          title: t('لا معلمين بهذه الشروط', 'No teachers match'),
          message: t('خفّف التصفية أو جرّب مادة أخرى.', 'Loosen the filters or try another subject.'),
          actionLabel: narrowed ? t('امسح التصفية', 'Clear the filters') : t('معلميّ', 'My teachers'),
          onAction: narrowed ? () => onFilters(TeacherFilters.none) : onMine,
        ),
      );
    } else {
      body = LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= Breakpoints.desktop ? 3 : (box.maxWidth >= Breakpoints.mobile ? 2 : 1);
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += cols) {
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: i + j < items.length
                        ? AppDeal(
                            index: i + j,
                            group: 'teachers.list',
                            child: TeacherListCard(
                                teacher: items[i + j], onTap: onOpen == null ? null : () => onOpen!(items[i + j])),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ]),
            ),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      });
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) onNearEnd?.call();
        return false;
      },
      child: AppRefresh(
        onRefresh: onRetry ?? () async {},
        child: SdHeroList(hero: hero, width: AppWidth.wide, children: [
          chips,
          const SizedBox(height: AppSpace.md),
          if (!loading && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(appDigits(teachersText(total)), style: AppType.meta(context).copyWith(color: c.textMedium)),
            ),
          body,
          if (loadingMore) const AppListSkeleton(items: 1, padding: EdgeInsets.zero),
        ]),
      ),
    );
  }
}

/// The filter sheet's form: gender, delivery, price range, lowest rating, available now. Pops the new filters.
class TeacherFiltersForm extends StatefulWidget {
  const TeacherFiltersForm({super.key, required this.initial});

  final TeacherFilters initial;

  @override
  State<TeacherFiltersForm> createState() => _TeacherFiltersFormState();
}

class _TeacherFiltersFormState extends State<TeacherFiltersForm> {
  late TeacherFilters _f = widget.initial;
  String? _error;

  void _apply() {
    if (_f.priceMin != null && _f.priceMax != null && _f.priceMin! > _f.priceMax!) {
      setState(() => _error = t('أقل سعر أكبر من أعلى سعر', 'The lowest price is above the highest'));
      return;
    }
    Navigator.of(context).pop(_f);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TeachersChoiceRow(
        label: t('المعلم', 'Teacher'),
        keyPrefix: 'teachers.f.gender',
        values: kTeacherGenders,
        selected: (v) => _f.gender == v,
        labelOf: teacherGenderLabel,
        onTap: (v) => setState(() => _f = _f.copyWith(gender: _f.gender == v ? null : v)),
      ),
      const SizedBox(height: AppSpace.md),
      TeachersChoiceRow(
        label: t('طريقة الحضور', 'Delivery'),
        keyPrefix: 'teachers.f.delivery',
        values: kTeacherDeliveryModes,
        selected: (v) => _f.delivery == v,
        labelOf: packageDeliveryLabel,
        onTap: (v) => setState(() => _f = _f.copyWith(delivery: _f.delivery == v ? null : v)),
      ),
      const SizedBox(height: AppSpace.md),
      // one price per row: each field is wide enough to type a real price (D-1655)
      AppNumberField(
        key: const ValueKey('teachers.f.pmin'),
        initialValue: _f.priceMin,
        label: t('أقل سعر', 'Lowest price'),
        min: 0,
        step: 50,
        onChanged: (v) => _f = _f.copyWith(priceMin: v?.toDouble()),
      ),
      const SizedBox(height: AppSpace.sm),
      AppNumberField(
        key: const ValueKey('teachers.f.pmax'),
        initialValue: _f.priceMax,
        label: t('أعلى سعر', 'Highest price'),
        min: 0,
        step: 50,
        onChanged: (v) => _f = _f.copyWith(priceMax: v?.toDouble()),
      ),
      const SizedBox(height: AppSpace.md),
      TeachersChoiceRow(
        label: t('أقل تقييم', 'Lowest rating'),
        keyPrefix: 'teachers.f.rating',
        values: const ['3', '4', '4.5'],
        selected: (v) => _f.minRating == double.parse(v),
        labelOf: (v) => '★ $v+',
        onTap: (v) => setState(() => _f = _f.copyWith(minRating: _f.minRating == double.parse(v) ? null : double.parse(v))),
      ),
      const SizedBox(height: AppSpace.sm),
      AppSwitchTile(
        key: const ValueKey('teachers.f.available'),
        title: t('متاح الآن', 'Available now'),
        subtitle: t('له باقة بمقعد فارغ أو قائمة انتظار مفتوحة', 'Has a package with a free seat or an open waiting list'),
        icon: Icons.event_available_rounded,
        value: _f.available,
        onChanged: (v) => setState(() => _f = _f.copyWith(available: v)),
      ),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppButtonRow(
        primary: AppButton.primary(key: const ValueKey('teachers.f.apply'), label: t('اعرض النتائج', 'Show results'), onPressed: _apply),
        secondary: [
          AppButton.ghost(
            key: const ValueKey('teachers.f.clear'),
            label: t('امسح', 'Clear'),
            onPressed: () => Navigator.of(context).pop(TeacherFilters(subject: _f.subject, q: _f.q)),
          ),
        ],
      ),
      const SizedBox(height: AppSpace.md),
    ]);
  }
}

/// The kit subject of a teacher's subject (the same colour on every screen).
String teacherKitSubject(String s) => switch (s) {
      'quran' || 'tajweed' => 'quran',
      'fiqh' => 'islamic',
      'nahw' => 'arabic',
      _ => 'other',
    };

/// A teacher in the list (Stu2Teachers): a card tinted in the first subject's colour, the initial on the solid
/// colour, the name, "معلم" / "معلمة", the subjects, how the classes are held, the rating and "شوف الملف".
class TeacherListCard extends StatelessWidget {
  const TeacherListCard({super.key, required this.teacher, this.onTap});

  final TeacherProfile teacher;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = teacher;
    final sub = c.kit.subject(teacherKitSubject(p.subjects.isEmpty ? '' : p.subjects.first));
    final tone = sub.tone;
    final initial = teacherInitialName(p.name).trim();
    final tags = <String>[
      for (final d in p.delivery) d == 'offline' ? 'sd_in_person'.tr : 'sd_remote'.tr,
      if (p.sessionTypes.isNotEmpty)
        p.sessionTypes.length > 1 ? 'sd_group_and_individual'.tr : teacherSessionTypeLabel(p.sessionTypes.first),
    ];
    return AppCard(
      key: ValueKey('teachers.card.${p.userId}'),
      variant: AppCardVariant.tint,
      tone: tone,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
            child: p.avatarUrl != null && p.avatarUrl!.isNotEmpty
                ? AppAvatar(name: initial, url: p.avatarUrl, size: AppTouch.primary)
                : Container(
                    width: AppTouch.primary,
                    height: AppTouch.primary,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(AppRadius.tile)),
                    child: Text(initial.isEmpty ? '؟' : initial.characters.first,
                        style: AppType.section(context).copyWith(color: sub.fg)),
                  ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              UserText(block: false, p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
              if (p.gender != null)
                Text(teacherGenderLabel(p.gender), style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
              if (p.subjects.isNotEmpty)
                Text(teachersJoin(p.subjects.map(teacherSubjectLabel)),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final (i, s) in tags.indexed) AppStatusBadge(label: s, tone: i == 0 ? AppTone.info : AppTone.neutral, dense: true),
          ]),
        ],
        const SizedBox(height: AppSpace.sm),
        TeacherRatingLine(rating: p.rating, count: p.reviewsCount),
        if (p.nextFree != null) ...[
          const SizedBox(height: AppSpace.xxs),
          // a bare start date (no schedule yet) has no time of day: midnight UTC would read as 2:00 AM (D-1656)
          AppInfoRow(
              Icons.event_available_outlined,
              p.nextFreeIsDay
                  ? '${t('تبدأ', 'Starts')}: ${packageDayLabel(p.nextFree!)}'
                  : '${t('أقرب موعد', 'Next opening')}: ${AppTime.dateTime(p.nextFree!)}'),
        ],
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Flexible(
            child: Text('sd_teachers_open'.tr,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: tone.ink),
        ]),
      ]),
    );
  }
}

// ── a teacher's page ─────────────────────────────────────────────────────────

class TeacherProfilePage extends StatefulWidget {
  const TeacherProfilePage({super.key, required this.teacherId, this.initial, this.api});

  final int teacherId;
  final TeacherProfile? initial;
  final TeachersApi? api;

  @override
  State<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends State<TeacherProfilePage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  late TeacherProfile? _p = widget.initial;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.teacher(widget.teacherId);
      if (!mounted) return;
      setState(() {
        _p = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_p == null) {
          _error = teachersErrorText(e);
        } else {
          showAppNotice(teachersErrorText(e), error: true);
        }
      });
    }
  }

  Future<void> _openPackage(TeacherPackage pk) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: '/packages/${pk.id}'),
      builder: (_) => PackagePage(packageId: pk.id, initial: pk, api: _api),
    ));
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return SdArea(area: AppArea.learn, child: BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: p?.name.isNotEmpty == true ? p!.name : t('المعلم', 'Teacher')),
      child: SafeArea(
        child: p == null
            ? (_loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load))
            : TeacherProfileView(teacher: p, packagesLoading: _loading && p.packages.isEmpty, onPackage: _openPackage, onRefresh: _load),
      ),
    ));
  }
}

class TeacherProfileView extends StatelessWidget {
  const TeacherProfileView({super.key, required this.teacher, this.onPackage, this.onRefresh, this.packagesLoading = false});

  final TeacherProfile teacher;
  final ValueChanged<TeacherPackage>? onPackage;
  final Future<void> Function()? onRefresh;
  final bool packagesLoading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = teacher;
    final hero = AppBlock(
      tone: AppBlockTone.sky,
      hero: true,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            // a paper ring: the avatar's own sky circle would vanish on the sky hero
            DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxs),
                child: AppAvatar(name: teacherInitialName(p.name), url: p.avatarUrl, size: AppTouch.primary + AppSpace.md),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                UserText(block: false, p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  [teacherGenderLabel(p.gender), if (p.yearsExperience > 0) yearsText(p.yearsExperience)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: b.muted),
                ),
                const SizedBox(height: AppSpace.xxs),
                TeacherRatingLine(rating: p.rating, count: p.reviewsCount, color: b.muted),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          TeacherSubjectBadges(subjects: p.subjects),
        ]);
      }),
    );
    final about = AppSection(
      title: teacherG(p.gender, 'عن المعلم', 'عن المعلمة', 'About'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.bio.trim().isEmpty)
          Text(teacherG(p.gender, 'لم يكتب المعلم نبذة بعد.', 'لم تكتب المعلمة نبذة بعد.', 'The teacher has not written an introduction yet.'),
              style: AppType.body(context).copyWith(color: c.textMedium))
        else
          UserText(p.bio.trim(), style: AppType.body(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        if (p.languages.isNotEmpty) AppInfoRow(Icons.translate_rounded, teachersJoin(p.languages.map(teacherLanguageLabel))),
        if (p.sessionTypes.isNotEmpty || p.delivery.isNotEmpty)
          AppInfoRow(Icons.groups_rounded, [...p.sessionTypes.map(teacherSessionTypeLabel), ...p.delivery.map(packageDeliveryLabel)].join(' · ')),
      ]),
    );
    final quals = p.qualifications.trim().isEmpty
        ? null
        : AppSection(
            title: t('المؤهلات', 'Qualifications'),
            child: UserText(p.qualifications.trim(), style: AppType.body(context).copyWith(color: c.textDark)),
          );
    final packages = AppSection(
      title: t('الباقات', 'Packages'),
      subtitle: t('اختر باقة لترى مواعيدها وتنضم.', 'Pick a package to see its times and join.'),
      child: packagesLoading
          ? const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
          : p.packages.isEmpty
              ? AppEmpty(
                  icon: Icons.event_busy_rounded,
                  title: t('لا باقات مفتوحة الآن', 'No packages open now'),
                  message: t('عد لاحقاً: يفتح المعلم باقات جديدة.', 'Come back later: the teacher opens new packages.'),
                  actionLabel: onRefresh == null ? null : t('حدّث', 'Refresh'),
                  onAction: onRefresh == null ? null : () => onRefresh!(),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final pk in p.packages) ...[
                    PackageCard(package: pk, onTap: onPackage == null ? null : () => onPackage!(pk)),
                    const SizedBox(height: AppSpace.sm),
                  ],
                ]),
    );
    final reviews = p.reviews.isEmpty
        ? null
        : AppSection(
            title: t('آراء الطلاب', 'Reviews'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in p.reviews.take(10)) ...[
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(child: UserText(block: false, r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark))),
                      Icon(Icons.star_rounded, size: AppIconSize.sm, color: c.accent2),
                      Text(r.rating.toStringAsFixed(1), style: AppType.meta(context).copyWith(color: c.textMedium)),
                    ]),
                    if ((r.comment ?? '').isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xxs),
                      UserText(r.comment!, style: AppType.body(context).copyWith(color: c.textMedium)),
                    ],
                  ]),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
            ]),
          );
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= Breakpoints.desktop;
      final Widget content = wide
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              hero,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [about, ?quals, ?reviews])),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 2, child: packages),
              ]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [hero, packages, about, ?quals, ?reviews]);
      final list = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [content, const SizedBox(height: AppSpace.lg)]);
      return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
    });
  }
}

// ── a package's page ─────────────────────────────────────────────────────────

class PackagePage extends StatefulWidget {
  const PackagePage({super.key, required this.packageId, this.initial, this.api});

  final int packageId;
  final TeacherPackage? initial;
  final TeachersApi? api;

  @override
  State<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends State<PackagePage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  late TeacherPackage? _p = widget.initial;
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<TeacherPackage?> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.package(widget.packageId);
      if (!mounted) return r;
      setState(() {
        _p = r;
        _loading = false;
      });
      return r;
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_p == null) {
            _error = teachersErrorText(e);
          } else {
            showAppNotice(teachersErrorText(e), error: true);
          }
        });
      }
      return null;
    }
  }

  Future<void> _pay(PackageEnrollResult r) async {
    final c = StoreCheckout.fromJson({...?r.checkout, 'url': r.checkoutUrl});
    if (c == null || !c.canOpen) return;
    await openPointsPaymentPage(context, c.url);
    // the webhook settles the seat: read the package again until it leaves pending_payment (30 s at most)
    for (var i = 0; i < 6 && mounted; i++) {
      final p = await _load();
      if (p == null || p.myEnrollment?.status != 'pending_payment') break;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (!mounted) return;
    if (_p?.myEnrollment?.status == 'active') {
      showAppNotice(t('دُفع مقعدك. أهلاً بك في الباقة', 'Your seat is paid. Welcome to the package'));
    } else if (_p?.myEnrollment?.status == 'pending_payment') {
      showAppNotice(t('لم يصل الدفع بعد. مقعدك محجوز حتى انتهاء المهلة.', 'The payment has not arrived yet. Your seat stays held until the time runs out.'));
    }
  }

  Future<void> _join() async {
    final p = _p;
    if (p == null || packagesOff()) return;
    // Games v3: a paid package asks once, with the coupon box (one coupon off the price before fees)
    String? coupon;
    if (!p.isFree && !couponsOff()) {
      final go = await showAppSheet<PackageJoinChoice>(context, (_) => PackageJoinSheet(package: p));
      if (go == null || !mounted) return;
      coupon = go.couponCode;
    }
    setState(() => _busy = true);
    try {
      final r = await _api.enroll(p.id, couponCode: coupon);
      if (!mounted) return;
      if (r.needsPayment) {
        await _pay(r);
      } else {
        final pos = r.position == null ? '' : t(': رقم ${r.position}', ': number ${r.position}');
        showAppNotice(r.waitlisted
            // a free package has nothing to pay: no payment words at all (D-1657)
            ? (p.isFree
                ? t('انضممت لقائمة الانتظار$pos. سنخبرك عندما يتوفر مقعد.', 'You joined the waiting list$pos. We will tell you when a seat frees.')
                : t('انضممت لقائمة الانتظار$pos. لن تدفع إلا إذا عُرض عليك مقعد.', 'You joined the waiting list$pos. You only pay if a seat is offered.'))
            : t('انضممت إلى الباقة', 'You joined the package'));
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      showAppNotice(teachersErrorText(e), error: true);
      final code = teachersErrorCode(e);
      if (code == 'package_full' || code == 'already_enrolled' || code == 'package_closed') unawaited(_load());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final p = _p;
    if (p == null) return;
    final paid = p.myEnrollment?.status == 'active' && !p.isFree;
    final ok = await appConfirm(context,
        message: paid
            ? t('مغادرة "${p.title}"؟ لا يُرد المبلغ تلقائياً: للاسترداد تواصل مع الدعم.',
                'Leave "${p.title}"? There is no automatic refund: contact support for a refund.')
            : t('مغادرة "${p.title}"؟ يذهب مقعدك لأول المنتظرين.', 'Leave "${p.title}"? Your seat goes to the first one waiting.'),
        danger: true,
        confirmLabel: t('غادر', 'Leave'));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.leave(p.id);
      showAppNotice(t('غادرت الباقة', 'You left the package'));
      await _load();
    } catch (e) {
      showAppNotice(teachersErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return SdArea(area: AppArea.learn, child: BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('الباقة', 'Package')),
      child: SafeArea(
        child: p == null
            ? (_loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load))
            : PackageView(
                package: p,
                busy: _busy,
                joinOff: packagesOff(),
                onJoin: _join,
                onLeave: _leave,
                onRefresh: () async => _load(),
              ),
      ),
    ));
  }
}

/// What the join sheet decided: go, with this coupon (null = none).
class PackageJoinChoice {
  const PackageJoinChoice(this.couponCode);
  final String? couponCode;
}

/// The paid package's join sheet (Games v3): the price, the coupon box, then Join.
class PackageJoinSheet extends StatefulWidget {
  const PackageJoinSheet({super.key, required this.package, this.coupon});

  final TeacherPackage package;

  /// The coupon box (tests pass a plain one); null = the real CouponField for this package.
  final Widget? coupon;

  @override
  State<PackageJoinSheet> createState() => _PackageJoinSheetState();
}

class _PackageJoinSheetState extends State<PackageJoinSheet> {
  CouponQuote? _q;

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    final q = _q;
    return AppSheetContent(
      title: t('الانضمام إلى الباقة', 'Join the package'),
      icon: Icons.groups_rounded,
      children: [
        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        AppSpace.gapXs,
        Text(
          q == null
              ? packagePriceLabel(p.finalPrice, p.currency)
              : t('${packagePriceLabel(q.priceAfter, p.currency)} بعد خصم القسيمة', '${packagePriceLabel(q.priceAfter, p.currency)} after the coupon'),
          key: const ValueKey('package.join.price'),
          style: AppType.section(context),
        ),
        if (p.isFull) ...[
          AppSpace.gapXs,
          Text(t('الباقة ممتلئة: تُحفظ القسيمة وتُستخدم حين يُعرض عليك مقعد.', 'The package is full: the coupon is kept and used when a seat is offered.'),
              style: AppType.meta(context)),
        ],
        AppSpace.gapMd,
        widget.coupon ??
            CouponField(
              key: const ValueKey('package.join.coupon'),
              target: CouponTarget.package,
              targetId: p.id,
              onChanged: (v) => setState(() => _q = v),
            ),
        AppSpace.gapLg,
        AppButton.primary(
          key: const ValueKey('package.join.go'),
          label: p.isFull ? t('انضم لقائمة الانتظار', 'Join the waiting list') : t('انضم وادفع', 'Join and pay'),
          icon: p.isFull ? Icons.hourglass_top_rounded : Icons.lock_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(PackageJoinChoice(q?.coupon.code)),
        ),
      ],
    );
  }
}

class PackageView extends StatefulWidget {
  const PackageView({super.key, required this.package, this.onJoin, this.onLeave, this.onRefresh, this.busy = false, this.joinOff = false});

  final TeacherPackage package;
  final VoidCallback? onJoin, onLeave;
  final Future<void> Function()? onRefresh;
  final bool busy, joinOff;

  @override
  State<PackageView> createState() => _PackageViewState();
}

class _PackageViewState extends State<PackageView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PackageView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// A countdown runs only while a hold or an offer is open.
  void _sync() {
    final e = widget.package.myEnrollment;
    final counting = e?.expiresAt != null && (e!.status == 'pending_payment' || e.status == 'offered');
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.package;
    final state = packageJoinState(p);
    final left = packageHoldLeft(p.myEnrollment?.expiresAt);
    final hero = AppBlock(
      tone: state == PackageJoinState.offered ? AppBlockTone.gold : AppBlockTone.peach,
      hero: true,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          UserText(block: false, p.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
          const SizedBox(height: AppSpace.xxs),
          Text(
            [
              teacherSubjectLabel(p.subject),
              packageLevelLabel(p.level),
              if ((p.teacher?.name ?? '').isNotEmpty) p.teacher!.name,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: b.muted),
          ),
          const SizedBox(height: AppSpace.sm),
          PackagePriceText(price: p.price, finalPrice: p.finalPrice, currency: p.currency, discountPercent: p.discountPercent),
        ]);
      }),
    );
    final facts = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppInfoRow(Icons.event_repeat_rounded, '${sessionsText(p.sessionsCount)} × ${minutesText(p.sessionMinutes)}'),
        // the days and times before joining (D-1648), and the first REAL session day (D-1649)
        KeyedSubtree(
          key: const ValueKey('package.schedule'),
          child: AppInfoRow(Icons.schedule_rounded,
              packageScheduleText(p.schedule, p.sessionsCount) ?? t('المواعيد يتفق عليها المعلم مع الطلاب', 'The teacher agrees the times with the students')),
        ),
        if (packageFirstDay(p.schedule, p.startDate) case final first?) AppInfoRow(Icons.event_rounded, packageStartsText(first)),
        AppInfoRow(Icons.place_rounded,
            p.location == null || p.delivery == 'online' ? packageDeliveryLabel(p.delivery) : '${packageDeliveryLabel(p.delivery)} · ${p.location}'),
        AppInfoRow(Icons.event_seat_rounded, '${seatsLeftText(p.seatsLeft)} · ${t('من ${p.maxStudents}', 'of ${p.maxStudents}')}'),
        if (p.waitlistCount > 0) AppInfoRow(Icons.hourglass_top_rounded, waitingText(p.waitlistCount)),
      ]),
    );
    final Widget? stateBanner = switch (state) {
      PackageJoinState.pendingPayment => AppBanner(
          key: const ValueKey('package.state.pending'),
          icon: Icons.timer_outlined,
          color: c.warning,
          text: left == null
              ? t('مقعدك محجوز حتى تدفع.', 'Your seat is held until you pay.')
              : t('مقعدك محجوز لمدة $left. ادفع قبل انتهائها وإلا عاد المقعد متاحاً.', 'Your seat is held for $left. Pay before it ends, or the seat opens again.'),
        ),
      PackageJoinState.offered => AppBanner(
          key: const ValueKey('package.state.offered'),
          icon: Icons.celebration_rounded,
          color: c.accent2,
          text: left == null
              ? t('خرج أحد الطلاب فصار المقعد لك. ادفع لتثبيته.', 'A student left, so the seat is yours. Pay to keep it.')
              : t('صار المقعد لك: أمامك $left للدفع، ثم يُعرض على التالي.', 'The seat is yours: you have $left to pay, then it goes to the next student.'),
        ),
      PackageJoinState.waitlisted => AppBanner(
          key: const ValueKey('package.state.waitlisted'),
          icon: Icons.hourglass_top_rounded,
          text: '${packageJoinLabel(state, position: p.myEnrollment?.position)}. ${p.isFree ? t('سنخبرك عندما يتوفر مقعد.', 'We will tell you when a seat frees.') : t('سنخبرك عندما يتوفر مقعد، ولن تدفع قبل ذلك.', 'We will tell you when a seat frees; you pay nothing before that.')}',
        ),
      PackageJoinState.full => AppBanner(
          key: const ValueKey('package.state.full'),
          icon: Icons.event_busy_rounded,
          color: c.danger,
          text: t('اكتملت المقاعد ولا قائمة انتظار لهذه الباقة.', 'The seats are full and this package has no waiting list.'),
        ),
      PackageJoinState.active => AppBanner(
          key: const ValueKey('package.state.active'),
          icon: Icons.check_circle_rounded,
          color: c.success,
          text: p.seriesId != null
              ? t('أنت مشترك. تجد الجلسات في جدولك.', 'You are in. The sessions are in your schedule.')
              : t('أنت مشترك. يتفق معك المعلم على مواعيد الجلسات.', 'You are in. The teacher agrees the session times with you.'),
        ),
      PackageJoinState.closed || PackageJoinState.notOpen => AppBanner(
          icon: Icons.block_rounded,
          color: c.textMedium,
          text: packageJoinLabel(state),
        ),
      _ => null,
    };
    final canAct = packageJoinActionable(state) && !widget.joinOff && state != PackageJoinState.waitlisted;
    final mine = packageJoinMine(state);
    final list = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      hero,
      if (stateBanner != null) ...[const SizedBox(height: AppSpace.md), stateBanner],
      const SizedBox(height: AppSpace.md),
      facts,
      if (p.goal.trim().isNotEmpty)
        AppSection(title: t('الهدف', 'Goal'), child: UserText(p.goal.trim(), style: AppType.body(context).copyWith(color: c.textDark))),
      if (p.description.trim().isNotEmpty)
        AppSection(title: t('عن الباقة', 'About the package'), child: UserText(p.description.trim(), style: AppType.body(context).copyWith(color: c.textDark))),
      const SizedBox(height: AppSpace.lg),
      if (widget.joinOff && !mine)
        AppBanner(icon: Icons.lock_outline_rounded, color: c.warning, text: t('الانضمام للباقات متوقف الآن من إدارة المنصة.', 'Joining packages is switched off by the platform right now.'))
      else
        AppButtonRow(
          primary: AppButton.primary(
            key: ValueKey('package.join.${state.name}'),
            label: state == PackageJoinState.pendingPayment && left != null ? '${packageJoinLabel(state)} · $left' : packageJoinLabel(state, position: p.myEnrollment?.position),
            icon: switch (state) {
              PackageJoinState.pay || PackageJoinState.pendingPayment || PackageJoinState.offered => Icons.payments_rounded,
              PackageJoinState.joinWaitlist || PackageJoinState.waitlisted => Icons.hourglass_top_rounded,
              PackageJoinState.active => Icons.check_rounded,
              _ => Icons.add_rounded,
            },
            busy: widget.busy,
            onPressed: canAct && !widget.busy ? widget.onJoin : null,
          ),
          secondary: [
            if (mine)
              AppButton.ghost(
                key: const ValueKey('package.leave'),
                label: state == PackageJoinState.waitlisted ? t('اخرج من الانتظار', 'Leave the waiting list') : t('غادر الباقة', 'Leave the package'),
                onPressed: widget.busy ? null : widget.onLeave,
              ),
          ],
        ),
      const SizedBox(height: AppSpace.lg),
    ]);
    return widget.onRefresh == null ? list : AppRefresh(onRefresh: widget.onRefresh!, child: list);
  }
}

// ── my teachers ──────────────────────────────────────────────────────────────

class MyTeachersPage extends StatefulWidget {
  const MyTeachersPage({super.key, this.api});

  final TeachersApi? api;

  @override
  State<MyTeachersPage> createState() => _MyTeachersPageState();
}

class _MyTeachersPageState extends State<MyTeachersPage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  List<MyTeacher>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.myTeachers();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = teachersErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => SdArea(area: AppArea.learn, child: BasePage(
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: t('معلميّ', 'My teachers')),
        child: SdHeroColumn(title: 'sd_h_my_teachers'.tr, subtitle: 'sd_h_my_teachers_d'.tr, icon: Icons.how_to_reg_outlined, child: SafeArea(
          child: _items == null
              ? (_error == null ? const AppListSkeleton(items: 3) : AppErrorState(message: _error, onRetry: _load))
              : MyTeachersView(
                  items: _items!,
                  onRefresh: _load,
                  onBrowse: () => Navigator.of(context).maybePop(),
                  onTeacher: (m) => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => TeacherProfilePage(teacherId: m.teacher.userId, initial: m.teacher, api: _api),
                  )),
                  onPackage: (pk) async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PackagePage(packageId: pk.id, initial: pk, api: _api)));
                    if (mounted) unawaited(_load());
                  },
                ),
        )),
      ));
}

class MyTeachersView extends StatelessWidget {
  const MyTeachersView({super.key, required this.items, this.onTeacher, this.onPackage, this.onBrowse, this.onRefresh});

  final List<MyTeacher> items;
  final ValueChanged<MyTeacher>? onTeacher;
  final ValueChanged<TeacherPackage>? onPackage;
  final VoidCallback? onBrowse;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = <Widget>[
      if (items.isEmpty)
        AppEmpty(
          icon: Icons.school_outlined,
          title: t('لا معلمين بعد', 'No teachers yet'),
          message: t('انضم لباقة معلم لتجده هنا مع موعد جلستك القادمة.', 'Join a teacher\'s package to find them here with your next session.'),
          actionLabel: t('تصفح المعلمين', 'Browse teachers'),
          onAction: onBrowse,
        )
      else
        for (final m in items) ...[
          AppCard(
            key: ValueKey('myteacher.${m.teacher.userId}'),
            onTap: onTeacher == null ? null : () => onTeacher!(m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                AppAvatar(name: teacherInitialName(m.teacher.name), url: m.teacher.avatarUrl, size: AppTouch.min),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    UserText(block: false, m.teacher.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                    Text(
                      m.nextSession == null ? t('لا جلسة قادمة محددة', 'No next session set') : '${t('الجلسة القادمة', 'Next session')}: ${AppTime.dateTime(m.nextSession!)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(color: m.nextSession == null ? c.textMedium : c.primary),
                    ),
                  ]),
                ),
              ]),
              for (final pk in m.activePackages) ...[
                const SizedBox(height: AppSpace.xs),
                AppActionCard(
                  key: ValueKey('myteacher.package.${pk.id}'),
                  icon: teacherSubjectIcon(pk.subject),
                  title: pk.title,
                  subtitle: packageScheduleText(pk.schedule, pk.sessionsCount) ?? '${teacherSubjectLabel(pk.subject)} · ${sessionsText(pk.sessionsCount)}',
                  onTap: onPackage == null ? null : () => onPackage!(pk),
                ),
              ],
            ]),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      const SizedBox(height: AppSpace.lg),
    ];
    final list = ListView(padding: const EdgeInsets.all(AppSpace.md), children: children);
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}
