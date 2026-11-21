// lib/features/nahw/nahw_lesson_page.dart — one nahw lesson (D-1349): the reading text, then its exercises one at a
// time with instant feedback (graded on the device: the lesson carries the answers), then the result, which is
// saved as ONE attempt with a `client_id` kept until the server answers (a retry is the same attempt).
//
//   NahwLessonPage     loads GET /api/v1/nahw/lessons/{id}, runs the round, posts the attempt
//   NahwReadingView    the lesson text + "Start the exercises" (plain values)
//   NahwRoundView      one exercise with its progress strip, Check, and the feedback panel (plain values)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'nahw_api.dart';
import 'nahw_exercise_view.dart';
import 'nahw_models.dart';

/// Bumped after a saved attempt so the levels list reloads its progress.
class NahwBus {
  NahwBus._();
  static final revision = ValueNotifier<int>(0);
}

String nahwExercisesText(int n) => countText(n,
    ar1: 'تمرين واحد', ar2: 'تمرينان', arFew: '$n تمارين', arMany: '$n تمريناً', en1: '1 exercise', en: '$n exercises');

enum _Phase { reading, round, result }

class NahwLessonPage extends StatefulWidget {
  const NahwLessonPage({super.key, required this.lessonId, this.title = '', this.api});

  final int lessonId;
  final String title;
  final NahwApi? api;

  @override
  State<NahwLessonPage> createState() => _NahwLessonPageState();
}

class _NahwLessonPageState extends State<NahwLessonPage> {
  late final NahwApi _api = widget.api ?? NahwApi();
  NahwLesson? _lesson;
  String? _error;

  _Phase _phase = _Phase.reading;
  int _index = 0;
  NahwResponse _response = const NahwResponse();
  bool _checked = false;
  int _score = 0;
  final List<Object?> _answers = [];

  String? _clientId;
  bool _saving = false;
  String? _saveError;
  NahwProgress? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _api.lesson(widget.lessonId);
      if (mounted) setState(() => _lesson = l);
    } catch (e) {
      if (mounted) setState(() => _error = nahwErrorText(e));
    }
  }

  void _start() => setState(() {
        _phase = _Phase.round;
        _index = 0;
        _score = 0;
        _answers.clear();
        _response = const NahwResponse();
        _checked = false;
        _saveError = null;
        _saved = null;
        _clientId = null;
      });

  void _check() {
    final e = _lesson!.exercises[_index];
    final g = nahwGrade(e, _response);
    setState(() {
      _checked = true;
      _score += g.score;
      _answers.add(_response.toJson(e));
    });
  }

  void _next() {
    final l = _lesson!;
    if (_index + 1 >= l.exercises.length) {
      setState(() => _phase = _Phase.result);
      _save();
      return;
    }
    setState(() {
      _index++;
      _response = const NahwResponse();
      _checked = false;
    });
  }

  Future<void> _save() async {
    final l = _lesson!;
    _clientId ??= nahwClientId();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final r = await _api.attempt(l.id, clientId: _clientId!, score: _score, maxScore: l.maxScore, answers: [..._answers]);
      _clientId = null;
      NahwBus.revision.value++;
      if (mounted) {
        setState(() {
          _saving = false;
          _saved = r.progress;
        });
      }
    } catch (e) {
      if (nahwDefiniteAnswer(e)) _clientId = null;
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = nahwErrorText(e);
        });
      }
    }
  }

  Future<bool> _leaveOk() async {
    if (_phase != _Phase.round || _index == 0 && !_checked) return true;
    return appConfirm(context,
        message: t('ستضيع إجاباتك في هذه الجولة. هل تريد الخروج؟', 'Your answers in this round will be lost. Leave?'),
        confirmLabel: t('خروج', 'Leave'));
  }

  @override
  Widget build(BuildContext context) {
    final l = _lesson;
    final Widget body;
    if (l == null) {
      body = _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : const Padding(padding: AppSpace.card, child: AppListSkeleton(items: 4));
    } else if (_phase == _Phase.reading) {
      body = NahwReadingView(lesson: l, onStart: l.exercises.isEmpty ? null : _start);
    } else if (_phase == _Phase.round) {
      body = NahwRoundView(
        exercise: l.exercises[_index],
        index: _index,
        total: l.exercises.length,
        score: _score,
        response: _response,
        checked: _checked,
        onChanged: (r) => setState(() => _response = r),
        onCheck: _check,
        onNext: _next,
      );
    } else {
      final best = _saved;
      body = ListView(padding: AppSpace.card, children: [
        LearnResultView(
          score: _score,
          max: l.maxScore,
          saving: _saving,
          saveError: _saveError,
          onRetrySave: _save,
          note: best == null
              ? null
              : best.completed
                  ? t('أتممت الدرس · أفضل نتيجة ${best.percent}%', 'Lesson complete · best ${best.percent}%')
                  : t('يكتمل الدرس عند 60% · أفضل نتيجة ${best.percent}%', 'The lesson completes at 60% · best ${best.percent}%'),
          onReplay: _saving ? null : _start,
          onDone: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
      ]);
    }
    return PopScope(
      canPop: _phase != _Phase.round,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _leaveOk() && mounted) nav.pop();
      },
      child: BasePage(
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: l?.title ?? widget.title),
        child: SafeArea(child: body),
      ),
    );
  }
}

class NahwReadingView extends StatelessWidget {
  const NahwReadingView({super.key, required this.lesson, this.onStart});

  final NahwLesson lesson;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final p = lesson.progress;
    return ListView(padding: AppSpace.card, children: [
      AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(lesson.title, style: AppType.pageTitle(context)),
          if (p != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(
              p.completed
                  ? t('أتممته · أفضل نتيجة ${p.percent}%', 'Completed · best ${p.percent}%')
                  : t('أفضل نتيجة ${p.percent}% · ${p.attempts} محاولة', 'Best ${p.percent}% · ${p.attempts} attempts'),
              style: AppType.meta(context),
            ),
          ],
          AppSpace.gapMd,
          // the lesson text is Arabic (the subject is Arabic grammar): always right to left
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(lesson.bodyAr, style: AppType.body(context).copyWith(height: 1.8, color: context.colors.textDark)),
          ),
        ]),
      ),
      AppSpace.gapMd,
      AppButton.primary(
        key: const ValueKey('nahw.start'),
        label: onStart == null
            ? t('لا توجد تمارين بعد', 'No exercises yet')
            : t('ابدأ التمارين (${nahwExercisesText(lesson.exercises.length)})',
                'Start the exercises (${nahwExercisesText(lesson.exercises.length)})'),
        icon: Icons.play_arrow_rounded,
        expand: true,
        onPressed: onStart,
      ),
    ]);
  }
}

class NahwRoundView extends StatelessWidget {
  const NahwRoundView({
    super.key,
    required this.exercise,
    required this.index,
    required this.total,
    required this.response,
    required this.onChanged,
    this.score = 0,
    this.checked = false,
    this.onCheck,
    this.onNext,
  });

  final NahwExercise exercise;
  final int index;
  final int total;
  final int score;
  final NahwResponse response;
  final bool checked;
  final ValueChanged<NahwResponse> onChanged;
  final VoidCallback? onCheck;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final g = checked ? nahwGrade(exercise, response) : null;
    final last = index + 1 >= total;
    return ListView(padding: AppSpace.card, children: [
      LearnProgressHeader(current: index + 1, total: total, score: score),
      AppSpace.gapMd,
      NahwExerciseView(exercise: exercise, response: response, checked: checked, onChanged: onChanged),
      AppSpace.gapMd,
      if (g == null)
        AppButton.primary(
          key: const ValueKey('nahw.check'),
          label: t('تحقّق', 'Check'),
          icon: Icons.check_rounded,
          expand: true,
          onPressed: response.complete(exercise) ? onCheck : null,
        )
      else
        LearnFeedback(
          key: const ValueKey('nahw.feedback'),
          correct: g.correct,
          title: g.correct || exercise.kind != 'classify' || g.score == 0 ? null : nahwPartText(g),
          explanation: exercise.explanation,
          actionLabel: last ? t('النتيجة', 'See the result') : t('التالي', 'Next'),
          onAction: onNext,
        ),
    ]);
  }
}
