// lib/features/courses/course_space/subject_lesson_panel.dart
//
// The lesson panel of the subject page (SubjectProfile panel=lesson, rows 5-8): opened from a recorded step with
// `showSubjectPanel(…, wide: true)`. Tabs فيديو / الكتاب / ملخصات / تمارين over the session's real materials; a tab
// with nothing in it is not drawn. Video: a preview that opens the one player (VideoPlayerScreen) with the lesson's
// videos as the playlist, and the videos as chapters. الكتاب and ملخصات: the session's own material grid (the same
// tiles, completion marks and protected play as the sessions timeline). تمارين: the exams that gate the lesson.
// Footer: the one forward button — "حل التمارين", then "خلّصت الدرس، كمّل للي بعده".
//
// Reads TeacherCourseScreenProvider (materials) from its context: the caller re-provides it into the sheet route.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space_parts.dart';
import 'package:flutter_education_app/features/courses/student/details/session_exam_gate.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherSessionItem;
import 'package:flutter_education_app/features/sessions/material/components/session_material_grid.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/video/video_player_screen.dart';

enum SubjectLessonTab { video, book, imgs, quiz }

/// Which tab a material belongs to (null: none of them — a live recording still being made).
SubjectLessonTab? subjectLessonTabOf(SessionMaterialType t) => switch (t) {
      SessionMaterialType.video || SessionMaterialType.recorded => SubjectLessonTab.video,
      SessionMaterialType.pdf || SessionMaterialType.document || SessionMaterialType.link => SubjectLessonTab.book,
      SessionMaterialType.image => SubjectLessonTab.imgs,
      SessionMaterialType.recording => null,
    };

class SubjectLessonPanel extends StatefulWidget {
  const SubjectLessonPanel({
    super.key,
    required this.session,
    this.gate,
    this.onOpenExam,
    this.onNext,
    this.initialTab,
  });

  final TeacherSessionItem session;

  /// The exams that gate this lesson (null / empty: no تمارين tab).
  final SessionExamGate? gate;
  final Future<void> Function(int examId)? onOpenExam;

  /// "خلّصت الدرس، كمّل للي بعده": the next lesson (null: the panel just closes).
  final VoidCallback? onNext;
  final SubjectLessonTab? initialTab;

  @override
  State<SubjectLessonPanel> createState() => _SubjectLessonPanelState();
}

class _SubjectLessonPanelState extends State<SubjectLessonPanel> {
  SubjectLessonTab? _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherCourseScreenProvider>().fetchMaterials(widget.session);
    });
  }

  List<SubjectLessonTab> _tabs(List<SessionMaterialModel> all) => [
        for (final t in SubjectLessonTab.values)
          if (t == SubjectLessonTab.quiz ? !(widget.gate?.isEmpty ?? true) : all.any((m) => subjectLessonTabOf(m.type) == t)) t,
      ];

  static String _label(SubjectLessonTab t) => switch (t) {
        SubjectLessonTab.video => 'sb_lesson_tab_video'.tr,
        SubjectLessonTab.book => 'sb_lesson_tab_book'.tr,
        SubjectLessonTab.imgs => 'sb_lesson_tab_imgs'.tr,
        SubjectLessonTab.quiz => 'sb_lesson_tab_quiz'.tr,
      };

  void _play(SessionMaterialModel m, List<SessionMaterialModel> videos) {
    if (!m.requiresPlay && (m.urlLow == null || m.urlLow!.isEmpty)) {
      showAppNotice('video_not_available'.tr, error: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(autoPlay: true, material: m, playlist: videos),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TeacherCourseScreenProvider>();
    final all = prov.materialsFor(widget.session.id);
    final loaded = prov.materialLoaded[widget.session.id] ?? false;
    final tabs = _tabs(all);
    final tab = tabs.contains(_tab) ? _tab! : (tabs.isEmpty ? null : tabs.first);
    final hasQuiz = tabs.contains(SubjectLessonTab.quiz);

    final Widget body;
    if (!loaded && all.isEmpty) {
      body = const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 3));
    } else if (tab == null) {
      body = AppEmpty(icon: Icons.menu_book_outlined, title: 'sb_lesson_empty'.tr);
    } else {
      body = ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          if (tabs.length > 1) ...[
            AppTabs(
              items: [for (final t in tabs) AppTabItem(_label(t))],
              index: tabs.indexOf(tab),
              expand: true,
              onChanged: (i) => setState(() => _tab = tabs[i]),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          AppWipeSwitcher(switchKey: tab, child: _content(context, tab, all)),
        ],
      );
    }
    final onQuiz = tab == SubjectLessonTab.quiz || !hasQuiz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        if (tab != null)
          SubjectPanelFooter(children: [
            Expanded(
              child: AppButton.hot(
                label: onQuiz ? 'sb_lesson_next'.tr : 'sb_lesson_solve'.tr,
                expand: true,
                size: AppButtonSize.lg,
                onPressed: onQuiz
                    ? () {
                        Navigator.of(context).maybePop();
                        widget.onNext?.call();
                      }
                    : () => setState(() => _tab = SubjectLessonTab.quiz),
              ),
            ),
          ]),
      ],
    );
  }

  Widget _content(BuildContext context, SubjectLessonTab tab, List<SessionMaterialModel> all) {
    final of = [for (final m in all) if (subjectLessonTabOf(m.type) == tab) m];
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    switch (tab) {
      case SubjectLessonTab.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubjectVideoPreview(
              title: of.first.name,
              minutes: ((of.first.durationSeconds ?? 0) / 60).round(),
              onPlay: () => _play(of.first, of),
            ),
            for (final (i, m) in of.indexed) ...[
              const SizedBox(height: AppSpace.sm),
              AppFlipIn(
                index: i,
                group: 'lesson_chapters',
                child: AppTile(
                  dense: true,
                  leading: _Num(i + 1),
                  title: m.name,
                  trailing: (m.durationSeconds ?? 0) > 0
                      ? Text(sbMinutes(((m.durationSeconds ?? 0) / 60).ceil()), style: AppType.meta(context))
                      : null,
                  selected: i == 0,
                  onTap: () => _play(m, of),
                ),
              ),
            ],
          ],
        );
      case SubjectLessonTab.book:
      case SubjectLessonTab.imgs:
        return SessionMaterialGrid(
          session: widget.session,
          materials: of,
          columns: wide ? 3 : 2,
          isTeacher: false,
          isLoading: false,
        );
      case SubjectLessonTab.quiz:
        final exams = widget.gate?.exams ?? const <SessionExamInfo>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, e) in exams.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpace.sm),
              AppTile(
                icon: e.passed ? Icons.verified_rounded : Icons.quiz_outlined,
                tone: e.passed ? context.colors.kit.ok : context.colors.kit.accent(AppAccent.grape),
                title: e.name,
                subtitle: [
                  if (e.questionCount > 0) sbQuestions(e.questionCount),
                  if ((e.duration ?? 0) > 0) sbMinutes(e.duration!),
                ].join('، '),
                trailing: e.passed
                    ? AppStatusBadge(label: 'sb_subj_done'.tr, tone: AppTone.success, icon: Icons.check_rounded)
                    : Icon(Icons.chevron_right_rounded, color: context.colors.textLight),
                onTap: e.canStart && widget.onOpenExam != null ? () => widget.onOpenExam!(e.id) : null,
              ),
            ],
          ],
        );
    }
  }
}

class _Num extends StatelessWidget {
  const _Num(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return Container(
      width: AppIconSize.xl,
      height: AppIconSize.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: set.tint, shape: BoxShape.circle),
      child: Text(sbDigits(n), style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600)),
    );
  }
}

/// The lesson's video as a still: the learn area's gradient, a round play button, the length. Tap plays it in the
/// one player.
class SubjectVideoPreview extends StatelessWidget {
  const SubjectVideoPreview({super.key, required this.title, required this.onPlay, this.minutes = 0});

  final String title;
  final int minutes;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: title,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: AppHeroSurface(
          shapes: false,
          borderRadius: BorderRadius.circular(AppRadius.cardWide),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPlay,
              child: Stack(children: [
                PositionedDirectional(
                  start: AppSpace.md,
                  top: AppSpace.md,
                  end: AppSpace.md,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppType.section(context).copyWith(color: c.onHero)),
                ),
                Center(
                  child: Container(
                    width: AppSpace.xxxl,
                    height: AppSpace.xxxl,
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.heroGlassBorder, width: AppSpace.xs),
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: c.kit.live.color, size: AppIconSize.xl),
                  ),
                ),
                if (minutes > 0)
                  PositionedDirectional(
                    end: AppSpace.md,
                    bottom: AppSpace.md,
                    child: Text(sbMinutes(minutes), style: AppType.label(context).copyWith(color: c.onHero)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
