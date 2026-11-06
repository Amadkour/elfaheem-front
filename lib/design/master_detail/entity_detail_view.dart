// lib/design/master_detail/entity_detail_view.dart — the body of a detail panel / page (D-290).
//
// Loads the summary (the cached one at once, else the row's own name + image over a skeleton, then the server's;
// an error with Retry), then draws, in this order: the header (picture, name, links to the related entities, the
// quick actions), the badges worded per code, the stat tiles, the kind's blocks (a course's trend and withdrawal
// reasons, a category's top courses, a learner's own enrollment) and every section the server listed, in its order:
// a paged sub-list with search, the contract's filter and sort, whose rows are links (student → course → category →
// teacher → …); a student's timeline per course; a course's content block.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';

import '../app_kit.dart';
import 'entity_chip.dart';
import 'entity_learner.dart';
import 'entity_panel_controller.dart';
import 'entity_specs.dart';
import 'entity_viewer_actions.dart';

/// A quick action of the panel (Manage, View as …), shown under the header.
class EntityPanelAction {
  const EntityPanelAction({required this.icon, required this.label, required this.onPressed, this.key, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Key? key;

  /// The one main action of the panel (Continue learning): drawn as the primary button, at full width.
  final bool primary;
}

/// The quick actions for [ref] once its summary is known ([summary] null while it loads).
typedef EntityActionsBuilder = List<EntityPanelAction> Function(EntityRef ref, EntitySummary? summary);

/// The text of a failed entity load: out of scope reads "not found", a role without entity views "not available".
String entityErrorText(Object? e) {
  if (e is ApiException) {
    if (e.code == 'not_found' || e.statusCode == 404) return 'md_not_found'.tr;
    if (e.code == 'entity_forbidden' || e.statusCode == 403) return 'md_forbidden'.tr;
  }
  return appErrorMessage(e);
}

class EntityDetailView extends StatefulWidget {
  const EntityDetailView({
    super.key,
    required this.entity,
    this.controller,
    this.actions,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
  });

  final EntityRef entity;

  /// The panel's controller: the trail's context (a course opened from a student …) and [EntityPanelController.reload].
  final EntityPanelController? controller;
  final EntityActionsBuilder? actions;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;

  @override
  State<EntityDetailView> createState() => _EntityDetailViewState();
}

class _EntityDetailViewState extends State<EntityDetailView> {
  EntitySummary? _summary;
  Object? _error;
  bool _loading = false;
  int _revision = 0;

  EntityRef get ref => widget.entity;

  @override
  void initState() {
    super.initState();
    _revision = widget.controller?.revision ?? 0;
    _load();
  }

  @override
  void didUpdateWidget(covariant EntityDetailView old) {
    super.didUpdateWidget(old);
    final rev = widget.controller?.revision ?? 0;
    if (old.entity != widget.entity) {
      _summary = null;
      _error = null;
      _revision = rev;
      _load();
    } else if (rev != _revision) {
      _revision = rev;
      EntitiesApi.instance.invalidate(ref);
      _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    final want = ref;
    final hit = force ? null : EntitiesApi.instance.cached(want);
    if (hit != null) {
      setState(() {
        _summary = hit;
        _error = null;
        _loading = false;
      });
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      // a parent's course opened from one child's row: that child's enrollment, whichever other child is enrolled too
      final s = await EntitiesApi.instance.summary(want, force: force, studentId: widget.controller?.contextStudentId);
      if (!mounted || want != ref) return;
      setState(() {
        _summary = s;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || want != ref) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  int? _viewerId(BuildContext context) {
    try {
      return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final ctl = widget.controller;
    final shown = s?.ref.withLabel(label: ref.label, labelEn: ref.labelEn, imageUrl: ref.imageUrl) ?? ref;
    final headerRef = s == null ? ref : s.ref;
    final children = <Widget>[
      EntityHeader(
        entity: s == null ? shown : headerRef,
        summary: s,
        actions: widget.actions != null ? widget.actions!(ref, s) : entityViewerActions(context, ref, s, controller: ctl),
      ),
    ];
    if (s == null) {
      if (_error != null && !_loading) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.md),
          child: AppErrorState(message: entityErrorText(_error), onRetry: () => _load(force: true), compact: true),
        ));
      } else {
        children.add(const _SummarySkeleton());
      }
    } else {
      if (s.badges.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final b in s.badges)
              AppStatusBadge(label: mdBadgeText(b), tone: mdBadgeTone(b.level), icon: mdBadgeIcon(b.code)),
          ]),
        ));
      }
      final stats = statSpecsOf(s);
      if (stats.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: EntityStatGrid(stats)));
      }
      children.addAll(_blocks(context, s));
      final focusCourse = ctl?.focusCourseId;
      final contextStudent = ctl?.contextStudentId;
      String? nameOf(int? id, EntityKind kind) {
        if (ctl == null || id == null) return null;
        final hit = ctl.trail.where((r) => r.kind == kind && r.id == id);
        return hit.isEmpty ? null : hit.last.name;
      }

      for (final section in s.sections) {
        final spec = sectionSpecOf(s.kind, section);
        if (spec == null) continue;
        final Widget body = switch (spec.shape) {
          EntitySectionShape.block => _ContentBlock(summary: s),
          EntitySectionShape.timeline => s.kind == EntityKind.student
              ? StudentTimelineSection(studentId: s.id, focusCourseId: focusCourse)
              : _learnerTimeline(context, s, contextStudent),
          EntitySectionShape.list => EntitySubList(
              key: ValueKey('md.${s.kind.name}.${s.id}.$section'),
              entity: s.ref,
              spec: spec,
              initialSearch: switch ((s.kind, section)) {
                (EntityKind.student, 'courses') => nameOf(focusCourse, EntityKind.course),
                (EntityKind.course, 'students') => nameOf(contextStudent, EntityKind.student),
                _ => null,
              },
              highlightId: s.kind == EntityKind.student ? focusCourse : contextStudent,
              // a parent names the child; a learner's own course draws its rows without links (nothing to open)
              fixedFilter: s.learnerId != null && s.mine != null ? {'student_id': '${s.learnerId}'} : const {},
              linkRows: s.mine == null,
            ),
        };
        children.add(EntitySectionCard(spec: spec, child: body));
      }
    }
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: widget.padding,
      child: KeyedSubtree(
        key: ValueKey('md.view.${ref.toToken()}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _learnerTimeline(BuildContext context, EntitySummary s, int? contextStudent) {
    final sid = s.learnerId ?? contextStudent ?? _viewerId(context);
    if (sid == null) return const SizedBox.shrink();
    return EntityTimelineList(studentId: sid, courseId: s.id);
  }

  List<Widget> _blocks(BuildContext context, EntitySummary s) {
    final out = <Widget>[];
    switch (s.kind) {
      case EntityKind.course:
        final mine = s.mine;
        if (mine != null) {
          out.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: EntityLearnerCard(mine: mine, self: s.learnerId == null || s.learnerId == _viewerId(context)),
          ));
        }
        final trend = s.trend;
        if (trend.isNotEmpty) out.add(_TrendBlock(trend: trend));
        final reasons = s.withdrawalReasons;
        if (reasons.isNotEmpty) out.add(_ReasonsBlock(reasons: reasons));
      case EntityKind.category:
        final top = s.topCourses;
        if (top.isNotEmpty) {
          out.add(_BlockCard(
            title: 'md_top_courses'.tr,
            icon: Icons.emoji_events_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (course, students) in top)
                EntityRowFrame(
                  ref: course.ref,
                  title: course.ref.name.isEmpty ? '#${course.ref.id}' : course.ref.name,
                  subtitle: course.teacher?.name,
                  trailing: Text(mdStudents(students), style: AppType.meta(context)),
                ),
            ]),
          ));
        }
      case EntityKind.student:
      case EntityKind.teacher:
        break;
    }
    return out;
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

/// The top of a detail: the picture, the name, what it belongs to (links), its status and the quick actions.
class EntityHeader extends StatelessWidget {
  const EntityHeader({super.key, required this.entity, this.summary, this.actions = const []});

  final EntityRef entity;
  final EntitySummary? summary;
  final List<EntityPanelAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary;
    final name = entity.name.isEmpty ? (s == null ? '' : '#${entity.id}') : entity.name;
    final username = s?.text('username');
    final meta = <String>[];
    final pills = <Widget>[];
    final links = <EntityRef>[];
    String? body;
    if (s != null) {
      switch (s.kind) {
        case EntityKind.student:
          final active = s.flag('is_active');
          if (active != null) {
            pills.add(AppStatusBadge(
                label: active ? 'md_active'.tr : 'md_inactive'.tr,
                tone: active ? AppTone.success : AppTone.warning,
                dot: true,
                dense: true));
          }
          if (s.text('email') != null) meta.add(s.text('email')!);
          if (s.text('phone') != null) meta.add(s.text('phone')!);
          if (s.time('created_at') != null) meta.add(mdText('md_joined', {'d': mdDate(s.time('created_at'))}));
          if (s.time('last_login') != null) meta.add(mdText('md_last_login', {'d': mdAgo(s.time('last_login'))}));
        case EntityKind.teacher:
          final active = s.flag('is_active');
          if (active != null) {
            pills.add(AppStatusBadge(
                label: active ? 'md_active'.tr : 'md_inactive'.tr,
                tone: active ? AppTone.success : AppTone.warning,
                dot: true,
                dense: true));
          }
          if (s.specialization != null) links.add(s.specialization!);
          body = s.text('bio');
          if (s.time('created_at') != null) meta.add(mdText('md_joined', {'d': mdDate(s.time('created_at'))}));
        case EntityKind.course:
          if (s.category != null) links.add(s.category!);
          if (s.teacher != null) links.add(s.teacher!);
          if (s.time('archived_at') != null) {
            pills.add(AppStatusBadge(label: 'md_status_archived'.tr, tone: AppTone.danger, dense: true));
          } else if (s.flag('is_published') != null) {
            final pub = s.flag('is_published')!;
            pills.add(AppStatusBadge(
                label: pub ? 'md_status_published'.tr : 'md_status_draft'.tr,
                tone: pub ? AppTone.success : AppTone.neutral,
                dense: true));
          }
          if (s.flag('is_private') == true) {
            pills.add(AppStatusBadge(label: 'md_private'.tr, tone: AppTone.info, icon: Icons.lock_outline_rounded, dense: true));
          }
          final status = s.text('status');
          if (status != null) {
            pills.add(AppStatusBadge(label: mdCourseStatusLabel(status), tone: AppTone.neutral, dense: true));
          }
          final price = _priceText(s.price);
          if (price != null) meta.add(price);
          final start = s.time('start_date'), end = s.time('end_date');
          if (start != null || end != null) meta.add('${mdDate(start)} – ${mdDate(end)}');
        case EntityKind.category:
          if (s.parent != null) links.add(s.parent!);
          links.addAll(s.children.take(6));
          body = s.text('description');
      }
    }
    final title = Text(name.isEmpty ? '—' : name,
        maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EntityThumb(entity, size: 56),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(entityKindLabel(entity.kind).toUpperCase(), style: AppType.overline(context)),
              const SizedBox(height: 2),
              Semantics(header: true, child: title),
              if (username != null)
                Text('@$username',
                    maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
              if (pills.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: pills),
              ],
            ]),
          ),
        ]),
        if (links.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xs, children: [for (final l in links) EntityChip(l)]),
        ],
        if (body != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(body, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          for (final m in meta)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          for (final a in actions.where((a) => a.primary)) ...[
            AppButton.primary(key: a.key, label: a.label, icon: a.icon, expand: true, onPressed: a.onPressed),
            const SizedBox(height: AppSpace.xs),
          ],
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final a in actions.where((a) => !a.primary))
              AppButton.tonal(key: a.key, label: a.label, icon: a.icon, size: AppButtonSize.sm, onPressed: a.onPressed),
          ]),
        ],
        const SizedBox(height: AppSpace.xxs),
        Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: c.divider),
      ]),
    );
  }

  static String? _priceText(Map<String, dynamic>? p) {
    if (p == null) return null;
    final cur = entityString(p['currency']) ?? '';
    final fees = entityDouble(p['fees']), monthly = entityDouble(p['monthly']);
    if ((fees == null || fees == 0) && (monthly == null || monthly == 0)) return 'md_free'.tr;
    final parts = [
      if (fees != null && fees > 0) mdMoney(EntityMoney(fees, cur)),
      if (monthly != null && monthly > 0) mdText('md_per_month', {'p': mdMoney(EntityMoney(monthly, cur))}),
    ];
    return parts.join(' · ');
  }
}

// ── Stats ────────────────────────────────────────────────────────────────────

/// The stat tiles: 2 per row in a panel, more on a page.
class EntityStatGrid extends StatelessWidget {
  const EntityStatGrid(this.stats, {super.key});

  final List<EntityStat> stats;

  @override
  Widget build(BuildContext context) => AppGrid(minTile: 150, spacing: AppSpace.xs, children: [
        for (final s in stats)
          Semantics(
            label: '${s.label}: ${s.value}',
            excludeSemantics: true,
            child: AppStatTile(icon: s.icon, label: s.label, value: s.value, color: appToneColor(context, s.tone)),
          ),
      ]);
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppShimmer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: const [
              Expanded(child: AppSkeletonBox(height: 68, radius: 20)),
              SizedBox(width: AppSpace.xs),
              Expanded(child: AppSkeletonBox(height: 68, radius: 20)),
            ]),
            const SizedBox(height: AppSpace.xs),
            Row(children: const [
              Expanded(child: AppSkeletonBox(height: 68, radius: 20)),
              SizedBox(width: AppSpace.xs),
              Expanded(child: AppSkeletonBox(height: 68, radius: 20)),
            ]),
            const SizedBox(height: AppSpace.lg),
            const AppSkeletonBox(width: 140, height: 14),
            const SizedBox(height: AppSpace.sm),
            for (var i = 0; i < 3; i++) ...[
              const AppSkeletonBox(height: 64, radius: 16),
              const SizedBox(height: AppSpace.xs),
            ],
          ]),
        ),
      );
}

// ── Blocks ───────────────────────────────────────────────────────────────────

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _SectionHeading(icon: icon, title: title),
            const SizedBox(height: AppSpace.sm),
            child,
          ]),
        ),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(icon, size: AppIconSize.md, color: Color.lerp(c.primary, c.textDark, 0.25)),
      AppSpace.gapXs,
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        ),
      ),
    ]);
  }
}

/// New enrollments of the last 12 weeks as one sparkline (phase 3; the charts are phase 5).
class _TrendBlock extends StatelessWidget {
  const _TrendBlock({required this.trend});

  final List<EntityTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final total = trend.fold<int>(0, (a, p) => a + p.count);
    final values = [for (final p in trend) p.count.toDouble()];
    final first = trend.first.weekStart, last = trend.last.weekStart;
    return _BlockCard(
      title: 'md_trend_title'.tr,
      icon: Icons.show_chart_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(mdText('md_trend_total', {'n': mdNumber(total)}), style: AppType.figure(context)),
        const SizedBox(height: AppSpace.xs),
        AppSparkline(values, height: 48, label: mdText('md_trend_total', {'n': mdNumber(total)})),
        const SizedBox(height: AppSpace.xxs),
        Row(children: [
          Expanded(child: Text(mdDate(first), style: AppType.meta(context))),
          Text(mdDate(last), style: AppType.meta(context)),
        ]),
      ]),
    );
  }
}

/// Why students withdrew: each reason with its count and a bar against the largest.
class _ReasonsBlock extends StatelessWidget {
  const _ReasonsBlock({required this.reasons});

  final List<(String, int)> reasons;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = reasons.fold<int>(1, (a, r) => r.$2 > a ? r.$2 : a);
    return _BlockCard(
      title: 'md_reasons_title'.tr,
      icon: Icons.help_outline_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (code, n) in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Semantics(
              label: '${mdReasonLabel(code)}: $n',
              excludeSemantics: true,
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text(mdReasonLabel(code), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                ),
                AppSpace.gapXs,
                Expanded(flex: 2, child: AppProgressBar(value: n.toDouble(), max: max.toDouble(), height: 6, color: c.danger)),
                SizedBox(
                  width: 36,
                  child: Text('$n', textAlign: TextAlign.end, style: AppType.meta(context).copyWith(color: c.textDark)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// A course's content: its sessions and materials.
class _ContentBlock extends StatelessWidget {
  const _ContentBlock({required this.summary});

  final EntitySummary summary;

  @override
  Widget build(BuildContext context) => EntityStatGrid([
        EntityStat('sessions', 'md_stat_sessions'.tr, Icons.event_note_outlined, mdNumber(summary.stat('sessions') ?? 0)),
        EntityStat('materials', 'md_stat_materials'.tr, Icons.video_library_outlined,
            mdNumber(summary.stat('materials') ?? 0)),
      ]);
}

// ── Sections ─────────────────────────────────────────────────────────────────

/// A section of the detail: a card with its heading and body.
class EntitySectionCard extends StatelessWidget {
  const EntitySectionCard({super.key, required this.spec, required this.child});

  final EntitySectionSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: _SectionHeading(icon: spec.icon, title: spec.title),
            ),
            const SizedBox(height: AppSpace.sm),
            child,
          ]),
        ),
      );
}

/// One sub-list: search (once there is enough to search), the contract's filter as chips, the sort, the rows (links)
/// and "Show more".
class EntitySubList extends StatefulWidget {
  const EntitySubList({
    super.key,
    required this.entity,
    required this.spec,
    this.initialSearch,
    this.highlightId,
    this.fixedFilter = const {},
    this.linkRows = true,
  });

  final EntityRef entity;
  final EntitySectionSpec spec;

  /// Sent with every page and not shown (a parent's child).
  final Map<String, String> fixedFilter;
  final bool linkRows;

  /// Starts searching for this (a course opened from a student starts at that student).
  final String? initialSearch;
  final int? highlightId;

  @override
  State<EntitySubList> createState() => _EntitySubListState();
}

class _EntitySubListState extends State<EntitySubList> {
  late EntityListQuery _query = EntityListQuery(
    search: widget.initialSearch ?? '',
    sort: widget.spec.sorts.isEmpty ? null : widget.spec.sorts.first,
    size: widget.spec.pageSize,
  );
  late final _searchCtl = TextEditingController(text: widget.initialSearch ?? '');
  final _items = <EntityItem>[];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _maxTotal = 0;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  EntityListQuery _withFixed(EntityListQuery q) =>
      widget.fixedFilter.isEmpty ? q : q.copyWith(filter: {...q.filter, ...widget.fixedFilter});

  Future<void> _reload() async {
    final t = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await EntitiesApi.instance.page(widget.entity, widget.spec.section, query: _withFixed(_query.copyWith(page: 1)));
      if (!mounted || t != _ticket) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.items);
        _total = p.total;
        if (_query.search.isEmpty && _query.filter.isEmpty && p.total > _maxTotal) _maxTotal = p.total;
        _hasMore = p.hasMore;
        _loading = false;
        _query = _query.copyWith(page: 1);
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    final t = _ticket;
    setState(() => _loadingMore = true);
    final next = _query.copyWith(page: _query.page + 1);
    try {
      final p = await EntitiesApi.instance.page(widget.entity, widget.spec.section, query: _withFixed(next));
      if (!mounted || t != _ticket) return;
      setState(() {
        _items.addAll(p.items);
        _total = p.total;
        _hasMore = p.hasMore;
        _query = next;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() => _loadingMore = false);
      showAppNotice(entityErrorText(e), error: true);
    }
  }

  void _setSearch(String q) {
    if (q.trim() == _query.search.trim()) return;
    _query = _query.copyWith(search: q.trim(), page: 1);
    _reload();
  }

  void _setFilter(String? v) {
    final key = widget.spec.filterKey;
    if (key == null) return;
    _query = _query.copyWith(filter: v == null ? const {} : {key: v}, page: 1);
    _reload();
  }

  void _setSort(String? s) {
    if (s == null || s == _query.sort) return;
    _query = _query.copyWith(sort: s, page: 1);
    _reload();
  }

  void _openHistory(int studentId, int courseId, String title) =>
      showEntityTimelineSheet(context, studentId: studentId, courseId: courseId, title: title);

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final filterValue = spec.filterKey == null ? null : _query.filter[spec.filterKey];
    final querying = _query.search.isNotEmpty || filterValue != null;
    final showSearch = spec.searchable && (_maxTotal > 6 || _query.search.isNotEmpty);
    final showFilter = spec.filterKey != null && (_maxTotal > 1 || filterValue != null);
    final showSort = spec.sorts.length > 1 && (_maxTotal > 1);
    final isEnrollments = _items.isNotEmpty ? _items.first is EnrollmentRow : spec.filterKey == 'state';
    final ownerId = widget.entity.id;

    final toolbar = <Widget>[
      if (showSearch || showSort)
        LayoutBuilder(builder: (context, box) {
          final sort = showSort
              ? AppDropdown<String>(
                  value: _query.sort,
                  decoration: InputDecoration(labelText: 'md_sort'.tr, isDense: true),
                  items: [for (final s in spec.sorts) DropdownMenuItem(value: s, child: Text(mdSortLabel(s)))],
                  onChanged: _setSort,
                )
              : null;
          final search = showSearch
              ? AppSearchField(
                  controller: _searchCtl, hint: '${'md_search'.tr} ${spec.title}', dense: true, onChanged: _setSearch)
              : null;
          if (search != null && sort != null && box.maxWidth >= 440) {
            return Row(children: [
              Expanded(child: search),
              AppSpace.gapXs,
              SizedBox(width: 180, child: sort),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ?search,
            if (search != null && sort != null) AppSpace.gapXs,
            ?sort,
          ]);
        }),
      if (showFilter)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              AppChoiceChip(label: 'md_filter_all'.tr, selected: filterValue == null, onTap: () => _setFilter(null)),
              for (final o in spec.filterOptions) ...[
                const SizedBox(width: AppSpace.xxs),
                AppChoiceChip(label: spec.filterLabel(o), selected: filterValue == o, onTap: () => _setFilter(o)),
              ],
            ]),
          ),
        ),
    ];

    final Widget body;
    if (_loading) {
      body = const _RowsSkeleton();
    } else if (_error != null) {
      body = AppErrorState(message: entityErrorText(_error), onRetry: _reload, compact: true);
    } else if (_items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
        child: Text(querying ? 'md_no_results'.tr : (spec.emptyKey ?? 'md_empty_section').tr,
            textAlign: TextAlign.center, style: AppType.body(context)),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: context.colors.divider),
          entityRowFor(context, _items[i],
              onHistory: isEnrollments ? _openHistory : null,
              ownerId: ownerId,
              highlightId: widget.highlightId,
              ownerKind: widget.entity.kind,
              link: widget.linkRows),
        ],
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Center(
              child: AppButton.ghost(
                label: '${'md_load_more'.tr} · ${mdText('md_shown_of', {'n': '${_items.length}', 'total': '$_total'})}',
                icon: Icons.expand_more_rounded,
                busy: _loadingMore,
                size: AppButtonSize.sm,
                onPressed: _more,
              ),
            ),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...toolbar,
      if (toolbar.isNotEmpty) const SizedBox(height: AppSpace.xs),
      body,
    ]);
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) =>
      const AppListSkeleton(items: 3, padding: EdgeInsets.symmetric(vertical: AppSpace.xxs));
}

// ── Timeline ─────────────────────────────────────────────────────────────────

/// A student's history in one course as a sheet (the History button of an enrollment row).
Future<void> showEntityTimelineSheet(BuildContext context,
        {required int studentId, required int courseId, String title = ''}) =>
    showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: title.isEmpty ? 'md_history'.tr : '${'md_history'.tr} · $title',
        children: [EntityTimelineList(studentId: studentId, courseId: courseId)],
      ),
    );

/// A student's timeline section: the course picker (their courses, the one in context first) and that course's
/// history.
class StudentTimelineSection extends StatefulWidget {
  const StudentTimelineSection({super.key, required this.studentId, this.focusCourseId});

  final int studentId;
  final int? focusCourseId;

  @override
  State<StudentTimelineSection> createState() => _StudentTimelineSectionState();
}

class _StudentTimelineSectionState extends State<StudentTimelineSection> {
  List<EntityRef>? _courses;
  Object? _error;
  int? _courseId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await EntitiesApi.instance.page(EntityRef(EntityKind.student, widget.studentId), 'courses',
          query: const EntityListQuery(sort: 'activity_desc', size: 50));
      if (!mounted) return;
      final courses = [for (final r in p.items.whereType<EnrollmentRow>()) r.subject];
      setState(() {
        _courses = courses;
        final focus = widget.focusCourseId;
        _courseId = focus != null && courses.any((c) => c.id == focus)
            ? focus
            : (courses.isEmpty ? null : courses.first.id);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorState(message: entityErrorText(_error), onRetry: _load, compact: true);
    final courses = _courses;
    if (courses == null) return const _RowsSkeleton();
    if (courses.isEmpty || _courseId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Text('md_empty_section'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (courses.length > 1) ...[
        AppDropdown<int>(
          value: _courseId,
          decoration: InputDecoration(labelText: 'md_timeline_course'.tr, isDense: true),
          items: [
            for (final c in courses)
              DropdownMenuItem(value: c.id, child: Text(c.name.isEmpty ? '#${c.id}' : c.name)),
          ],
          onChanged: (v) => setState(() => _courseId = v),
        ),
        const SizedBox(height: AppSpace.sm),
      ] else ...[
        Text(courses.first.name, style: AppType.label(context)),
        const SizedBox(height: AppSpace.sm),
      ],
      EntityTimelineList(key: ValueKey('md.tl.${widget.studentId}.$_courseId'), studentId: widget.studentId, courseId: _courseId!),
    ]);
  }
}

/// One student's history in one course, newest first, 20 at a time.
class EntityTimelineList extends StatefulWidget {
  const EntityTimelineList({super.key, required this.studentId, required this.courseId});

  final int studentId;
  final int courseId;

  @override
  State<EntityTimelineList> createState() => _EntityTimelineListState();
}

class _EntityTimelineListState extends State<EntityTimelineList> {
  final _events = <EntityTimelineEvent>[];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await EntitiesApi.instance.timeline(widget.studentId, widget.courseId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _events.addAll(p.items);
        _page = p.page;
        _hasMore = p.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      if (_loading) return const _RowsSkeleton();
      if (_error != null) return AppErrorState(message: entityErrorText(_error), onRetry: _next, compact: true);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Text('md_timeline_empty'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < _events.length; i++)
        EntityTimelineTile(_events[i], last: i == _events.length - 1 && !_hasMore),
      if (_hasMore)
        Center(
          child: AppButton.ghost(
            label: 'md_load_more'.tr,
            icon: Icons.expand_more_rounded,
            busy: _loading,
            size: AppButtonSize.sm,
            onPressed: _next,
          ),
        ),
    ]);
  }
}
