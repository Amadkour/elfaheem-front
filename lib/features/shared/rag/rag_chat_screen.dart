// The documents assistant (Phase 7, D-022): ask the organization's / course's documents, get an answer quoted from
// them with its sources. `RagAnswerCard` is presentational (tested under the layout harness); the screen owns the
// API calls and the polling.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'rag_chat.dart';

class RagChatScreen extends StatefulWidget {
  const RagChatScreen({super.key, this.orgId, this.courseId, this.title});
  final int? orgId;
  final int? courseId;
  final String? title;

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  final _api = RagApi();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<RagAnswer> _items = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _history();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _history() async {
    final r = await _api.history(orgId: widget.orgId, courseId: widget.courseId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _items..clear()..addAll(RagApi.items(r).reversed);
      if (r.unavailable) _error = t('المساعد غير متاح بعد على هذا الخادم', 'The assistant is not available on this server yet');
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _sending) return;
    setState(() { _sending = true; _error = null; });
    final r = await _api.ask(q, orgId: widget.orgId, courseId: widget.courseId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _sending = false; _error = ragCodeText(r.code, r.message); });
      return;
    }
    _input.clear();
    final pending = RagAnswer.fromJson(r.map);
    setState(() => _items.add(pending));
    _toEnd();
    final done = await _api.waitFor(pending.id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      final i = _items.indexWhere((a) => a.id == pending.id);
      if (done.ok && i >= 0) _items[i] = RagAnswer.fromJson(done.map);
      if (!done.ok) _error = ragCodeText(done.code, done.message);
      if (done.ok && !RagAnswer.fromJson(done.map).done) {
        _error = t('ما زال المساعد يعمل على إجابتك — حدّث بعد قليل', 'The assistant is still working on your answer — refresh in a moment');
      }
    });
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      key: const ValueKey('rag.assistant'),
      appBar: ScreenAppBar(title: widget.title ?? t('مساعد المستندات', 'Documents assistant'),
          actions: [
            IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: () {
              setState(() => _error = null);
              _history();
            }),
            if (widget.orgId != null) const ContextExitButton(),
          ]),
      child: Column(children: [
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            AppBanner(icon: Icons.menu_book_rounded, color: c.primary,
                text: t('الإجابات من مستندات مؤسستك ومقرراتك فقط، مع ذكر المصدر. إن لم تكن الإجابة فيها سيخبرك المساعد بذلك.',
                    'Answers come only from your organization\'s and courses\' documents, with their sources. If the answer is not there, the assistant says so.')),
            const SizedBox(height: 10),
            if (_loading) const AppListSkeleton(items: 2),
            if (!_loading && _items.isEmpty && _error == null)
              AppEmpty(icon: Icons.question_answer_outlined, title: t('اسأل عن اللوائح أو الشروط أو محتوى المقرر', 'Ask about regulations, terms or course content')),
            for (final a in _items) RagAnswerCard(answer: a),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger)),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: AppField(controller: _input, label: t('سؤالك', 'Your question'), maxLines: 3)),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: t('إرسال', 'Send'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A question and its answer: the answer text with its `[n]` markers, then the sources it quotes.
class RagAnswerCard extends StatelessWidget {
  const RagAnswerCard({super.key, required this.answer});
  final RagAnswer answer;

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
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('أبحث في المستندات…', 'Searching the documents…'), style: theme.bodySmall?.copyWith(color: c.textMedium)),
                  const SizedBox(height: 8),
                  const AppSkeletonBox(height: 14),
                ])
              : answer.state == 'failed'
                  ? AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: t('تعذرت الإجابة — أعد السؤال', 'Could not answer — ask again'))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (answer.found == false)
                        Row(children: [
                          Icon(Icons.search_off_rounded, size: 18, color: c.warning),
                          const SizedBox(width: 6),
                          Expanded(child: Text(answer.answer, style: theme.bodyMedium)),
                        ])
                      else
                        Text.rich(TextSpan(children: [
                          for (final r in answerRuns(answer.answer))
                            r.cite == null
                                ? TextSpan(text: r.text)
                                : TextSpan(text: r.text, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                        ]), style: theme.bodyMedium?.copyWith(height: 1.5)),
                      if (answer.citations.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(t('المصادر', 'Sources'), style: theme.labelMedium?.copyWith(color: c.textMedium)),
                        const SizedBox(height: 4),
                        for (final ci in answer.citations) _Source(citation: ci),
                      ],
                    ]),
        ),
      ]),
    );
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
        leading: CircleAvatar(radius: 12, backgroundColor: c.primary.withValues(alpha: 0.12),
            child: Text('${citation.n}', style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700))),
        title: Text(citation.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.bodySmall),
        children: [Align(alignment: AlignmentDirectional.centerStart, child: Text('«${citation.quote}»', style: theme.bodySmall?.copyWith(color: c.textMedium)))],
      ),
    );
  }
}
