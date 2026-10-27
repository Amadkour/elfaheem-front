// The assistant's conversation (Phase 7, D-022; premium assistant D-012): ask the app's pages, the organization's
// rules or the course's documents and get an answer written from them with its sources. `app: true` is the app
// assistant: the platform's own documents for every user; with `orgId` too it is the app assistant opened inside
// an organization (that organization's library and rules as well). [RagChatView] is the conversation itself
// (history, answers, starter prompts, the question box) without a page around it: [RagChatScreen] puts it in a
// page, the floating app assistant (app_assistant.dart) in its pop-up. The presentational parts — [RagAnswerCard],
// [RagAnswerBody], [RagStageTrail], [RagStarterPrompts] — take plain values and run under the layout harness; the
// view owns the API calls and the polling.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'rag_chat.dart';
import 'rag_library.dart';
import 'rag_library_screen.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key, this.orgId, this.courseId, this.app = false, this.title});
  final int? orgId;
  final int? courseId;
  final bool app;
  final String? title;

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  final _chat = GlobalKey<RagChatViewState>();
  bool _manager = false; // library managers get the Library action (from the documents list: manager: true)

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('rag.assistant'),
      appBar: ScreenAppBar(title: widget.title ?? (widget.app ? t('مساعد التطبيق', 'App assistant') : t('مساعد المستندات', 'Documents assistant')),
          actions: [
            if (_manager)
              IconButton(
                  tooltip: t('مكتبة المستندات', 'Documents library'),
                  icon: const Icon(Icons.folder_copy_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RagLibraryScreen(orgId: widget.app ? null : widget.orgId, courseId: widget.courseId, app: widget.app)))),
            IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: () => _chat.currentState?.refresh()),
            if (widget.orgId != null && !widget.app) const ContextExitButton(),
          ]),
      child: RagChatView(
          key: _chat,
          orgId: widget.orgId,
          courseId: widget.courseId,
          app: widget.app,
          onManager: (m) {
            if (m != _manager) setState(() => _manager = m);
          }),
    );
  }
}

/// The conversation: the caller's earlier questions with their answers, then the question box. Fills the height it
/// is given (it must be bounded: an Expanded, a page body, a sized pop-up).
class RagChatView extends StatefulWidget {
  const RagChatView({super.key, this.orgId, this.courseId, this.app = false, this.onManager, this.compact = false, this.api, this.contextLabel});
  final int? orgId;
  final int? courseId;
  final bool app;

  /// Whether the caller manages this library (the documents list answers `manager: true`).
  final ValueChanged<bool>? onManager;

  /// A narrow pop-up: tighter padding.
  final bool compact;
  final RagApi? api;

  /// Shown in the banner: where the assistant reads from (the organization's name inside an organization).
  final String? contextLabel;

  @override
  State<RagChatView> createState() => RagChatViewState();
}

class RagChatViewState extends State<RagChatView> {
  late final RagApi _api = widget.api ?? RagApi();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<RagAnswer> _items = [];
  List<String>? _starters; // from the server (questions the library answers); null = the built-in list
  bool _loading = true;
  bool _sending = false;
  String? _error;

  RagContext get _ctx => ragContextOf(app: widget.app, orgId: widget.orgId);

  @override
  void initState() {
    super.initState();
    _history();
    _loadStarters();
    if (widget.onManager != null) _checkManager();
  }

  Future<void> _loadStarters() async {
    final r = await _api.starters(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted || !r.ok) return;
    final qs = ragStartersFrom(r.map);
    if (qs.isNotEmpty) setState(() => _starters = qs);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reloads the history (the page's Refresh action).
  void refresh() {
    setState(() => _error = null);
    _history();
  }

  Future<void> _history() async {
    final r = await _api.history(orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _items..clear()..addAll(RagApi.items(r).reversed);
      if (r.unavailable) _error = t('المساعد غير متاح بعد على هذا الخادم', 'The assistant is not available on this server yet');
      if (!r.ok && ragOrgBlocked(r.code)) _error = ragChatResultText(r); // suspended / deactivated / switched off
    });
    _toEnd();
  }

  Future<void> _checkManager() async {
    final r = await RagLibraryApi().list(orgId: widget.app ? null : widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted || !r.ok) return;
    widget.onManager?.call(RagLibrary.fromJson(r.map).manager);
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  /// Sends [text] (a typed question, a starter prompt or a follow-up).
  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending) return;
    setState(() { _sending = true; _error = null; });
    final r = await _api.ask(q, orgId: widget.orgId, courseId: widget.courseId, app: widget.app);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _sending = false; _error = ragChatResultText(r); });
      return;
    }
    _input.clear();
    final pending = RagAnswer.fromJson(r.map);
    setState(() => _items.add(pending));
    _toEnd();
    final done = await _api.waitFor(pending.id, onUpdate: (a) {
      if (!mounted) return;
      final i = _items.indexWhere((x) => x.id == a.id);
      if (i >= 0 && _items[i].stage != a.stage) setState(() => _items[i] = a);
    });
    if (!mounted) return;
    setState(() {
      _sending = false;
      final i = _items.indexWhere((a) => a.id == pending.id);
      if (done.ok && i >= 0) _items[i] = RagAnswer.fromJson(done.map);
      if (!done.ok) _error = ragChatResultText(done);
      if (done.ok && !RagAnswer.fromJson(done.map).done) {
        _error = t('ما زال المساعد يعمل على إجابتك — حدّث بعد قليل', 'The assistant is still working on your answer — refresh in a moment');
      }
    });
    _toEnd();
  }

  Future<void> _rate(RagAnswer a, bool helpful) async {
    final r = await _api.rate(a.id, helpful: helpful);
    if (!mounted || !r.ok) return;
    setState(() {
      final i = _items.indexWhere((x) => x.id == a.id);
      if (i >= 0) _items[i] = RagAnswer.fromJson(r.map);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final side = widget.compact ? 12.0 : 16.0;
    final last = _items.isEmpty ? null : _items.last;
    return Column(children: [
      Expanded(
        child: ListView(controller: _scroll, padding: EdgeInsets.fromLTRB(side, 8, side, 16), children: [
          AppBanner(icon: Icons.menu_book_rounded, color: c.primary, text: _scopeText()),
          const SizedBox(height: 10),
          if (_loading) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
          if (!_loading && _items.isEmpty && _error == null) RagStarterPrompts(context_: _ctx, prompts: _starters, onPick: send, compact: widget.compact),
          for (final a in _items)
            RagAnswerCard(
                answer: a,
                onRate: a.smallTalk ? null : (helpful) => _rate(a, helpful),
                onFollowUp: identical(a, last) && !_sending ? send : null),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger)),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 4, side, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: EnterSubmits(
                    onSubmit: () => send(_input.text),
                    child: AppField(controller: _input, label: t('اسألني أي شيء…', 'Ask me anything…'), maxLines: 3))),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: t('إرسال', 'Send'),
              onPressed: _sending ? null : () => send(_input.text),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }

  String _scopeText() {
    final org = widget.contextLabel;
    return switch (_ctx) {
      RagContext.app => t('أجيب من شروط التطبيق وصفحاته وأدلته، مع ذكر المصدر. إن لم تكن الإجابة فيها أخبرك بذلك.',
          'I answer from the app\'s terms, pages and guides, with the source. If the answer is not there, I say so.'),
      RagContext.org => org == null || org.isEmpty
          ? t('أجيب من صفحات التطبيق ومن قواعد مؤسستك ومستنداتها، مع ذكر المصدر.',
              'I answer from the app\'s pages and from your organization\'s rules and documents, with the source.')
          : t('أجيب من صفحات التطبيق ومن قواعد «$org» ومستنداتها، مع ذكر المصدر.',
              'I answer from the app\'s pages and from the rules and documents of "$org", with the source.'),
      RagContext.docs => t('أجيب من مستندات مؤسستك ومقرراتك فقط، مع ذكر المصدر. إن لم تكن الإجابة فيها أخبرك بذلك.',
          'I answer only from your organization\'s and courses\' documents, with the source. If the answer is not there, I say so.'),
    };
  }
}

/// The empty chat: what the assistant can do, as questions to tap.
class RagStarterPrompts extends StatelessWidget {
  const RagStarterPrompts({super.key, required this.context_, required this.onPick, this.prompts, this.compact = false});
  final RagContext context_;
  final ValueChanged<String> onPick;
  /// The server's questions (built from the library's headings); null or empty = [ragStarterPrompts].
  final List<String>? prompts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 12 : 24),
        child: Column(children: [
          Container(
            width: 56, height: 56, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome_rounded, color: c.primary, size: 28),
          ),
          const SizedBox(height: 10),
          Text(t('كيف أساعدك اليوم؟', 'How can I help you today?'), textAlign: TextAlign.center, style: appText(16, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: 4),
          Text(t('اسأل بالعربية أو الإنجليزية — أجيب بلغتك', 'Ask in Arabic or English — I answer in your language'),
              textAlign: TextAlign.center, style: appText(12.5, c: c.textMedium)),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (final p in (prompts == null || prompts!.isEmpty) ? ragStarterPrompts(context_) : prompts!)
          AppChoiceChip(label: p, selected: false, onTap: () => onPick(p), icon: Icons.chat_bubble_outline_rounded),
      ]),
    ]);
  }
}

/// The steps of an answer being prepared: done · current · to come.
class RagStageTrail extends StatelessWidget {
  const RagStageTrail({super.key, required this.stage});
  final String? stage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = ragStages.indexOf(stage ?? '');
    final labels = [t('فهم', 'Understand'), t('بحث', 'Search'), t('كتابة', 'Write'), t('مراجعة', 'Verify')];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
        const SizedBox(width: 8),
        Expanded(child: Text(ragStageText(stage), style: appText(13, c: c.textMedium))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (var i = 0; i < ragStages.length; i++)
          _StageDot(label: labels[i], state: at < 0 ? (i == 0 ? 1 : 0) : (i < at ? 2 : (i == at ? 1 : 0))),
      ]),
    ]);
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.label, required this.state});
  final String label;
  final int state; // 0 to come · 1 now · 2 done

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = state == 0 ? c.textLight : (state == 1 ? c.primary : c.success);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(state == 2 ? Icons.check_circle_rounded : (state == 1 ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded), size: 14, color: col),
      const SizedBox(width: 3),
      Text(label, style: appText(11.5, w: state == 1 ? FontWeight.w700 : FontWeight.w500, c: col)),
    ]);
  }
}

/// A question and its answer: the answer's blocks with their `[n]` markers, the follow-ups, then the sources it quotes.
class RagAnswerCard extends StatelessWidget {
  const RagAnswerCard({super.key, required this.answer, this.onRate, this.onFollowUp});
  final RagAnswer answer;

  /// helpful? (null = no rating offered)
  final void Function(bool helpful)? onRate;

  /// Tapping a suggested question sends it (null = the chips are not shown).
  final ValueChanged<String>? onFollowUp;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: Text(answer.question, style: theme.bodyMedium),
          ),
        ),
        const SizedBox(height: 6),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: !answer.done
              ? RagStageTrail(stage: answer.stage)
              : answer.state == 'failed'
                  ? AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: t('تعذرت الإجابة — أعد السؤال', 'Could not answer — ask again'))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (answer.found == false && !answer.smallTalk)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.search_off_rounded, size: 18, color: c.warning),
                          const SizedBox(width: 6),
                          Expanded(child: RagAnswerBody(text: answer.answer)),
                        ])
                      else
                        RagAnswerBody(text: answer.answer),
                      if (answer.citations.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(t('المصادر', 'Sources'), style: theme.labelMedium?.copyWith(color: c.textMedium)),
                        const SizedBox(height: 4),
                        for (final ci in answer.citations) _Source(citation: ci),
                      ],
                      if (answer.followUps.isNotEmpty && onFollowUp != null) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final f in answer.followUps)
                            AppChoiceChip(label: f, selected: false, onTap: () => onFollowUp!(f), icon: Icons.arrow_outward_rounded),
                        ]),
                      ],
                      // a Wrap, not a Row: on a 320 px phone with large text the badge, Copy and the rating share two lines
                      Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                        if (answer.byModel && !answer.smallTalk)
                          Tooltip(
                            message: t('إجابة مكتوبة من المصادر وتمت مراجعتها', 'Written from the sources and checked against them'),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.verified_rounded, size: 14, color: c.success),
                              const SizedBox(width: 3),
                              Text(t('من المصادر', 'From the sources'), style: appText(11, c: c.textLight)),
                            ]),
                          ),
                        IconButton(
                            tooltip: t('نسخ', 'Copy'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: answerRuns(answer.answer).where((r) => r.cite == null).map((r) => r.text).join()));
                              appToast(t('تم النسخ', 'Copied'));
                            },
                            icon: Icon(Icons.copy_rounded, size: 16, color: c.textLight)),
                        if (onRate != null) ...[
                          Text(t('هل أفادتك؟', 'Helpful?'), style: theme.bodySmall?.copyWith(color: c.textLight)),
                          IconButton(
                              tooltip: t('مفيدة', 'Helpful'), visualDensity: VisualDensity.compact, onPressed: () => onRate!(true),
                              icon: Icon(answer.helpful == true ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, size: 18,
                                  color: answer.helpful == true ? c.success : c.textLight)),
                          IconButton(
                              tooltip: t('غير مفيدة', 'Not helpful'), visualDensity: VisualDensity.compact, onPressed: () => onRate!(false),
                              icon: Icon(answer.helpful == false ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined, size: 18,
                                  color: answer.helpful == false ? c.danger : c.textLight)),
                        ],
                      ]),
                    ]),
        ),
      ]),
    );
  }
}

/// The answer text: paragraphs, bullets and numbered steps, **bold** terms, `[n]` markers in the accent colour.
class RagAnswerBody extends StatelessWidget {
  const RagAnswerBody({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    final blocks = answerBlocks(text);
    if (blocks.isEmpty) return Text(text, style: base);
    TextSpan spans(List<AnswerRun> runs) => TextSpan(children: [
          for (final r in runs)
            r.cite != null
                ? TextSpan(text: r.text, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12))
                : TextSpan(text: r.text, style: r.bold ? const TextStyle(fontWeight: FontWeight.w800) : null),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : (blocks[i].kind == AnswerBlockKind.paragraph ? 8 : 3)),
          child: blocks[i].kind == AnswerBlockKind.paragraph
              ? Text.rich(spans(blocks[i].runs), style: base)
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 22,
                      child: Text(blocks[i].kind == AnswerBlockKind.bullet ? '•' : '${blocks[i].number}.',
                          style: base?.copyWith(color: c.primary, fontWeight: FontWeight.w800))),
                  Expanded(child: Text.rich(spans(blocks[i].runs), style: base)),
                ]),
        ),
    ]);
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.citation});
  final RagCitation citation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(start: 34, bottom: 8),
        dense: true,
        leading: Semantics(
          label: t('المصدر ${citation.n}', 'Source ${citation.n}'),
          excludeSemantics: true,
          child: CircleAvatar(radius: 12, backgroundColor: c.primary.withValues(alpha: 0.12),
              child: Text('${citation.n}', style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700))),
        ),
        title: Text(citation.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.bodySmall),
        children: [Align(alignment: AlignmentDirectional.centerStart, child: Text('«${citation.quote}»', style: theme.bodySmall?.copyWith(color: c.textMedium)))],
      ),
    );
  }
}
