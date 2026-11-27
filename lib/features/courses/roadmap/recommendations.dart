// lib/features/courses/roadmap/recommendations.dart
//
// "Recommended for you" on the student's profile (D-120): the backend's hybrid list (services/learning/recs.py),
// each course with its reason ("Because you completed …", "From the same instructor, …", "Students like you took
// this", "Popular in …"). Personal student accounts only; the kill switch `roadmap.recommendations` hides it.
//
//   ProfileRecommendations   the profile block: 3 courses + "See all" · "My interests" · "Not interested" per row
//                            (with Undo); recommendations turned off → one slim row to turn them back on
//   RecommendationsPage      the whole list (≤ 30), redesign Stu1Discover?screen=recs: RecommendationCard on the
//                            one course card (CourseCardSliver: rows on a phone, a grid of tiles from 600 px)
//   showInterestsSheet       pick fields, grouped with their sub-fields (empty = inferred from the courses taken) ·
//                            Show recommendations switch · "Show N hidden courses again"
//
// What is shown and opened is reported in batches (RecEventLog) for the super admin's numbers per reason.
//
// Presentational parts take plain values (test/ui/roadmap_layout_test.dart).
library;

import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;

/// The profile block; draws nothing for an account / state that has no recommendations.
class ProfileRecommendations extends StatefulWidget {
  const ProfileRecommendations({super.key, required this.role, this.api = const RoadmapApi(), this.padding = EdgeInsets.zero});

  final String? role;
  final RoadmapApi api;
  final EdgeInsetsGeometry padding;

  @override
  State<ProfileRecommendations> createState() => _ProfileRecommendationsState();
}

class _ProfileRecommendationsState extends State<ProfileRecommendations> {
  RecPage? _page;
  bool _gone = false;
  bool _failed = false;

  bool get _allowed => widget.role == 'student' && !roadmapOrgAccount(widget.role) && !roadmapOff(kRoadmapRecsKey);

  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final p = await widget.api.recommendations(limit: 3);
      if (mounted) setState(() => _page = p);
      RecEventLog.instance.shown(p.items.map((x) => x.course.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => roadmapHiddenError(e) ? _gone = true : _failed = true);
    }
  }

  Future<void> _dismiss(RecItem item) async {
    final before = _page;
    if (before == null) return;
    setState(() => _page = RecPage(items: [for (final x in before.items) if (x.course.id != item.course.id) x], total: before.total - 1));
    try {
      await widget.api.dismiss(item.course.id);
      showAppNotice(
        t('لن نقترح هذه الدورة مجدداً', 'We won’t suggest this course again'),
        actionLabel: t('تراجع', 'Undo'),
        onAction: () => _undo(item),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _page = before);
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  Future<void> _undo(RecItem item) async {
    try {
      await widget.api.restore(item.course.id);
      await _load();
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  void _open(RmCourse c) {
    RecEventLog.instance.opened(c.id);
    AppNavigator.openCourse(c.id);
  }

  Future<void> _interests() async {
    final changed = await showInterestsSheet(context, api: widget.api);
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed || _gone) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: RecommendationsSectionView(
        page: _page,
        failed: _failed,
        onRetry: _load,
        onOpen: _open,
        onDismiss: _dismiss,
        onInterests: _interests,
        onSeeAll: () => Navigator.of(context).push(
          MaterialPageRoute(settings: const RouteSettings(name: '/recommendations'), builder: (_) => RecommendationsPage(api: widget.api)),
        ),
      ),
    );
  }
}

/// The profile block from plain values: [page] null = loading.
class RecommendationsSectionView extends StatelessWidget {
  const RecommendationsSectionView({
    super.key,
    required this.page,
    required this.onOpen,
    required this.onDismiss,
    required this.onInterests,
    this.onSeeAll,
    this.failed = false,
    this.onRetry,
  });

  final RecPage? page;
  final bool failed;
  final ValueChanged<RmCourse> onOpen;
  final ValueChanged<RecItem> onDismiss;
  final VoidCallback onInterests;
  final VoidCallback? onSeeAll, onRetry;

  @override
  Widget build(BuildContext context) {
    final p = page;
    if (p != null && p.hidden) {
      return _SlimRow(
        icon: Icons.auto_awesome_outlined,
        text: t('التوصيات متوقفة', 'Recommendations are off'),
        action: t('تشغيل', 'Turn on'),
        onTap: onInterests,
      );
    }
    final Widget body;
    if (failed) {
      body = _SlimRow(icon: Icons.cloud_off_rounded, text: t('تعذّر تحميل التوصيات', 'Could not load recommendations'), action: t('إعادة المحاولة', 'Retry'), onTap: onRetry);
    } else if (p == null) {
      body = const AppListSkeleton(items: 3, withAvatar: true);
    } else if (p.items.isEmpty) {
      body = _SlimRow(
        icon: Icons.explore_outlined,
        text: t('سنقترح دورات حين تبدأ دورة أو تختار اهتماماتك.', 'We’ll suggest courses once you start one or pick your interests.'),
        action: t('اهتماماتي', 'My interests'),
        onTap: onInterests,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final item in p.items.take(3)) RecommendationRow(item: item, onOpen: () => onOpen(item.course), onDismiss: () => onDismiss(item))],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(t('مقترح لك', 'Recommended for you'), style: AppType.section(context))),
            ),
            AppButton.ghost(
              onPressed: onInterests,
              size: AppButtonSize.sm,
              icon: Icons.tune_rounded,
              label: t('اهتماماتي', 'My interests'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        body,
        if (p != null && p.total > 3 && onSeeAll != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              onPressed: onSeeAll,
              size: AppButtonSize.sm,
              label: t('عرض الكل (${p.total})', 'See all (${p.total})'),
            ),
          ),
      ],
    );
  }
}

class _SlimRow extends StatelessWidget {
  const _SlimRow({required this.icon, required this.text, required this.action, this.onTap});

  final IconData icon;
  final String text, action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.sm - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppType.body(context)),
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 0)),
                  child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One recommended course: thumbnail · title · the reason (one line) · "Not interested".
class RecommendationRow extends StatelessWidget {
  const RecommendationRow({super.key, required this.item, required this.onOpen, this.onDismiss});

  final RecItem item;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;

  static IconData _icon(String reason) => switch (reason) {
    'because_completed' || 'because_taking' || 'similar_topics' => Icons.timeline_rounded,
    'matches_interest' => Icons.favorite_border_rounded,
    'similar_students' => Icons.groups_2_outlined,
    'same_teacher' => Icons.person_outline_rounded,
    'explore_field' => Icons.explore_outlined,
    _ => Icons.trending_up_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final co = item.course;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: co.imageUrl == null
                        ? ColoredBox(color: c.inputBg, child: Icon(Icons.menu_book_rounded, color: c.textLight))
                        : AppNetworkImage(url: co.imageUrl!, width: 52, height: 52, fit: BoxFit.cover, borderRadius: BorderRadius.zero),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(co.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                      const SizedBox(height: AppSpace.xxs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(_icon(item.reason), size: AppIconSize.xs, color: appInk(context, c.primary)),
                          ),
                          const SizedBox(width: AppSpace.xxs),
                          Expanded(
                            child: Text(item.reasonText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: t('غير مهتم', 'Not interested'),
                    icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every recommendation (the server keeps at most 30).
class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key, this.api = const RoadmapApi()});

  final RoadmapApi api;

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  RecPage? _page;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.api.recommendations(limit: 30);
      if (mounted) setState(() => _page = p);
      RecEventLog.instance.shown(p.items.map((x) => x.course.id));
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _dismiss(RecItem item) async {
    try {
      await widget.api.dismiss(item.course.id);
      final p = _page;
      if (p != null && mounted) {
        setState(() => _page = RecPage(items: [for (final x in p.items) if (x.course.id != item.course.id) x], total: p.total - 1));
      }
      showAppNotice(
        t('لن نقترح هذه الدورة مجدداً', 'We won’t suggest this course again'),
        actionLabel: t('تراجع', 'Undo'),
        onAction: () async {
          try {
            await widget.api.restore(item.course.id);
            await _load();
          } catch (e) {
            showAppNotice(ApiException.from(e).message, error: true);
          }
        },
      );
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    return BasePage(
      key: const ValueKey(kRoadmapRecsKey),
      appBar: ScreenAppBar(title: t('مقترح لك', 'Recommended for you')),
      child: SaHeroPage(area: AppArea.learn, kicker: 'sa_recs_kicker'.tr, title: 'sa_recs_title'.tr, squiggle: 'sa_recs_squiggle'.tr, child: AppRefresh(
        onRefresh: _load,
        // redesign (Stu1Discover?screen=recs, S-A2): the one course card, its reason as a tag, "مو مهتم" on each
        child: LayoutBuilder(builder: (context, box) {
          final gutter = box.maxWidth >= Breakpoints.mobile ? AppSpace.lg : AppSpace.md;
          final side = math.max(gutter, (box.maxWidth - AppWidth.wide.max) / 2);
          final width = math.max(0.0, box.maxWidth - 2 * side);
          final Widget body;
          if (_error != null) {
            body = SliverToBoxAdapter(
              child: AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load),
            );
          } else if (p == null) {
            body = const SliverFillRemaining(hasScrollBody: true, child: CourseListSkeleton(padding: EdgeInsets.zero));
          } else if (p.items.isEmpty) {
            body = SliverToBoxAdapter(child: AppEmpty(icon: Icons.explore_outlined, title: t('لا توصيات الآن', 'No recommendations right now')));
          } else {
            body = CourseCardSliver(
              width: width,
              count: p.items.length,
              itemBuilder: (context, i, shape) {
                final item = p.items[i];
                return RecommendationCard(
                  key: ValueKey('recs.${item.course.id}'),
                  item: item,
                  shape: shape,
                  onOpen: () {
                    RecEventLog.instance.opened(item.course.id);
                    AppNavigator.openCourse(item.course.id);
                  },
                  onDismiss: () => _dismiss(item),
                );
              },
            );
          }
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), sliver: body),
            ],
          );
        }),
      )),
    );
  }
}

/// One recommended course on the one course card: the subject cover, the title, the teacher, the reason (a tag on
/// a row, a chip on a tile's cover), "مو مهتم" and the price.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.item, required this.shape, required this.onOpen, this.onDismiss});

  final RecItem item;
  final CourseCardShape shape;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final co = item.course;
    final row = shape == CourseCardShape.row;
    final reason = AppStatusBadge(label: item.reasonText, accent: AppAccent.grape, icon: Icons.auto_awesome_rounded);
    // a Wrap: "Not interested" and the price share the line, and the price drops under it on a narrow card
    final actions = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        if (onDismiss != null)
          AppButton.secondary(
            key: ValueKey('recs.dismiss.${co.id}'),
            label: 'sa_recs_not_interested'.tr,
            icon: Icons.close_rounded,
            size: AppButtonSize.sm,
            onPressed: onDismiss,
          ),
        CoursePriceFooter(price: coursePriceLabel(co.currency, co.isFree ? 0 : co.finalPrice), free: co.isFree || co.finalPrice == 0),
      ],
    );
    return CourseListCard(
      shape: shape,
      title: co.name,
      imageUrl: co.imageUrl ?? '',
      subject: co.field?.name,
      meta: [if ((co.teacherName ?? '').isNotEmpty) co.teacherName!],
      chip: row ? null : CourseCoverChip(label: item.reasonText, icon: Icons.auto_awesome_rounded),
      footer: row
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              reason,
              const SizedBox(height: AppSpace.xs),
              actions,
            ])
          : actions,
      onTap: onOpen,
    );
  }
}

/// The interests sheet; true when something was saved.
Future<bool?> showInterestsSheet(BuildContext context, {RoadmapApi api = const RoadmapApi()}) =>
    showAppSheet<bool>(context, (_) => _InterestsSheet(api: api));

class _InterestsSheet extends StatefulWidget {
  const _InterestsSheet({required this.api});

  final RoadmapApi api;

  @override
  State<_InterestsSheet> createState() => _InterestsSheetState();
}

class _InterestsSheetState extends State<_InterestsSheet> {
  LearningPrefs? _prefs;
  List<RmField> _fields = const [];
  Set<int> _picked = {};
  bool _show = true;
  bool _clearHidden = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prefs = await widget.api.prefs();
      // an older server sends no `choices`: the platform's top fields then
      final roots = prefs.choices.isNotEmpty ? const <RmField>[] : await widget.api.categories();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _show = !prefs.hide;
        _picked = {for (final f in prefs.interests) f.id};
        _fields = interestChoices(roots, prefs);
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null || _saving) return;
    setState(() => _saving = true);
    final inferred = {for (final f in prefs.inferred) f.id};
    // unchanged from what the courses suggest → stay "inferred" (follows new courses by itself)
    final reset = !prefs.chosen && _picked.length == inferred.length && _picked.containsAll(inferred);
    try {
      await widget.api.savePrefs(
        hide: !_show,
        interestIds: reset ? null : _picked.toList(),
        reset: reset && prefs.chosen,
        clearDismissed: _clearHidden,
      );
      if (!mounted) return;
      showAppNotice(t('تم الحفظ', 'Saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(t('اهتماماتي', 'My interests')),
        Flexible(
          child: p != null
              ? InterestsForm(
                  fields: _fields,
                  picked: _picked,
                  show: _show,
                  inferred: !p.chosen,
                  hidden: _clearHidden ? 0 : p.dismissed,
                  onToggle: (id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id)),
                  onShow: (v) => setState(() => _show = v),
                  onShowHidden: () => setState(() => _clearHidden = true),
                )
              : _error != null
              ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
              : const Padding(padding: EdgeInsets.all(16), child: AppListSkeleton(items: 3)),
        ),
        if (p != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AppButton.primary(label: t('احفظ اهتماماتي', 'Save my interests'), expand: true, busy: _saving, onPressed: _save),
          ),
      ],
    );
  }
}

/// The fields a student may pick: the server's `choices` (every field, sub-fields with their parent), else the
/// platform's top categories; then the ones their courses or earlier picks add.
List<RmField> interestChoices(List<RmField> roots, LearningPrefs prefs) {
  final seen = <int>{};
  return [
    for (final f in [...prefs.choices, ...roots, ...prefs.inferred, ...prefs.interests])
      if (seen.add(f.id)) f,
  ];
}

/// The sheet's body from plain values.
class InterestsForm extends StatelessWidget {
  const InterestsForm({
    super.key,
    required this.fields,
    required this.picked,
    required this.show,
    required this.onToggle,
    required this.onShow,
    this.inferred = false,
    this.hidden = 0,
    this.onShowHidden,
  });

  final List<RmField> fields;
  final Set<int> picked;
  final bool show, inferred;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onShow;

  /// Courses the student marked "Not interested"; > 0 offers to show them again.
  final int hidden;
  final VoidCallback? onShowHidden;

  Widget _chip(BuildContext context, RmField f) {
    // redesign (Stu1Discover?sheet=interests): the kit chip, a tick on the chosen ones
    return AppChip(
      label: f.name,
      icon: picked.contains(f.id) ? Icons.check_rounded : null,
      selected: picked.contains(f.id),
      onTap: () => onToggle(f.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        AppSwitchTile(
          title: t('أظهر التوصيات', 'Show recommendations'),
          subtitle: t('دورات مقترحة في ملفك وبطاقة مسارك في الرئيسية', 'Suggested courses on your profile and the journey card on your home'),
          value: show,
          onChanged: onShow,
        ),
        const SizedBox(height: 12),
        Text(t('المجالات التي تهمك', 'Fields you care about'), style: AppType.section(context)),
        const SizedBox(height: 2),
        Text(
          inferred
              ? t('اخترناها من دوراتك. غيّرها كما تحب.', 'We picked these from your courses. Change them as you like.')
              : t('اختر اللي يناسبك، أو خلّها ونختار من دوراتك.', 'Pick what suits you, or none and we’ll go by your courses.'),
          style: AppType.meta(context),
        ),
        const SizedBox(height: 12),
        if (fields.isEmpty)
          Text(t('لا مجالات بعد', 'No fields yet'), style: AppType.body(context))
        else ...[
          // the fields without sub-fields share one wrapped row; a field with sub-fields gets its own block
          if (interestGroups(fields).any((g) => g.$2.isEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final (top, subs) in interestGroups(fields)) if (subs.isEmpty) _chip(context, top)],
              ),
            ),
          for (final (top, subs) in interestGroups(fields))
            if (subs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chip(context, top),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final s in subs) _chip(context, s)]),
                    ),
                  ],
                ),
              ),
        ],
        if (hidden > 0 && onShowHidden != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onShowHidden,
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(t('أظهر الدورات المخفية مجدداً ($hidden)', 'Show hidden courses again ($hidden)')),
            ),
          ),
      ],
    );
  }
}
