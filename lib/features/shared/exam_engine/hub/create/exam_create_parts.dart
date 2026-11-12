// The "New exam" wizard's presentational parts, plain values only (the layout harness pumps them): the shell (a summary
// rail on a wide window, a compact progress header on a phone) and the body of each step that is not an existing kit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_all.dart' show NewExamPlace;
import '../../paper/exam_setup.dart' show OmrTemplateItem, versionsBubbleText;
import '../../paper/exam_setup_wizard.dart' show SetupChoiceTile, SetupProgress;
import 'exam_create_logic.dart';

/// From this width the summary is a rail beside the step.
const createRailFrom = 960.0;
const _bodyMax = 720.0;
const _railWidth = 300.0;

enum CreateItemState { done, current, todo }

/// One step in the summary: what it is, what was chosen, and how to go back to it.
class CreateSummaryItem {
  const CreateSummaryItem({required this.label, this.value, required this.state, this.onTap, this.locked = false});
  final String label;
  final String? value;
  final CreateItemState state;

  /// null = cannot be opened yet.
  final VoidCallback? onTap;

  /// Fixed since the draft exists (the place of an exam).
  final bool locked;
}

class ExamCreateShell extends StatelessWidget {
  const ExamCreateShell({
    super.key,
    required this.stepKey,
    required this.items,
    required this.index,
    required this.stepLabel,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.backLabel,
    required this.onBack,
    required this.onClose,
    this.subtitle,
    this.error,
    this.hint,
    this.busy = false,
    this.primaryIcon,
    this.estimate = const [],
  });

  /// Changes with the step: the page fades and starts at the top.
  final Object stepKey;
  final List<CreateSummaryItem> items;
  final int index;
  final String stepLabel;
  final String title;
  final String? subtitle;
  final String? error;

  /// Why the primary action is not available yet.
  final String? hint;
  final Widget body;
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final bool busy;
  final String backLabel;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  final List<(String, String)> estimate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= createRailFrom;
        final main = _main(context, wide);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: _railWidth, child: _Rail(items: items, estimate: estimate, onClose: onClose)),
            Expanded(child: main),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PhoneHeader(items: items, index: index, stepLabel: stepLabel, onClose: onClose),
          Expanded(child: main),
        ]);
      }),
    );
  }

  Widget _main(BuildContext context, bool wide) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    Widget column(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _bodyMax), child: child));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: AnimatedSwitcher(
          duration: motion.base,
          switchInCurve: AppMotion.curve,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
          child: SingleChildScrollView(
            key: ValueKey(stepKey),
            padding: EdgeInsets.symmetric(horizontal: wide ? AppSpace.xl : AppSpace.md, vertical: wide ? AppSpace.xl : AppSpace.md),
            child: column(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: wide ? AppType.headline(context) : AppType.pageTitle(context)),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(subtitle!, style: AppType.body(context).copyWith(height: 1.45)),
              ],
              SizedBox(height: wide ? AppSpace.lg : AppSpace.md),
              if (error != null) ...[
                AppBanner(key: const ValueKey('create.error'), icon: Icons.error_outline_rounded, color: c.danger, text: error!),
                const SizedBox(height: AppSpace.md),
              ],
              body,
            ])),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? AppSpace.xl : AppSpace.md, vertical: AppSpace.sm),
            child: column(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (hint != null) ...[
                Text(hint!, key: const ValueKey('create.hint'), textAlign: TextAlign.center, style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xs),
              ],
              Row(children: [
                AppButton.ghost(key: const ValueKey('create.back'), label: backLabel, onPressed: onBack),
                AppSpace.gapSm,
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('create.primary'),
                    child: AppButton.primary(label: primaryLabel, icon: primaryIcon, busy: busy, expand: true, onPressed: onPrimary),
                  ),
                ),
              ]),
            ])),
          ),
        ),
      ),
    ]);
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.items, required this.estimate, required this.onClose});
  final List<CreateSummaryItem> items;
  final List<(String, String)> estimate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: BorderDirectional(end: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AppAccentStrip(),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.md, AppSpace.xs, AppSpace.sm),
            child: Row(children: [
              Expanded(child: Text(t('اختبار جديد', 'New exam'), style: AppType.pageTitle(context))),
              IconButton(key: const ValueKey('create.close'), tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.close_rounded, color: c.textMedium)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm), children: [
              for (var i = 0; i < items.length; i++) _RailRow(item: items[i], number: i + 1, last: i == items.length - 1),
            ]),
          ),
          if (estimate.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              // what the exam will come to, as it is planned: an information (sky) block
              child: AppBlock(
                key: const ValueKey('create.estimate'),
                tone: AppBlockTone.sky,
                padding: const EdgeInsets.all(AppSpace.md),
                child: Builder(builder: (context) {
                  final b = AppBlock.colorsOf(context);
                  return Column(children: [
                    for (var i = 0; i < estimate.length; i++) ...[
                      if (i > 0) AppSpace.gapXs,
                      Row(children: [
                        Expanded(child: Text(estimate[i].$1, style: AppType.meta(context).copyWith(color: b.muted))),
                        Text(estimate[i].$2, style: AppType.figure(context).copyWith(color: b.ink)),
                      ]),
                    ],
                  ]);
                }),
              ),
            ),
        ]),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({required this.item, required this.number, required this.last});
  final CreateSummaryItem item;
  final int number;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = item.state == CreateItemState.current;
    final done = item.state == CreateItemState.done;
    final dot = Container(
      width: AppIconSize.lg,
      height: AppIconSize.lg,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || current ? c.primary : null,
        border: done || current ? null : Border.all(color: c.divider, width: AppBorder.strong),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero)
          : Text('$number', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: current ? c.onHero : c.textMedium)),
    );
    return Semantics(
      button: item.onTap != null,
      selected: current,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: AppIconSize.hero,
              child: Column(children: [
                const SizedBox(height: AppSpace.xs),
                dot,
                if (!last) Expanded(child: Center(child: Container(width: AppBorder.strong, color: done ? c.primary.withValues(alpha: .5) : c.divider))),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpace.sm, bottom: AppSpace.md, end: AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.label, style: AppType.row(context).copyWith(fontWeight: current ? FontWeight.w700 : FontWeight.w500, color: item.state == CreateItemState.todo ? c.textMedium : c.textDark)),
                  if (item.value != null) ...[
                    const SizedBox(height: 2),
                    Text(item.value!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(height: 1.35)),
                  ],
                ]),
              ),
            ),
            if (item.locked)
              Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Icon(Icons.lock_outline_rounded, size: AppIconSize.xs, color: c.textLight))
            else if (item.onTap != null && done)
              Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Icon(Icons.edit_outlined, size: AppIconSize.xs, color: c.textLight)),
          ]),
        ),
      ),
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.items, required this.index, required this.stepLabel, required this.onClose});
  final List<CreateSummaryItem> items;
  final int index;
  final String stepLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chips = [for (final x in items) if (x.value != null && x.state == CreateItemState.done) x];
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xxs, 0),
              child: Row(children: [
                Expanded(child: SetupProgress(index: index, total: items.length, label: stepLabel)),
                IconButton(key: const ValueKey('create.close'), tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.close_rounded, color: c.textMedium)),
              ]),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpace.xs),
                    _SummaryChip(item: chips[i]),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.item});
  final CreateSummaryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: item.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _chipMax, minHeight: AppSpace.xl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(item.value!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary)))),
              if (item.onTap != null) ...[
                const SizedBox(width: AppSpace.xxs),
                Icon(item.locked ? Icons.lock_outline_rounded : Icons.edit_outlined, size: AppIconSize.xs, color: appInk(context, c.primary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Recommended", beside a choice.
class CreateRecommended extends StatelessWidget {
  const CreateRecommended({super.key});

  @override
  Widget build(BuildContext context) => AppBadgePill(t('موصى به', 'Recommended'), color: context.colors.success);
}

/// A choice that cannot be taken now, with the reason in its own line.
class _Muted extends StatelessWidget {
  const _Muted({required this.off, required this.child});
  final bool off;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(opacity: off ? .55 : 1, child: child);
}

const _gap = SizedBox(height: AppSpace.sm);

/// The widest a done step's summary chip grows in the phone header.
const _chipMax = 200.0;

// ═══════════════════════════════════════ where ═════════════════════════════════════════════════════════════════

class CreateWhereBody extends StatefulWidget {
  const CreateWhereBody({super.key, required this.places, required this.selected, required this.onPick, this.orgNames = const {}});

  /// null = loading.
  final List<NewExamPlace>? places;
  final NewExamPlace? selected;
  final ValueChanged<NewExamPlace> onPick;
  final Map<int, String> orgNames;

  @override
  State<CreateWhereBody> createState() => _CreateWhereBodyState();
}

class _CreateWhereBodyState extends State<CreateWhereBody> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.places;
    if (all == null) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? all : [for (final p in all) if (p.name.toLowerCase().contains(q) || p.courseId == null) p];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (all.length > 8) ...[
        AppSearchField(hint: t('ابحث عن مقرر', 'Search for a course'), onChanged: (v) => setState(() => _q = v)),
        _gap,
      ],
      for (final p in list) ...[
        SetupChoiceTile(
          key: ValueKey('create.place.${p.courseId}.${p.orgId}'),
          icon: p.courseId != null ? Icons.menu_book_rounded : (p.orgId != null ? Icons.apartment_rounded : Icons.person_outline_rounded),
          title: p.name,
          subtitle: _sub(p),
          selected: widget.selected == p,
          onTap: () => widget.onPick(p),
        ),
        _gap,
      ],
    ]);
  }

  String? _sub(NewExamPlace p) {
    if (p.courseId != null) return p.orgId == null ? null : widget.orgNames[p.orgId];
    if (p.orgId != null) return t('اختبار على مستوى المؤسسة، بدون مقرر', 'An organization exam, without a course');
    return t('لا طلاب مرتبطون به، ولا أسئلة تلقائية', 'No students linked to it, and no automatic questions');
  }
}

// ═══════════════════════════════════════ answers ═══════════════════════════════════════════════════════════════

IconData answerFormatIcon(AnswerFormat f) => switch (f) {
      AnswerFormat.online => Icons.devices_rounded,
      AnswerFormat.onPaper => Icons.description_outlined,
      AnswerFormat.table => Icons.table_chart_outlined,
      AnswerFormat.bubble => Icons.grid_on_rounded,
    };

/// "How will students answer?": one card per format, the last one used marked (D-661).
class CreateAnswerBody extends StatelessWidget {
  const CreateAnswerBody({super.key, required this.formats, required this.value, required this.onPick, this.lastUsed});
  final List<AnswerFormat> formats;
  final AnswerFormat? value;
  final ValueChanged<AnswerFormat> onPick;

  /// The format of this teacher's previous exam: preselected, and said so while it is the one chosen.
  final AnswerFormat? lastUsed;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < formats.length; i++) ...[
          if (i > 0) _gap,
          SetupChoiceTile(
            key: ValueKey('create.answer.${answerFormatKey(formats[i])}'),
            icon: answerFormatIcon(formats[i]),
            title: answerFormatLabel(formats[i]),
            subtitle: answerFormatHint(formats[i]),
            selected: value == formats[i],
            badge: formats[i] == lastUsed
                ? AppBadgePill(t('آخر اختيار', 'Last used'), color: context.colors.primary)
                : (lastUsed == null && formats[i] == AnswerFormat.online ? const CreateRecommended() : null),
            onTap: () => onPick(formats[i]),
          ),
        ],
      ]);
}

/// What an answer table changes for the questions, said once above them.
class CreateTableRules extends StatelessWidget {
  const CreateTableRules({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('create.table.rules'),
        icon: Icons.table_chart_outlined,
        text: t('الأسئلة الموضوعية تُجاب في جدول الإجابة، والمقالية في كراسة الإجابة.',
            'Objective questions are answered in the answer table; essay questions in the answer booklet.'),
      );
}

// ═══════════════════════════════════════ sheet notes ═══════════════════════════════════════════════════════════

/// The teacher's own sheet types waiting for approval: visible, not choosable, and the way forward said.
class CreatePendingTemplates extends StatelessWidget {
  const CreatePendingTemplates({super.key, required this.items, this.justSent = false});
  final List<OmrTemplateItem> items;

  /// The sheet the teacher has just taught went for approval.
  final bool justSent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        key: const ValueKey('create.pending'),
        icon: Icons.hourglass_top_rounded,
        color: c.warning,
        text: justSent
            ? t('أُرسلت ورقتك للاعتماد ولا يمكن استخدامها قبل موافقة مشرف المنصة. أكمل الآن بورقة أخرى، وستجدها هنا عند اعتمادها.',
                'Your sheet went for approval and cannot be used until the platform admin accepts it. Continue with another one now; it will be here once approved.')
            : t('هذه الأوراق بانتظار موافقة مشرف المنصة. اختر ورقة معتمدة لتكمل الآن.',
                'These sheets are waiting for the platform admin to approve them. Choose an approved one to continue now.'),
      ),
      const SizedBox(height: AppSpace.xs),
      for (final x in items) ...[
        Opacity(
          opacity: .6,
          child: SetupChoiceTile(
            icon: Icons.grid_on_rounded,
            title: x.title,
            subtitle: x.subtitle,
            selected: false,
            badge: AppBadgePill(t('بانتظار الاعتماد', 'Waiting'), color: c.warning),
            onTap: null,
          ),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
    ]);
  }
}

/// A sheet NextBrain does not print, in plain words.
class CreateOwnSheetNote extends StatelessWidget {
  const CreateOwnSheetNote({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('create.ownsheet'),
        icon: Icons.info_outline_rounded,
        text: t('هذه ورقتك أنت: لا تطبعها NextBrain. اطبعها كما اعتدت، ثم صوّر الأوراق أو ارفعها للتصحيح. تُطبع ورقة الأسئلة وحدها من هنا، بنموذج واحد.',
            'This is your own sheet: NextBrain does not print it. Print it the way you normally do, then photograph or upload the sheets for marking. Only the question paper prints from here, in one version.'),
      );
}

// ═══════════════════════════════════════ questions ═════════════════════════════════════════════════════════════

enum CreateQuestionWay { automatic, manual, file, forms }

/// How the questions get here. The two main ways first, the others quieter below.
class CreateQuestionWayBody extends StatelessWidget {
  const CreateQuestionWayBody({super.key, required this.onPick, required this.hasCourse, required this.canGenerate, required this.canImportForms, required this.bubble});
  final ValueChanged<CreateQuestionWay> onPick;
  final bool hasCourse;

  /// The generator's switch is on (regardless of the course).
  final bool canGenerate;
  final bool canImportForms;
  final bool bubble;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canGenerate) ...[
        _Muted(
          off: !hasCourse,
          child: SetupChoiceTile(
            key: const ValueKey('create.way.automatic'),
            icon: Icons.auto_awesome_rounded,
            title: t('تلقائي', 'Automatic'),
            subtitle: hasCourse
                ? t('أسئلة من مستندات المقرر، تراجعها وتعدّلها قبل النشر', 'Questions written from the course documents; you review and edit them')
                : t('يحتاج إلى مقرر يقرأ منه الأسئلة. هذا الاختبار بلا مقرر، فاكتب الأسئلة بنفسك أو ارجع واختر مقررًا',
                    'Needs a course to read from. This exam has none: write the questions yourself, or go back and choose a course'),
            selected: false,
            badge: hasCourse ? const CreateRecommended() : null,
            onTap: hasCourse ? () => onPick(CreateQuestionWay.automatic) : null,
          ),
        ),
        _gap,
      ],
      SetupChoiceTile(
        key: const ValueKey('create.way.manual'),
        icon: Icons.edit_note_rounded,
        title: t('يدوي', 'Manual'),
        subtitle: bubble
            ? t('اكتب أسئلة اختيار من متعدد وصح / خطأ', 'Write multiple choice and true / false questions')
            : t('اكتب الأسئلة بنفسك: اختيار من متعدد، صح / خطأ، أكمل، مطابقة وغيرها', 'Write them yourself: multiple choice, true / false, complete, matching and more'),
        selected: false,
        badge: hasCourse && canGenerate ? null : const CreateRecommended(),
        onTap: () => onPick(CreateQuestionWay.manual),
      ),
      const SizedBox(height: AppSpace.md),
      Text(t('طرق أخرى', 'Other ways'), style: AppType.label(context)),
      const SizedBox(height: AppSpace.xs),
      _Muted(
        off: bubble,
        child: SetupChoiceTile(
          key: const ValueKey('create.way.file'),
          icon: Icons.upload_file_rounded,
          title: t('ارفع ملف امتحان جاهز', 'Upload a ready exam file'),
          subtitle: bubble
              ? t('ورقة التظليل تحتاج إلى أسئلة بإجابات صحيحة، والملف لا يوفرها', 'A bubble sheet needs questions with right answers, which a file does not give')
              : t('PDF أو Word أو صورة', 'A PDF, Word file or photo'),
          selected: false,
          onTap: bubble ? null : () => onPick(CreateQuestionWay.file),
        ),
      ),
      if (canImportForms) ...[
        _gap,
        SetupChoiceTile(
          key: const ValueKey('create.way.forms'),
          icon: Icons.dynamic_form_outlined,
          title: t('استيراد من Google Forms', 'Import from Google Forms'),
          subtitle: t('نموذج من حسابك يصبح أسئلة هذا الاختبار', 'A form from your account becomes this exam\'s questions'),
          selected: false,
          onTap: () => onPick(CreateQuestionWay.forms),
        ),
      ],
    ]);
  }
}

/// What a bubble sheet changes for the questions, said once before the first one is written.
class CreateBubbleRules extends StatelessWidget {
  const CreateBubbleRules({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('create.bubble.rules'),
        icon: Icons.grid_on_rounded,
        text: t('في ورقة التظليل: اختيار من متعدد وصح / خطأ فقط، ولكل سؤال إجابة صحيحة. يبقى ترتيب الأسئلة كما هو، ويمكن خلط الاختيارات.',
            'On a bubble sheet: multiple choice and true / false only, each with a right answer. The question order stays fixed; the choices can be shuffled.'),
      );
}

/// A bubble exam's questions that will not work, with the fix on the banner.
class CreateBubbleProblems extends StatelessWidget {
  const CreateBubbleProblems({super.key, required this.check, this.onRemove, this.onNormal, this.onEditor});
  final BubbleCheck check;

  /// Takes the questions a bubble cannot hold out of the exam.
  final VoidCallback? onRemove;

  /// Makes the students answer on the paper instead (any question type).
  final VoidCallback? onNormal;

  /// Opens the full editor (for imported questions).
  final VoidCallback? onEditor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = <Widget>[];
    Widget row(String text, {List<Widget> actions = const []}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          // the fixes sit under the banner: its own action slot is a single short button in a row
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppBanner(icon: Icons.warning_amber_rounded, color: c.danger, text: text),
            if (actions.isNotEmpty) Wrap(alignment: WrapAlignment.end, children: actions),
          ]),
        );
    final n = check.notHeld.length;
    if (n > 0) {
      lines.add(row(
        t('لا يمكن لورقة التظليل حمل ${questionsCountText(n)}: مقالي أو إجابة قصيرة أو أكمل أو مطابقة.',
            'A bubble sheet cannot hold ${questionsCountText(n)}: essay, short answer, complete or matching.'),
        actions: [
          if (onRemove != null) AppButton.ghost(key: const ValueKey('create.bubble.remove'), size: AppButtonSize.sm, onPressed: onRemove, label: t('احذفها', 'Remove them')),
          if (onNormal != null) AppButton.ghost(key: const ValueKey('create.bubble.normal'), size: AppButtonSize.sm, onPressed: onNormal, label: t('اجعل الإجابة على ورقة الأسئلة', 'Answer on the paper instead')),
        ],
      ));
    }
    if (check.importedNotHeld > 0) {
      lines.add(row(
        t('${questionsCountText(check.importedNotHeld)} من المستورد لا تناسب ورقة التظليل. احذفها من المحرر الكامل.',
            '${questionsCountText(check.importedNotHeld)} of the imported ones do not fit a bubble sheet. Remove them in the full editor.'),
        actions: [
          if (onEditor != null) AppButton.ghost(size: AppButtonSize.sm, onPressed: onEditor, label: t('المحرر الكامل', 'Full editor')),
          if (onNormal != null) AppButton.ghost(size: AppButtonSize.sm, onPressed: onNormal, label: t('اجعل الإجابة على ورقة الأسئلة', 'Answer on the paper instead')),
        ],
      ));
    }
    if (check.over > 0) {
      lines.add(row(t('الورقة تتسع لـ${questionsCountText(check.capacity ?? 0)} فقط. احذف ${questionsCountText(check.over)} أو اختر ورقة أكبر.',
          'This sheet holds only ${questionsCountText(check.capacity ?? 0)}. Remove ${questionsCountText(check.over)} or choose a larger sheet.')));
    }
    if (check.choicesOver > 0) {
      lines.add(row(t('${questionsCountText(check.choicesOver)} بها اختيارات أكثر من فقاعات الورقة.', '${questionsCountText(check.choicesOver)} have more choices than the sheet has bubbles.')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
  }
}

/// Questions already on the server from an import.
class CreateImportedCard extends StatelessWidget {
  const CreateImportedCard({super.key, required this.count, required this.points, this.onEditor});
  final int count;
  final double points;
  final VoidCallback? onEditor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBanner(
      key: const ValueKey('create.imported'),
      icon: Icons.task_alt_rounded,
      color: c.success,
      text: t('استوردنا ${questionsCountText(count)}، والمجموع ${marksCountText(points)}.', 'Imported ${questionsCountText(count)}, ${marksCountText(points)} in all.'),
      action: onEditor == null ? null : AppButton.ghost(size: AppButtonSize.sm, onPressed: onEditor, label: t('راجعها', 'Review')),
    );
  }
}

// ═══════════════════════════════════════ publish ═══════════════════════════════════════════════════════════════

class CreatePublishBody extends StatelessWidget {
  const CreatePublishBody({
    super.key,
    required this.plan,
    required this.onPaperPlan,
    required this.onVersions,
    required this.onShuffleQuestions,
    required this.onShuffleOptions,
    required this.electronicDetail,
  });
  final ExamCreatePlan plan;
  final ValueChanged<PaperPlan> onPaperPlan;
  final ValueChanged<int> onVersions;
  final ValueChanged<bool> onShuffleQuestions, onShuffleOptions;

  /// The timing and the rules (the quick builder's panel).
  final Widget electronicDetail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    final noStudents = !p.hasCourse && p.exam.orgId == null;
    // the kind was chosen in the Answers step: here only what follows from it
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p.isElectronic) ...[
        AppBanner(
          key: const ValueKey('create.audience'),
          icon: noStudents ? Icons.warning_amber_rounded : Icons.groups_outlined,
          color: noStudents ? c.warning : null,
          text: noStudents
              ? t('هذا الاختبار بلا مقرر ولا مؤسسة، فلن يظهر لأي طالب. اربطه بمقرر من المحرر الكامل، أو اختره ورقيًا.',
                  'This exam has no course or organization, so no student will see it. Link it to a course in the full editor, or make it a paper exam.')
              : (p.hasCourse
                  ? t('يظهر لطلاب «${p.place?.name ?? ''}» عند موعده.', 'Students of "${p.place?.name ?? ''}" see it when it opens.')
                  : t('يظهر لطلاب المؤسسة عند موعده.', 'The organization\'s students see it when it opens.')),
        ),
        const SizedBox(height: AppSpace.sm),
        electronicDetail,
      ],
      if (p.isPaper) ...[
        Text(t('كيف تُطبع الأوراق؟', 'How is it printed?'), style: AppType.section(context)),
        _gap,
        SetupChoiceTile(
          key: const ValueKey('create.paper.versions'),
          icon: Icons.layers_outlined,
          title: t('نموذج واحد أو عدة نماذج', 'One exam per version'),
          subtitle: t('كل نموذج يُطبع بعدد الحاضرين', 'Each version is printed for those attending'),
          selected: p.paperPlan == PaperPlan.versions,
          badge: const CreateRecommended(),
          onTap: () => onPaperPlan(PaperPlan.versions),
        ),
        if (p.paperPlan == PaperPlan.versions) ...[
          const SizedBox(height: AppSpace.xs),
          CreateVersionsPanel(plan: p, onVersions: onVersions, onShuffleQuestions: onShuffleQuestions, onShuffleOptions: onShuffleOptions),
        ],
        _gap,
        _Muted(
          off: !p.personalAllowed,
          child: SetupChoiceTile(
            key: const ValueKey('create.paper.personal'),
            icon: Icons.badge_outlined,
            title: t('ورقة شخصية لكل طالب', 'A personal version for each student'),
            subtitle: p.personalAllowed
                ? t('تُطبع باسم الطالب وبياناته فتُطابق ورقته تلقائيًا', 'Printed with the student\'s name and details, so each paper matches by itself')
                : _personalWhyNot(p),
            selected: p.paperPlan == PaperPlan.personal,
            onTap: p.personalAllowed ? () => onPaperPlan(PaperPlan.personal) : null,
          ),
        ),
      ],
    ]);
  }

  String _personalWhyNot(ExamCreatePlan p) {
    if (!p.hasCourse) return t('يحتاج إلى مقرر لنعرف طلابه', 'Needs a course, so we know its students');
    if (p.exam.isFile) return t('الملف المرفوع يُطبع كما هو', 'An uploaded file prints as it is');
    return t('ورقتك الخاصة لا تطبعها NextBrain', 'NextBrain does not print your own sheet');
  }
}

class CreateVersionsPanel extends StatelessWidget {
  const CreateVersionsPanel({super.key, required this.plan, required this.onVersions, required this.onShuffleQuestions, required this.onShuffleOptions});
  final ExamCreatePlan plan;
  final ValueChanged<int> onVersions;
  final ValueChanged<bool> onShuffleQuestions, onShuffleOptions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = plan;
    if (!p.versionsAllowed) {
      return AppBanner(
        icon: Icons.info_outline_rounded,
        text: p.exam.isFile
            ? t('الملف المرفوع يُطبع كما هو، بنموذج واحد.', 'An uploaded file prints as it is, in one version.')
            : t('ورقتك الخاصة لا تحمل رمزًا يميز النموذج، فهو نموذج واحد.', 'Your own sheet carries no version mark, so it is one version.'),
      );
    }
    final n = p.versions;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('كم نموذجًا؟', 'How many versions?'), style: AppType.bodyStrong(context))),
          IconButton(key: const ValueKey('create.versions.less'), tooltip: t('أقل', 'Fewer'), onPressed: n > 1 ? () => onVersions(n - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
          SizedBox(width: AppIconSize.xl, child: Text('$n', key: const ValueKey('create.versions.count'), textAlign: TextAlign.center, style: AppType.figure(context))),
          IconButton(key: const ValueKey('create.versions.more'), tooltip: t('أكثر', 'More'), onPressed: n < 10 ? () => onVersions(n + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]),
        if (n > 1) ...[
          AppSwitchTile(
            title: t('اخلط ترتيب الأسئلة', 'Shuffle the questions'),
            subtitle: p.isBubble ? versionsBubbleText : null,
            value: p.shuffleQuestions && !p.isBubble,
            dense: true,
            onChanged: p.isBubble ? null : onShuffleQuestions,
          ),
          AppSwitchTile(
            title: t('اخلط ترتيب الاختيارات', 'Shuffle the choices'),
            subtitle: p.shuffleOptionsAllowed ? null : t('مربعات الاختيار في ورقة الإجابة تتبع ترتيب الاختيارات', 'The choice boxes on the answer sheet follow the option order'),
            value: p.shuffleOptions && p.shuffleOptionsAllowed,
            dense: true,
            onChanged: p.shuffleOptionsAllowed ? onShuffleOptions : null,
          ),
          if (versionsWouldMatch(p))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppBanner(
                key: const ValueKey('create.versions.same'),
                icon: Icons.warning_amber_rounded,
                color: c.warning,
                text: t('ستخرج النماذج متطابقة: لا شيء يمكن خلطه. فعّل الخلط أو اكتفِ بنموذج واحد.',
                    'The versions would come out the same: nothing can be shuffled. Turn shuffling on, or keep one version.'),
              ),
            ),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════ leaving, done ═════════════════════════════════════════════════════════

enum CreateLeave { keep, delete, save, discard }

/// Leaving before the end: nothing is lost by surprise.
class CreateLeaveBody extends StatelessWidget {
  const CreateLeaveBody({super.key, required this.hasDraft, required this.canSave, required this.onPick, required this.onStay});
  final bool hasDraft, canSave;
  final ValueChanged<CreateLeave> onPick;
  final VoidCallback onStay;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: hasDraft ? Icons.bookmark_added_outlined : Icons.info_outline_rounded,
        text: hasDraft
            ? t('اختبارك محفوظ كمسودة في صفحة الاختبارات، ويمكنك إكماله من هناك.', 'Your exam is saved as a draft on the Exams page, and you can finish it from there.')
            : t('ما كتبته لم يُحفظ بعد.', 'What you wrote is not saved yet.'),
      ),
      const SizedBox(height: AppSpace.md),
      if (hasDraft)
        AppButton.primary(key: const ValueKey('create.leave.keep'), label: t('احتفظ بالمسودة واخرج', 'Keep the draft and leave'), expand: true, onPressed: () => onPick(CreateLeave.keep))
      else if (canSave)
        AppButton.primary(key: const ValueKey('create.leave.save'), label: t('احفظ كمسودة واخرج', 'Save as a draft and leave'), expand: true, onPressed: () => onPick(CreateLeave.save)),
      AppSpace.gapXs,
      AppButton.secondary(key: const ValueKey('create.leave.stay'), label: t('أكمل الاختبار', 'Keep working'), expand: true, onPressed: onStay),
      AppSpace.gapXs,
      AppButton.danger(
        key: ValueKey(hasDraft ? 'create.leave.delete' : 'create.leave.discard'),
        label: hasDraft ? t('احذف المسودة', 'Delete the draft') : t('اخرج دون حفظ', 'Leave without saving'),
        dangerOutline: true,
        expand: true,
        onPressed: () => onPick(hasDraft ? CreateLeave.delete : CreateLeave.discard),
      ),
    ]);
  }
}

/// The electronic exam is out: what happened and the next useful things.
class CreateDoneBody extends StatelessWidget {
  const CreateDoneBody({super.key, required this.title, required this.place, required this.lines, required this.onDone, required this.onOpen, this.onFollow, this.onShare});
  final String title;
  final String? place;
  final List<(String, String)> lines;
  final VoidCallback onDone, onOpen;
  final VoidCallback? onFollow, onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.form.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // the moment the exam goes out: one emerald hero block that settles in, the mark, the editorial headline
                AppPopIn(
                  child: AppBlock(
                    tone: AppBlockTone.emerald,
                    hero: true,
                    child: Builder(builder: (context) {
                      final b = AppBlock.colorsOf(context);
                      final mark = b.accentInk(c.success);
                      return Column(children: [
                        Container(
                          width: AppSpace.xxxl,
                          height: AppSpace.xxxl,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: mark.withValues(alpha: .12)),
                          child: Icon(Icons.task_alt_rounded, size: AppIconSize.xl, color: mark),
                        ),
                        AppSpace.gapMd,
                        Text(t('نُشر الاختبار', 'The exam is published'), key: const ValueKey('create.done'), textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: b.ink)),
                        const SizedBox(height: AppSpace.xxs),
                        Text([title, ?place].join(' · '), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted, height: 1.45)),
                      ]);
                    }),
                  ),
                ),
                AppSpace.gapMd,
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                  child: Column(children: [
                    for (var i = 0; i < lines.length; i++) ...[
                      if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppTouch.min),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Flexible(child: Text(lines[i].$1, style: AppType.meta(context))),
                          AppSpace.gapSm,
                          Flexible(child: Text(lines[i].$2, textAlign: TextAlign.end, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                    ],
                  ]),
                ),
                AppSpace.gapLg,
                AppButton.primary(key: const ValueKey('create.done.finish'), label: t('تم', 'Done'), expand: true, onPressed: onDone),
                AppSpace.gapXs,
                Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  AppButton.ghost(key: const ValueKey('create.done.open'), label: t('افتح الاختبار', 'Open the exam'), icon: Icons.edit_outlined, onPressed: onOpen),
                  if (onFollow != null) AppButton.ghost(label: t('تابع النتائج', 'Follow the results'), icon: Icons.leaderboard_rounded, onPressed: onFollow),
                  if (onShare != null) AppButton.ghost(label: t('أخبر الطلاب', 'Tell the students'), icon: Icons.campaign_outlined, onPressed: onShare),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
