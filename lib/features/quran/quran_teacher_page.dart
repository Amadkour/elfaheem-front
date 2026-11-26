// lib/features/quran/quran_teacher_page.dart — one Quran teacher's card (Learning Hub Phase 6, D-1347):
// GET /api/v1/quran/teachers/{id}. Their programs ARE courses: "Book" opens the course page (AppNavigator.openCourse
// → CourseLinkLoader), whose existing enrol / checkout books it; no payment code here. A refusal there (403
// `quran_gender_rule`, `quran_teacher_unverified`) is drawn by apiErrorText.
//
//   QuranTeacherPage   loads the card (the list's copy shows at once)
//   QuranTeacherView   plain values (test/ui/quran_layout_test.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/home/student/models.dart' show AppCurrencyX;
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/teachers/teacher_discovery.dart' show TeacherProfilePage;
import 'package:flutter_education_app/features/teachers/teachers_api.dart' show teacherDiscoveryOff;
import 'package:flutter_education_app/features/teachers/teachers_parts.dart' show packagesText, teacherInitialName;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// One teacher identity (D-1664): a Quran teacher's Learning Hub v2 packages are shown and linked from the Quran
/// card and page while teacher discovery is on and some are published.
bool quranShowsPackages(QuranTeacher t) => t.packagesCount > 0 && !teacherDiscoveryOff();

class QuranTeacherPage extends StatefulWidget {
  const QuranTeacherPage({super.key, required this.teacherId, this.initial, this.api});

  final int teacherId;
  final QuranTeacher? initial;
  final QuranApi? api;

  @override
  State<QuranTeacherPage> createState() => _QuranTeacherPageState();
}

class _QuranTeacherPageState extends State<QuranTeacherPage> {
  late final QuranApi _api = widget.api ?? QuranApi();
  late QuranTeacher? _teacher = widget.initial;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
        _teacher = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_teacher == null) {
          _error = quranErrorText(e);
        } else {
          showAppNotice(quranErrorText(e), error: true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = _teacher;
    return SdArea(area: AppArea.quran, child: BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('معلم القرآن', 'Quran teacher')),
      child: SafeArea(
        child: tr == null
            ? (_loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load))
            : QuranTeacherView(
                teacher: tr,
                // the single card carries no `gender_ok`: the list's answer stands
                genderOk: widget.initial?.genderOk ?? tr.genderOk,
                onBook: (c) => AppNavigator.openCourse(c.id),
                onPackages: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: RouteSettings(name: '/teachers/${tr.userId}'),
                  builder: (_) => TeacherProfilePage(teacherId: tr.userId),
                )),
                onRefresh: _load,
              ),
      ),
    ));
  }
}

class QuranTeacherView extends StatelessWidget {
  const QuranTeacherView({super.key, required this.teacher, this.genderOk, this.onBook, this.onPackages, this.onRefresh});

  final QuranTeacher teacher;
  final bool? genderOk;
  final ValueChanged<QuranCourse>? onBook;

  /// Opens the teacher's profile with the packages (D-1664).
  final VoidCallback? onPackages;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tr = teacher;
    final blocked = genderOk == false;
    final children = <Widget>[
      AppBlock(
        tone: AppBlockTone.emerald,
        hero: true,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            AppAvatar(name: teacherInitialName(tr.name), url: tr.avatarUrl, size: AppTouch.primary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tr.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
                const SizedBox(height: AppSpace.xxs),
                Text(quranGenderLabel(tr.gender), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
                if (tr.verified) ...[
                  const SizedBox(height: AppSpace.xs),
                  AppStatusBadge(label: t('موثّق من المنصة', 'Verified by the platform'), tone: AppTone.success, icon: Icons.verified_rounded, dense: true),
                ],
              ]),
            ),
          ]);
        }),
      ),
      if (blocked) ...[
        const SizedBox(height: AppSpace.md),
        AppBanner(
          icon: Icons.info_outline_rounded,
          color: c.warning,
          text: t('الحجز مع هذا المعلم غير متاح لك: البرنامج يشترط أن يكون المعلم من نفس جنس الطالب.',
              'Booking with this teacher is not open to you: the program needs a teacher of the student\'s gender.'),
        ),
      ],
      AppSection(
        title: t('عن المعلم', 'About'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if ((tr.ijazah ?? '').isNotEmpty) ...[
            AppInfoRow(Icons.workspace_premium_rounded, '${t('الإجازة', 'Ijazah')}: ${tr.ijazah!}'),
            const SizedBox(height: AppSpace.xs),
          ],
          if (tr.bio.trim().isNotEmpty)
            Text(tr.bio, style: AppType.body(context).copyWith(color: c.textDark))
          else
            Text(t('لم يكتب المعلم نبذة بعد.', 'The teacher has not written an introduction yet.'),
                style: AppType.body(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final g in tr.goals) AppStatusBadge(label: quranGoalLabel(g), tone: AppTone.brand, dense: true),
            for (final s in tr.sessionTypes) AppStatusBadge(label: quranSessionLabel(s), icon: Icons.groups_rounded, dense: true),
          ]),
        ]),
      ),
      if (quranShowsPackages(tr))
        AppSection(
          title: t('الباقات', 'Packages'),
          child: AppActionCard(
            key: const ValueKey('quran.teacher.see_packages'),
            icon: Icons.inventory_2_outlined,
            title: '${t('اعرض الباقات', 'See the packages')} · ${packagesText(tr.packagesCount)}',
            subtitle: t('جلسات بمواعيد ومقاعد وسعر: انضم من صفحة المعلم.',
                "Sessions with set times, seats and a price: join from the teacher's page."),
            onTap: onPackages,
          ),
        ),
      if (tr.courses.isNotEmpty || !quranShowsPackages(tr))
      AppSection(
        title: t('البرامج', 'Programs'),
        subtitle: t('كل برنامج دورة: احجزه من صفحتها.', 'Each program is a course: book it from its page.'),
        child: tr.courses.isEmpty
            ? AppEmpty(
                icon: Icons.event_busy_rounded,
                title: t('لا برامج متاحة الآن', 'No programs open now'),
                message: t('عد لاحقاً، فالمعلم يفتح برامج جديدة.', 'Come back later: the teacher opens new programs.'),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final p in tr.courses) ...[
                  _ProgramRow(course: p, blocked: blocked, onBook: onBook == null ? null : () => onBook!(p)),
                  const SizedBox(height: AppSpace.sm),
                ],
              ]),
      ),
      const SizedBox(height: AppSpace.lg),
    ];
    // The body is its own semantics container with explicit child nodes, so a screen reader reaches every row and
    // the Book buttons (QA_PHASE6 4.4: on the web the body was missing from the tree).
    final list = Semantics(
      container: true,
      explicitChildNodes: true,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: children),
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({required this.course, required this.blocked, this.onBook});

  final QuranCourse course;
  final bool blocked;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final price = coursePriceLabel(AppCurrencyX.fromCode(course.currency), course.fees);
    final how = switch (course.deliveryMode) {
      'in_person' => t('حضوري', 'In person'),
      'both' => t('أونلاين وحضوري', 'Online and in person'),
      _ => t('أونلاين', 'Online'),
    };
    return AppCard(
      key: ValueKey('quran.program.${course.id}'),
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: AppTouch.min * 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              const SizedBox(height: AppSpace.xxs),
              Text('$price · $how', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
          AppButton(
            key: ValueKey('quran.book.${course.id}'),
            tooltip: blocked ? t('غير متاح لك', 'Not open to you') : '${t('احجز', 'Book')}: ${course.name}',
            label: t('احجز', 'Book'),
            icon: Icons.event_available_rounded,
            size: AppButtonSize.sm,
            onPressed: blocked ? null : onBook,
          ),
        ],
      ),
    );
  }
}
