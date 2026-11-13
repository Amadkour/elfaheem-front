// lib/design/master_detail/entity_detail_view.dart — the body of a detail panel / page (D-290).
//
// Loads the summary (the cached one at once, else the row's own name + image over a skeleton, then the server's;
// an error with Retry), then draws, in this order: the header (picture, name, links to the related entities, the
// quick actions), the badges worded per code, the stat tiles, the kind's blocks (a course's insight line, trend and
// withdrawal reasons, the history of the student it was opened from, a category's top courses, a learner's own
// enrollment) and every section the server listed, in its order:
// a paged sub-list with search, the contract's filter and sort, whose rows are links (student → course → category →
// teacher → …); a course's content block.
//
// A student (student_detail.dart): the overview card instead of the stat tiles, the courses section with each course's
// facts and timeline unfolding under its row, and for `can.manage` the management part. A course opened from a student
// keeps that student as its context.
library;

import 'package:flutter_education_app/features/shared/study_profile/study_profile_model.dart' show StudyProfile;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredAdminEntityManage;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/features/shared/course/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/student/models.dart' show AppCurrencyX;
import 'package:provider/provider.dart';

import '../app_bidi.dart' show ltrIsolate;
import '../app_kit.dart';
import 'entity_chip.dart';
import 'entity_learner.dart';
import 'entity_panel_controller.dart';
import 'entity_specs.dart';
import 'entity_timeline.dart';
import 'entity_viewer_actions.dart';
import 'student_detail.dart';

/// A quick action of the panel (Manage, View as …), shown under the header.
class EntityPanelAction {
  const EntityPanelAction(
      {required this.icon, required this.label, required this.onPressed, this.key, this.danger = false, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Key? key;

  /// Drawn as a danger action where one is possible.
  final bool danger;
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

  /// The management part of a student, for `can.manage` (loaded with the first summary that allows it).
  StudentManage? _manage;
  int? _manageFor;
  Object? _manageError;

  EntityRef get ref => widget.entity;

  void _syncManage(EntitySummary s) {
    if (s.kind != EntityKind.student || !s.can.manage || _manageFor == s.id) return;
    _manageFor = s.id;
    _loadManage(s.ref);
  }

  Future<void> _loadManage(EntityRef student) async {
    if (_manageError != null) setState(() => _manageError = null);
    try {
      final m = await loadStudentManage(student, onChanged: _entityChanged, onDeleted: () => widget.controller?.close());
      if (!mounted || _manageFor != student.id) {
        m.dispose();
        return;
      }
      m.addListener(_manageChanged);
      setState(() => _manage = m);
    } catch (e) {
      if (mounted) setState(() => _manageError = e);
    }
  }

  void _manageChanged() {
    if (mounted) setState(() {});
  }

  /// A change made here: the summary and the sub-lists load again, and the list behind the panel hears of it.
  void _entityChanged() {
    EntitiesApi.instance.invalidate(ref);
    final c = widget.controller;
    if (c != null) {
      c.entityChanged();
    } else if (mounted) {
      _load(force: true);
    }
  }

  void _dropManage() {
    _manage?.removeListener(_manageChanged);
    _manage?.dispose();
    _manage = null;
    _manageFor = null;
    _manageError = null;
  }

  @override
  void dispose() {
    _dropManage();
    super.dispose();
  }

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
      _dropManage();
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
      _summaryArrived(hit);
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
      _summaryArrived(s);
    } catch (e) {
      if (!mounted || want != ref) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// What the summary tells the rest of the panel: the management part, and the names the trail lacks (a deep link
  /// gives only kinds and ids, and the breadcrumbs and a course's student context draw names).
  void _summaryArrived(EntitySummary s) {
    _syncManage(s);
    final c = widget.controller;
    if (c == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.learn(s.ref);
      for (final r in c.trail) {
        if (r.name.isEmpty) {
          EntitiesApi.instance.summary(r).then((named) {
            if (mounted) c.learn(named.ref);
          }, onError: (Object _) {});
        }
      }
    });
  }

  /// The management block of a teacher / category this viewer manages: it lives in the detail itself, so every host
  /// (any list's panel, the full page) has it.
  Widget? _manageOf(EntitySummary s) => s.can.manage && (s.kind == EntityKind.teacher || s.kind == EntityKind.category)
      ? deferredAdminEntityManage(s, onChanged: _managed, onRemoved: _removed)
      : null;

  void _managed() {
    EntitiesApi.instance.invalidate(ref);
    final c = widget.controller;
    if (c != null) {
      c.reload();
    } else {
      _load(force: true);
    }
  }

  /// The entity is gone: the panel steps back or closes, a full page of its own (no list behind it) goes back. The
  /// revision tells the list behind to reload.
  void _removed() {
    EntitiesApi.instance.invalidate(ref);
    final c = widget.controller;
    if (c == null || (c.rowKind == null && !c.canBack)) {
      Navigator.of(context).maybePop();
      return;
    }
    c.reload();
    if (!c.back()) c.close();
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
        actions: [
          ...?_manage?.headerActions(context),
          ...(widget.actions != null ? widget.actions!(ref, s) : entityViewerActions(context, ref, s, controller: ctl)),
        ],
        manage: s == null ? null : _manageOf(s),
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
      final contextStudent = ctl?.contextStudentId == null ? null : ctl?.contextRef;
      if (contextStudent != null && !s.sections.contains('timeline')) {
        children.add(StudentInCourseBlock(
            key: ValueKey('md.context.${contextStudent.id}'), student: contextStudent, courseId: s.id));
      }
      final insight = mdCourseInsight(s);
      if (insight != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text(insight, key: const ValueKey('md.course.insight'), style: AppType.row(context)),
        ));
      }
      final stats = statSpecsOf(s);
      if (s.kind == EntityKind.student) {
        children.add(StudentOverviewCard(summary: s));
      } else if (stats.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: EntityStatGrid(stats)));
      }
      final focusCourse = ctl?.focusCourseId;
      children.addAll(_blocks(context, s));
      final contextStudentId = ctl?.contextStudentId;
      String? nameOf(int? id, EntityKind kind) {
        if (ctl == null || id == null) return null;
        final hit = ctl.trail.where((r) => r.kind == kind && r.id == id);
        return hit.isEmpty ? null : hit.last.name;
      }

      if (s.kind == EntityKind.category) {
        final specs = [for (final section in s.sections) ?sectionSpecOf(s.kind, section)];
        if (specs.isNotEmpty) children.add(EntityConnectedTabs(summary: s, specs: specs));
      }
      for (final section in s.kind == EntityKind.category ? const <String>[] : s.sections) {
        final spec = sectionSpecOf(s.kind, section);
        if (spec == null) continue; // a student's `timeline` too: each course's history unfolds under its row
        final studentCourses = s.kind == EntityKind.student && section == 'courses';
        final Widget body = switch (spec.shape) {
          EntitySectionShape.block => _ContentBlock(summary: s),
          EntitySectionShape.timeline => _learnerTimeline(context, s, contextStudentId),
          EntitySectionShape.list => EntitySubList(
              key: ValueKey('md.${s.kind.name}.${s.id}.$section'),
              entity: s.ref,
              spec: spec,
              initialSearch: switch ((s.kind, section)) {
                (EntityKind.course, 'students') => nameOf(contextStudentId, EntityKind.student),
                _ => null,
              },
              highlightId: s.kind == EntityKind.student ? focusCourse : contextStudentId,
              revision: ctl?.revision ?? 0,
              pinned: studentCourses && focusCourse != null
                  ? () => EntitiesApi.instance.studentCourse(s.id, focusCourse)
                  : null,
              rowBuilder: studentCourses
                  ? (context, item) => item is EnrollmentRow
                      ? StudentCourseRow(
                          key: ValueKey('md.student.row.${item.enrollment.enrollmentId}'),
                          studentId: s.id,
                          row: item,
                          focused: item.subject.id == focusCourse,
                          actions: _manage?.courseActions(context, item) ?? const [],
                        )
                      : null
                  : null,
              filterCounts: s.kind == EntityKind.course && section == 'students' ? _stateCounts(s) : const {},
              // a parent names the child; a learner's own course draws its rows without links (nothing to open)
              fixedFilter: s.learnerId != null && s.mine != null ? {'student_id': '${s.learnerId}'} : const {},
              linkRows: s.mine == null,
            ),
        };
        children.add(EntitySectionCard(
          spec: spec,
          trailing: studentCourses ? _manage?.coursesAction(context) : null,
          child: body,
        ));
      }
      if (s.kind == EntityKind.student && s.can.manage) {
        if (_manageError != null) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: AppErrorState(message: entityErrorText(_manageError), onRetry: () => _loadManage(s.ref), compact: true),
          ));
        }
        children.addAll(_manage?.sections(context) ?? const []);
      }
    }
    return SingleChildScrollView(
      // one entry per place in the trail: Back returns to the offset it left, a second visit starts at the top
      key: PageStorageKey('md.scroll.${ref.toToken()}.${ctl?.index ?? 0}'),
      controller: widget.scrollController,
      padding: widget.padding,
      child: KeyedSubtree(
        key: ValueKey('md.view.${ref.toToken()}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  /// How many students sit behind each state chip of a course's students list.
  Map<String, int> _stateCounts(EntitySummary s) => {
        for (final st in entityEnrollmentStates)
          if (s.stat(st) != null) st: s.stat(st)!.round(),
      };

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
            child: EntityLearnerCard(mine: mine, self: s.learnerId == null || (_viewerId(context) ?? s.learnerId) == s.learnerId),
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
  const EntityHeader({super.key, required this.entity, this.summary, this.actions = const [], this.manage});

  final EntityRef entity;
  final EntitySummary? summary;
  final List<EntityPanelAction> actions;

  /// The management block under the quick actions (a teacher / category this viewer manages).
  final Widget? manage;

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
          // stage / grade / track and school (D-795): who the teacher is teaching
          final study = StudyProfile.fromJson(entityMap(s.header['study']));
          if (study.summary.isNotEmpty) {
            pills.add(AppStatusBadge(label: study.summary, tone: AppTone.info, icon: Icons.school_rounded, dense: true));
          }
          if (study.place.isNotEmpty) meta.add(study.place);
          for (final o in s.organizations) {
            if (o.name.isNotEmpty) {
              pills.add(AppStatusBadge(label: o.name, tone: AppTone.neutral, icon: Icons.apartment_rounded, dense: true));
            }
          }
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
          if (s.organizations.isNotEmpty) meta.add(mdText('md_p6_member_of', {'o': [for (final o in s.organizations) o.name].where((n) => n.isNotEmpty).join(' · ')}));
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
          if (start != null && end != null) {
            meta.add('${mdDate(start)} – ${mdDate(end)}');
          } else if (start != null) {
            meta.add(mdText('md_p5_starts', {'d': mdDate(start)}));
          } else if (end != null) {
            meta.add(mdText('md_p5_ends', {'d': mdDate(end)}));
          }
        case EntityKind.category:
          if (s.parent != null) links.add(s.parent!);
          links.addAll(s.children.take(6));
          body = s.text('description');
          if (s.children.length > 6) meta.add(mdText('md_p6_more_children', {'n': '${s.children.length - 6}'}));
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
        if (manage != null) ...[
          const SizedBox(height: AppSpace.sm),
          manage!,
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
    final currency = AppCurrencyX.fromCode(cur);
    final parts = [
      if (fees != null && fees > 0) coursePriceLabel(currency, fees),
      if (monthly != null && monthly > 0) mdText('md_per_month', {'p': coursePriceLabel(currency, monthly)}),
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
  Widget build(BuildContext context) => AppGrid(minTile: 150, spacing: AppSpace.xs, padding: EdgeInsets.zero, children: [
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
  const _SectionHeading({required this.icon, required this.title, this.shrink = false});

  final IconData icon;
  final String title;

  /// As wide as its text instead of the whole line.
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max, children: [
      Icon(icon, size: AppIconSize.md, color: Color.lerp(c.primary, c.textDark, 0.25)),
      AppSpace.gapXs,
      Flexible(
        fit: shrink ? FlexFit.loose : FlexFit.tight,
        child: Semantics(
          header: true,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        ),
      ),
    ]);
  }
}

/// New enrollments of the last 12 weeks: the total, how the last 4 weeks compare with the 4 before, a bar per week.
class _TrendBlock extends StatelessWidget {
  const _TrendBlock({required this.trend});

  final List<EntityTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final total = trend.fold<int>(0, (a, p) => a + p.count);
    final values = [for (final p in trend) p.count.toDouble()];
    final first = trend.first.weekStart, last = trend.last.weekStart;
    final change = mdTrendChange(trend);
    final totalText = mdText('md_trend_total', {'n': mdNumber(total)});
    return _BlockCard(
      title: 'md_trend_title'.tr,
      icon: Icons.bar_chart_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(totalText, style: AppType.figure(context)),
            if (change != null)
              AppStatusBadge(
                label: mdText('md_p5_trend_change', {'p': ltrIsolate('${change > 0 ? '+' : ''}$change%')}),
                tone: change > 0 ? AppTone.success : (change < 0 ? AppTone.warning : AppTone.neutral),
                dense: true,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        // the bars speak for the whole block: week by week, with the dates the axis leaves out
        Semantics(
          container: true,
          label: [
            '${'md_trend_title'.tr}: $totalText',
            for (final p in trend) '${mdDate(p.weekStart)}: ${p.count}',
          ].join('. '),
          child: ExcludeSemantics(
            child: AppBarChart(
              height: 112,
              maxBarWidth: AppSpace.md,
              integerAxis: true,
              series: [AppChartSeries('md_trend_title'.tr, values)],
              labels: [for (final _ in trend) ''],
            ),
          ),
        ),
        Row(children: [
          Expanded(child: Text(mdDate(first), style: AppType.meta(context))),
          Text(mdDate(last), style: AppType.meta(context)),
        ]),
      ]),
    );
  }
}

/// Why students withdrew: each reason with its count, its share and a bar against the largest, the largest first.
class _ReasonsBlock extends StatelessWidget {
  const _ReasonsBlock({required this.reasons});

  final List<(String, int)> reasons;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = reasons.fold<int>(1, (a, r) => r.$2 > a ? r.$2 : a);
    final total = reasons.fold<int>(0, (a, r) => a + r.$2);
    final sorted = [...reasons]..sort((a, b) => b.$2.compareTo(a.$2));
    return _BlockCard(
      title: 'md_reasons_title'.tr,
      icon: Icons.help_outline_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (code, n) in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Semantics(
              label: '${mdReasonLabel(code)}: $n, ${mdPercent(100 * n / (total == 0 ? 1 : total))}',
              excludeSemantics: true,
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text(mdReasonLabel(code), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                ),
                AppSpace.gapXs,
                Expanded(flex: 2, child: AppProgressBar(value: n.toDouble(), max: max.toDouble(), height: 6, color: c.danger)),
                SizedBox(
                  width: 68,
                  child: Text('$n · ${mdPercent(100 * n / (total == 0 ? 1 : total))}',
                      textAlign: TextAlign.end, style: AppType.meta(context).copyWith(color: c.textDark)),
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
  const EntitySectionCard({super.key, required this.spec, required this.child, this.trailing});

  final EntitySectionSpec spec;
  final Widget child;

  /// An action beside the heading.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: trailing == null
                  ? _SectionHeading(icon: spec.icon, title: spec.title)
                  // the action drops under the heading when the two do not fit on one line
                  : Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xxs,
                      children: [_SectionHeading(icon: spec.icon, title: spec.title, shrink: true), trailing!],
                    ),
            ),
            const SizedBox(height: AppSpace.sm),
            child,
          ]),
        ),
      );
}

/// A category's connected lists (its courses, teachers and students) as tabs with their counts. A tab loads on its
/// first visit and keeps its search, filter and rows; the open tab survives drilling in and coming back.
class EntityConnectedTabs extends StatefulWidget {
  const EntityConnectedTabs({super.key, required this.summary, required this.specs});

  final EntitySummary summary;
  final List<EntitySectionSpec> specs;

  @override
  State<EntityConnectedTabs> createState() => _EntityConnectedTabsState();
}

class _EntityConnectedTabsState extends State<EntityConnectedTabs> {
  late int _tab;
  final _visited = <int>{};

  String get _memory => 'md.tabs.${widget.summary.ref.toToken()}';

  @override
  void initState() {
    super.initState();
    final saved = PageStorage.maybeOf(context)?.readState(context, identifier: _memory);
    _tab = saved is int && saved < widget.specs.length ? saved : 0;
    _visited.add(_tab);
  }

  void _select(int i) {
    PageStorage.maybeOf(context)?.writeState(context, i, identifier: _memory);
    setState(() {
      _tab = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final specs = widget.specs;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppUnderlineTabs(
            expand: true,
            index: _tab.clamp(0, specs.length - 1),
            onChanged: _select,
            items: [
              for (final spec in specs) AppTabItem(spec.title, icon: spec.icon, count: s.stat(spec.section)?.toInt()),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < specs.length; i++)
            if (_visited.contains(i))
              Visibility(
                key: ValueKey('md.tab.${specs[i].section}'),
                visible: i == _tab,
                maintainState: true,
                child: EntitySubList(entity: s.ref, spec: specs[i]),
              ),
        ]),
      ),
    );
  }
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
    this.revision = 0,
    this.pinned,
    this.rowBuilder,
    this.filterCounts = const {},
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

  /// The panel's revision: when it moves the rows load again, in place.
  final int revision;

  /// The row of [highlightId], drawn first when the unfiltered list's first page does not hold it.
  final Future<EntityItem?> Function()? pinned;

  /// Draws a row its own way (null: the usual row).
  final Widget? Function(BuildContext context, EntityItem item)? rowBuilder;
  /// How many rows sit behind each filter chip, when the summary knows.
  final Map<String, int> filterCounts;

  @override
  State<EntitySubList> createState() => _EntitySubListState();
}

/// What a sub-list holds when the panel swaps to another entity: Back draws it again at once, with its filters and
/// the rows it had (so the scroll offset still fits).
class _SubListMemo {
  const _SubListMemo(this.query, this.items, this.total, this.hasMore, this.maxTotal);

  final EntityListQuery query;
  final List<EntityItem> items;
  final int total;
  final bool hasMore;
  final int maxTotal;
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
  EntityItem? _pinned;

  String get _memoId => 'md.sub.${widget.entity.toToken()}.${widget.spec.section}.${widget.initialSearch ?? ''}';

  @override
  void initState() {
    super.initState();
    final memo = PageStorage.maybeOf(context)?.readState(context, identifier: _memoId);
    if (memo is _SubListMemo) {
      _query = memo.query;
      _searchCtl.text = memo.query.search;
      _items.addAll(memo.items);
      _total = memo.total;
      _hasMore = memo.hasMore;
      _maxTotal = memo.maxTotal;
      _loading = false;
    } else {
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant EntitySubList old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _reload(quiet: true);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool _isPinned(EntityItem i) => i is EnrollmentRow && i.subject.id == widget.highlightId;

  /// The focused row when the first page of the plain list lacks it. A failure only loses the pin.
  Future<EntityItem?> _loadPin(List<EntityItem> firstPage) async {
    final load = widget.pinned;
    if (load == null || _query.search.isNotEmpty || _query.filter.isNotEmpty || firstPage.any(_isPinned)) return null;
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  void _remember() => PageStorage.maybeOf(context)
      ?.writeState(context, _SubListMemo(_query, List.of(_items), _total, _hasMore, _maxTotal), identifier: _memoId);

  EntityListQuery _withFixed(EntityListQuery q) =>
      widget.fixedFilter.isEmpty ? q : q.copyWith(filter: {...q.filter, ...widget.fixedFilter});

  /// [quiet]: the rows on screen stay until the new ones arrive (a change made in the panel).
  Future<void> _reload({bool quiet = false}) async {
    final t = ++_ticket;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await EntitiesApi.instance.page(widget.entity, widget.spec.section, query: _withFixed(_query.copyWith(page: 1)));
      final pin = await _loadPin(p.items);
      if (!mounted || t != _ticket) return;
      setState(() {
        _pinned = pin;
        _items
          ..clear()
          ..addAll(p.items);
        _total = p.total;
        if (_query.search.isEmpty && _query.filter.isEmpty && p.total > _maxTotal) _maxTotal = p.total;
        _hasMore = p.hasMore;
        _loading = false;
        _query = _query.copyWith(page: 1);
      });
      _remember();
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
      _remember();
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
    final pinned = _pinned;
    final rows = pinned == null ? _items : [pinned, ..._items.where((i) => !_isPinned(i))];

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
                  controller: _searchCtl, hint: '${'md_search'.tr} ${spec.title}', onChanged: _setSearch)
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
          child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
            AppChoiceChip(label: 'md_filter_all'.tr, selected: filterValue == null, onTap: () => _setFilter(null)),
            for (final o in spec.filterOptions)
              // an empty state is not worth a chip, unless it is the one in use
              if (widget.filterCounts[o] != 0 || filterValue == o)
                AppChoiceChip(
                  label: widget.filterCounts[o] == null
                      ? spec.filterLabel(o)
                      : '${spec.filterLabel(o)} · ${mdNumber(widget.filterCounts[o])}',
                  selected: filterValue == o,
                  onTap: () => _setFilter(o),
                ),
          ]),
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
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: context.colors.divider),
          widget.rowBuilder?.call(context, rows[i]) ??
              entityRowFor(context, rows[i],
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
