// course_student_screen.dart
//
// The students enrolled in one of the teacher's courses (Warm Editorial, D-610 – D-629).
// ─────────────────────────────────────────────────────────────────────────────
// One memorable thing, everything else quiet:
//   • the editorial page header (title, the course as its subtitle, Back) on the canvas;
//   • ONE peach hero block — the class's progress: the average as a ring that fills once with its figure rolling
//     (AppOdometer), beside the class size and how many completed (counting up once); it leans under the pointer
//     (AppTilt) and is the screen's only colour block;
//   • search and "send a certificate to everyone" under it, on one row on wide windows;
//   • each student a paper card on a warm hairline: a progress ring around the avatar, name / @username / email /
//     joined, the percentage in its meaning's ink and a compact certificate pill; a list on phones, a 2–3 column grid
//     once there is room; the first cards rise in once (AppReveal) with the ring — the screen's one entrance;
//   • a tapped card opens the student's connected detail in the shared panel (D-290); certificates stay one action
//     away (the panel's Certificates action opens the student's certificates in the kit's dialog).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart' show EntitySummary;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_viewer_actions.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../../teacher/home/teacher_models.dart';
import 'course_student_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppFill, AppOdometer, AppPressScale, AppReveal, AppTilt;
import 'package:flutter_education_app/design/app_username.dart';

class EnrolledStudentsScreen extends StatefulWidget {
  final TeacherCourse course;

  const EnrolledStudentsScreen({super.key, required this.course});

  @override
  State<EnrolledStudentsScreen> createState() => _EnrolledStudentsScreenState();
}

class _EnrolledStudentsScreenState extends State<EnrolledStudentsScreen> {
  final _search = TextEditingController();
  // A student card opens that student's connected detail (their courses with me, history, Message) in the shared panel
  // (D-290); the certificates of this course stay one action away.
  final _panel = EntityPanelController(rowKind: EntityKind.student);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<EnrolledStudentsProvider>();
    await provider.fetch(widget.course.id);
    if (!mounted || widget.course.certificates.isEmpty) return;
    await provider.loadIssuedForCertificates(
      widget.course.certificates.map((c) => c.id).toList(),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _panel.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    // Fire loadMore a little before the true end, so the next page is
    // already in flight by the time the user reaches the bottom.
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
      context.read<EnrolledStudentsProvider>().loadMore();
    }
    return false;
  }

  List<EntityPanelAction> _actions(BuildContext context, EntityRef ref, EntitySummary? s) => [
        ...entityViewerActions(context, ref, s, controller: _panel),
        if (ref.kind == EntityKind.student && widget.course.certificates.isNotEmpty)
          EntityPanelAction(
            key: const ValueKey('md.course_student.certificates'),
            icon: Icons.workspace_premium_rounded,
            label: 'certificates'.tr,
            onPressed: () {
              final p = context.read<EnrolledStudentsProvider>();
              final st = p.students.where((x) => x.id == ref.id).firstOrNull;
              if (st != null) _showStudentDialog(context, st, widget.course, _progressColorOf(context, st));
            },
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      child: SafeArea(
        child: MasterDetailScaffold(
          controller: _panel,
          rootLabel: 'students'.tr,
          actions: (ref, s) => _actions(context, ref, s),
          list: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                title: 'enrolled_students_title'.tr,
                subtitle: (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? '',
                onBack: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: AppRefresh(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      slivers: [
                        SliverToBoxAdapter(child: _Top(search: _search, course: course)),
                        _StudentsSliver(course: course, onRetry: _load),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero — the class's progress, the screen's one block
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressHero extends StatelessWidget {
  const _ProgressHero();

  /// From this width the two counts sit side by side next to the ring.
  static const double _wide = 520;

  /// The widest one count gets beside the ring on a wide block.
  static const double _countMax = 180;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();
    return AppTilt(
      radius: AppRadius.block,
      child: AppBlock(
        tone: AppBlockTone.peach,
        hero: true,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= _wide;
          final counts = [
            _HeroCount(
              value: p.totalCount,
              label: 'stat_total'.tr,
              icon: Icons.people_alt_rounded,
              memoryKey: 'course_students.total',
            ),
            _HeroCount(
              value: p.completedCount,
              label: 'stat_completed'.tr,
              icon: Icons.task_alt_rounded,
              done: true,
              memoryKey: 'course_students.completed',
            ),
          ];
          return Row(
            children: [
              _ProgressRing(value: p.avgProgress),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: wide
                    ? Wrap(spacing: AppSpace.xxl, runSpacing: AppSpace.md, children: [
                        for (final n in counts) ConstrainedBox(constraints: const BoxConstraints(maxWidth: _countMax), child: n),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [counts[0], const SizedBox(height: AppSpace.md), counts[1]],
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// The average progress: a ring that fills once (and glides on a change) around its rolling figure.
class _ProgressRing extends StatelessWidget {
  final double value; // 0..100

  const _ProgressRing({required this.value});

  /// The ring's side and stroke: the block's focal figure.
  static const double _side = 128;
  static const double _stroke = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final pct = value.clamp(0, 100).toDouble();
    final track = Color.lerp(b.surface, b.ink, 0.1)!;
    // the fill in the block's readable accent ink (a deep emerald is lost on the dark peach)
    final fill = b.accentInk(pct >= 100 ? c.success : c.primary);
    return Semantics(
      label: 'stat_avg_progress'.tr,
      value: '${pct.toStringAsFixed(0)}%',
      child: SizedBox(
        width: _side,
        height: _side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: AppFill(
                value: pct / 100,
                builder: (context, v) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: _stroke,
                  strokeCap: StrokeCap.round,
                  backgroundColor: track,
                  valueColor: AlwaysStoppedAnimation(fill),
                ),
              ),
            ),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AppOdometer(
                        '${pct.toStringAsFixed(0)}%',
                        memoryKey: 'course_students.avg',
                        style: AppType.figureLarge(context).copyWith(color: b.ink),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(
                      'stat_avg_progress'.tr,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(color: b.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One count of the hero: the figure counting up once, its label with a quiet glyph.
class _HeroCount extends StatelessWidget {
  const _HeroCount({required this.value, required this.label, required this.icon, required this.memoryKey, this.done = false});

  final int value;
  final String label;
  final IconData icon;
  final String memoryKey;

  /// "Completed": the glyph in emerald (done), the figure stays ink.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: AppCountUp('$value', memoryKey: memoryKey, style: AppType.figureLarge(context).copyWith(color: b.ink)),
        ),
        const SizedBox(height: AppSpace.xxs),
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: done ? b.accentInk(context.colors.success) : b.muted),
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: b.muted),
            ),
          ),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top — the hero block, search and "send to everyone" (beside the block on wide lists, stacked on phones)
// ─────────────────────────────────────────────────────────────────────────────

/// The top of the list: the hero block, then search and "send to everyone". On a wide list the block keeps a reading
/// width at the start and the tools stand beside it; on narrower ones everything stacks.
class _Top extends StatelessWidget {
  const _Top({required this.search, required this.course});

  final TextEditingController search;
  final TeacherCourse course;

  /// From this width the tools stand beside the block.
  static const double _wide = 1000;

  /// The block's width beside the tools.
  static const double _heroW = 560;

  /// From this width (stacked) the button shares the search's row.
  static const double _row = 720;

  @override
  Widget build(BuildContext context) {
    final field = MySearchBar(
      controller: search,
      hint: 'search_student_by_name_email',
      onChanged: context.read<EnrolledStudentsProvider>().setQuery,
    );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= _wide) {
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xs),
          child: Row(children: [
            const SizedBox(width: _heroW, child: _ProgressHero()),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                field,
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _SendToAllButton(course: course)),
                ),
              ]),
            ),
          ]),
        );
      }
      const hero = Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: _ProgressHero(),
      );
      if (box.maxWidth >= _row) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          hero,
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: field),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.md, bottom: AppSpace.xxs),
              child: _SendToAllButton(course: course),
            ),
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        hero,
        field,
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: _SendToAllButton(course: course, expand: true),
        ),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body — responsive: list on phone widths, grid once there's room (web/tablet).
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsSliver extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onRetry;

  const _StudentsSliver({required this.course, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();

    if (p.isLoading && p.students.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.only(top: AppSpace.sm),
        sliver: SliverToBoxAdapter(child: AppListSkeleton()),
      );
    }

    // A failed first load used to show "no students yet": say it failed and offer a retry.
    if (p.students.isEmpty && p.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorState(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: onRetry),
      );
    }

    if (p.students.isEmpty) {
      final filtered = p.totalCount > 0;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppEmpty(
          icon: filtered ? Icons.search_off_rounded : Icons.people_outline_rounded,
          title: 'no_students'.tr,
          message: 'no_students_hint'.tr,
        ),
      );
    }

    // The list's own width: with the detail panel open beside it the list is narrower than the window.
    MasterDetailScope.maybeOf(context)?.controller.siblings = [
      for (final s in p.students) EntityRef(EntityKind.student, s.id, label: s.name, imageUrl: s.imageUrl),
    ];
    return SliverLayoutBuilder(builder: (context, box) => _grid(context, p, box.crossAxisExtent));
  }

  /// A card's height in the grid at text scale 1 (it grows with the reader's text size).
  static const double _cardH = 112;
  static const double _cardHMax = 156;

  Widget _grid(BuildContext context, EnrolledStudentsProvider p, double width) {
    final columns = width >= 1200 ? 3 : (width >= 760 ? 2 : 1);
    Widget card(int i) => AppReveal(
          index: i,
          group: 'course_students',
          child: _StudentCard(student: p.students[i], course: course),
        );
    const padding = EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl);
    final footer = [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
      SliverToBoxAdapter(child: _LoadMoreFooter(provider: p)),
    ];

    if (columns == 1) {
      return SliverPadding(
        padding: padding,
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverList.separated(
              itemCount: p.students.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
              itemBuilder: (_, i) => card(i),
            ),
            ...footer,
          ],
        ),
      );
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpace.sm,
              crossAxisSpacing: AppSpace.sm,
              // the card's text lines grow with the reader's text size
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(_cardH).clamp(_cardH, _cardHMax),
            ),
            delegate: SliverChildBuilderDelegate((_, i) => card(i), childCount: p.students.length),
          ),
          ...footer,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small footer under the list — a spinner while the next page loads, or a
// quiet "you've reached the end" once the server has nothing more to give.
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreFooter extends StatelessWidget {
  final EnrolledStudentsProvider provider;

  const _LoadMoreFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Center(
          child: SizedBox(
            width: AppIconSize.md,
            height: AppIconSize.md,
            child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: context.colors.primary),
          ),
        ),
      );
    }
    if (!provider.hasMore && provider.students.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Center(child: Text('end_of_list'.tr, style: AppType.meta(context))),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student card — ring-avatar + name/email, compact trailing certificate action.
// ─────────────────────────────────────────────────────────────────────────────

String _formatDate(String raw) {
  try {
    final dt = raw.toLocalSaTime;
    return '${dt.day}/${dt.month}/${dt.year}';
  } catch (_) {
    return raw;
  }
}

class _StudentCard extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;

  const _StudentCard({required this.student, required this.course});

  /// Below this inner width the certificate action is drawn as its glyph alone, so the name keeps its room.
  static const double _compactBelow = 300;

  @override
  Widget build(BuildContext context) {
    final panel = MasterDetailScope.maybeOf(context)?.controller;
    final ref = EntityRef(EntityKind.student, student.id, label: student.name, imageUrl: student.imageUrl);
    if (panel == null) return _card(context, ref, false);
    return ListenableBuilder(listenable: panel, builder: (context, _) => _card(context, ref, panel.selectedId == student.id));
  }

  Widget _card(BuildContext context, EntityRef ref, bool selected) {
    final c = context.colors;
    final tone = _progressColorOf(context, student);
    final meta = AppType.meta(context);
    final radius = AppRadius.cardAll;
    return AppPressScale(
      child: Material(
        color: selected ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? c.primary : c.divider,
            width: selected ? AppBorder.strong : AppBorder.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('md.course_student.${student.id}'),
          onTap: () => EntityNavigator.open(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: LayoutBuilder(builder: (context, box) => Row(
              children: [
                _RingAvatar(student: student, color: tone),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              student.name,
                              style: AppType.bodyStrong(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Text(
                            '${student.progressPercentage.toStringAsFixed(0)}%',
                            style: AppType.label(context).copyWith(
                              fontWeight: FontWeight.w600,
                              color: appInk(context, tone),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xxs / 2),
                      if (student.username != null) AppUsernameLine(student.username, fontSize: meta.fontSize!),
                      Text(student.gmail, style: meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: AppSpace.xxs / 2),
                      Text(
                        '${'joined'.tr} ${_formatDate(student.enrolledAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta.copyWith(color: c.textLight),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                // a narrow card keeps the text and draws the action as its glyph alone
                _CertificateAction(student: student, course: course, compact: box.maxWidth < _compactBelow),
              ],
            )),
          ),
        ),
      ),
    );
  }
}

class _RingAvatar extends StatelessWidget {
  final EnrolledStudent student;
  final Color color;

  const _RingAvatar({required this.student, required this.color});

  /// The ring's side and stroke; the photo sits [_gap] inside it.
  static const double _side = 52;
  static const double _stroke = 3;
  static const double _gap = 5;
  static const double _photo = _side - 2 * _gap;

  // One stable colour per student, from the theme's roles.
  Color _avatarColor(BuildContext context) {
    final c = context.colors;
    final palette = [c.primary, c.success, c.warning, c.accent2, c.purple];
    return palette[student.id % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final url = student.imageUrl;
    return SizedBox(
      width: _side,
      height: _side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AppFill(
              value: student.progressPercentage.clamp(0, 100) / 100,
              builder: (context, v) => CircularProgressIndicator(
                value: v,
                strokeWidth: _stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: context.colors.divider,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          ClipOval(
            child: (url != null && url.isNotEmpty)
                ? Image.network(
                    url,
                    width: _photo,
                    height: _photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initials(context),
                  )
                : _initials(context),
          ),
        ],
      ),
    );
  }

  Widget _initials(BuildContext context) {
    final tone = _avatarColor(context);
    return Container(
      width: _photo,
      height: _photo,
      color: appTintOn(context, tone),
      alignment: Alignment.center,
      child: Text(
        student.initials,
        style: AppType.bodyStrong(context).copyWith(color: appInk(context, tone)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact certificate action — send / sending / sent, with a picker when the
// course has more than one certificate.
// ─────────────────────────────────────────────────────────────────────────────

class _CertificateAction extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;

  const _CertificateAction({required this.student, required this.course, this.compact = false});

  /// The glyph alone in a 48 px target (a narrow card), the label as its tooltip and semantics.
  final bool compact;

  Future<void> _handleTap(BuildContext context) async {
    final provider = context.read<EnrolledStudentsProvider>();
    final target = await _pickCertificate(context, course.certificates);
    if (target == null || !context.mounted) return;

    final success = await provider.sendCertificate(target.id, student.id);
    if (!context.mounted) return;
    _showResultSnack(context, success, 'certificate_sent_success'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final provider = context.watch<EnrolledStudentsProvider>();
    final singleCert = course.certificates.length == 1 ? course.certificates.first : null;
    final isSending = singleCert != null &&
        provider.isSendingCertificate(singleCert.id, student.id);
    final isSent = singleCert != null &&
        provider.isCertificateIssued(singleCert.id, student.id);

    if (isSending) {
      return SizedBox(
        width: AppTouch.min,
        height: AppTouch.min,
        child: Center(
          child: SizedBox(
            width: AppIconSize.md,
            height: AppIconSize.md,
            child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.accent2),
          ),
        ),
      );
    }

    // Always visible, labeled pill. After a send it turns emerald and reads
    // "Resend", but stays tappable so the certificate can go out again.
    final icon = isSent ? Icons.replay_rounded : Icons.workspace_premium_rounded;
    final label = isSent ? 'resend_certificate_btn'.tr : 'send_btn'.tr;
    final tone = isSent ? c.success : c.accent2;
    final onTap = provider.isBulkSending ? null : () => _handleTap(context);
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(icon, size: AppIconSize.md, color: appInk(context, tone)),
      );
    }
    return AppPill(icon: icon, label: label, color: tone, onTap: onTap);
  }
}

/// The certificate picker's rows (a sheet): one 48 px row per certificate, the gold glyph, the title.
class _CertificatePicker extends StatelessWidget {
  final List<CourseCertificate> certificates;

  const _CertificatePicker({required this.certificates});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: 'choose_certificate_title'.tr,
      children: [
        for (final cert in certificates)
          InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: () => Navigator.pop(context, cert),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(children: [
                  Icon(Icons.workspace_premium_rounded, size: AppIconSize.md, color: c.accent2),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(cert.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the only certificate directly, or lets the teacher pick one.
Future<CourseCertificate?> _pickCertificate(
    BuildContext context, List<CourseCertificate> certs) async {
  if (certs.isEmpty) {
    showAppNotice('no_certificate_for_course'.tr, error: true);
    return null;
  }
  if (certs.length == 1) return certs.first;
  return showAppSheet<CourseCertificate>(context, (_) => _CertificatePicker(certificates: certs));
}

void _showResultSnack(BuildContext context, bool success, String okMessage) {
  showAppNotice(success ? okMessage : 'certificate_send_failed'.tr, error: !success);
}

// ─────────────────────────────────────────────────────────────────────────────
// "Send certificate to all students" — one click, with a confirmation step.
// ─────────────────────────────────────────────────────────────────────────────

class _SendToAllButton extends StatelessWidget {
  final TeacherCourse course;
  final bool expand;

  const _SendToAllButton({required this.course, this.expand = false});

  Future<void> _onTap(BuildContext context) async {
    final provider = context.read<EnrolledStudentsProvider>();

    final cert = await _pickCertificate(context, course.certificates);
    if (cert == null || !context.mounted) return;

    final confirmed = await showAppDialog<bool>(
      context,
      title: 'send_to_all_title'.tr,
      icon: Icons.workspace_premium_rounded,
      body: Text('${'send_to_all_confirm'.tr}\n\n${cert.title} · ${provider.totalCount} ${'students'.tr}'),
      actions: [
        Builder(builder: (ctx) => AppButton.ghost(label: 'cancel'.tr, onPressed: () => Navigator.pop(ctx, false))),
        Builder(builder: (ctx) => AppButton.primary(label: 'send_btn'.tr, icon: Icons.send_rounded, onPressed: () => Navigator.pop(ctx, true))),
      ],
    );
    if (confirmed != true || !context.mounted) return;

    final sent = await provider.sendCertificateToAll(cert.id);
    if (!context.mounted) return;
    _showResultSnack(context, sent >= 0, '${'send_to_all_success'.tr} ($sent)');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<EnrolledStudentsProvider>();
    final busy = p.isBulkSending;
    return AppButton.secondary(
      label: busy ? 'sending_label'.tr : 'send_to_all_students_btn'.tr,
      icon: Icons.workspace_premium_rounded,
      busy: busy,
      expand: expand,
      onPressed: p.totalCount == 0 ? null : () => _onTap(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student's certificates — the kit's dialog, opened from the detail panel's
// Certificates action. The dialog lives on the root navigator, so the
// provider is re-supplied.
// ─────────────────────────────────────────────────────────────────────────────

Color _progressColorOf(BuildContext context, EnrolledStudent student) {
  if (student.progressPercentage >= 80) return context.colors.success;
  if (student.progressPercentage >= 40) return context.colors.primary;
  return context.colors.warning;
}

void _showStudentDialog(
    BuildContext context, EnrolledStudent student, TeacherCourse course, Color color) {
  final provider = context.read<EnrolledStudentsProvider>();
  showAppDialog<void>(
    context,
    title: student.name,
    body: ChangeNotifierProvider.value(
      value: provider,
      child: _StudentDetailsBody(student: student, course: course, color: color),
    ),
    actions: [
      Builder(builder: (ctx) => AppButton.ghost(label: 'close'.tr, onPressed: () => Navigator.pop(ctx))),
    ],
  );
}

class _StudentDetailsBody extends StatelessWidget {
  final EnrolledStudent student;
  final TeacherCourse course;
  final Color color;

  const _StudentDetailsBody({
    required this.student,
    required this.course,
    required this.color,
  });

  /// The progress bar's thickness.
  static const double _bar = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final provider = context.watch<EnrolledStudentsProvider>();
    final pct = student.progressPercentage.clamp(0, 100).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          _RingAvatar(student: student, color: color),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'stat_avg_progress'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context),
              ),
              const SizedBox(height: AppSpace.xxs),
              AppCountUp(
                '${pct.toStringAsFixed(0)}%',
                style: AppType.figureLarge(context).copyWith(color: appInk(context, color)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppFill(
          value: pct / 100,
          builder: (context, v) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: v,
              minHeight: _bar,
              backgroundColor: c.inputBg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _InfoRow(icon: Icons.email_outlined, label: 'email'.tr, value: student.gmail),
        _InfoRow(icon: Icons.event_available_outlined, label: 'joined'.tr, value: _formatDate(student.enrolledAt)),
        _InfoRow(icon: Icons.flag_outlined, label: 'status'.tr, value: student.status),
        const SizedBox(height: AppSpace.lg),
        Text('certificates'.tr, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        if (course.certificates.isEmpty)
          Text('no_certificate_for_course'.tr, style: AppType.meta(context))
        else
          for (final cert in course.certificates)
            _CertificateRow(cert: cert, student: student, provider: provider),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Text(label, style: AppType.meta(context)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.row(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One certificate inside the dialog: title, "sent N×" info, and a
/// send / resend button (always enabled, so it can be sent again).
class _CertificateRow extends StatelessWidget {
  final CourseCertificate cert;
  final EnrolledStudent student;
  final EnrolledStudentsProvider provider;

  const _CertificateRow({
    required this.cert,
    required this.student,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = provider.issuedCount(cert.id, student.id);
    final sending = provider.isSendingCertificate(cert.id, student.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, size: AppIconSize.md, color: c.accent2),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cert.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                if (count > 0)
                  Text(
                    '${'certificate_sent_label'.tr} · $count×',
                    style: AppType.meta(context).copyWith(color: appInk(context, c.success)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: AppButton.ghost(
              label: count > 0 ? 'resend_certificate_btn'.tr : 'send_certificate_btn'.tr,
              icon: count > 0 ? Icons.replay_rounded : Icons.send_rounded,
              size: AppButtonSize.sm,
              busy: sending,
              onPressed: provider.isBulkSending
                  ? null
                  : () async {
                      final ok = await provider.sendCertificate(cert.id, student.id);
                      if (!context.mounted) return;
                      _showResultSnack(context, ok, 'certificate_sent_success'.tr);
                    },
            ),
          ),
        ],
      ),
    );
  }
}
