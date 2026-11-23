// lib/features/games/admin/v4/editors/item_preview.dart — the live preview card of an item being edited
// (Games v4 T65). Plain values in: the draft item and, when the server's `POST /items/check` has answered, its
// `resolved` snapshot (sequence tokens of a Quran / Hadith reference come from there). Sacred text is drawn in the
// Quran role (`quranTextStyle`), and the card never edits anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show isArabicText, quranTextStyle;

class ItemPreviewCard extends StatelessWidget {
  const ItemPreviewCard({super.key, required this.item, this.resolved, this.error, this.checking = false});

  final Json item;
  final Json? resolved;

  /// The server's complaint about the draft (already a readable line), shown instead of a silent blank.
  final String? error;
  final bool checking;

  String _pick(Object? m) {
    final j = jmap(m);
    final first = AppConfig.lang == 'ar' ? j['ar'] : j['en'];
    return '${first ?? j['ar'] ?? j['en'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = '${item['type'] ?? ''}';
    final body = jmap(item['body']);
    final sacred = jmap(item['source'])['kind'] == 'quran' || jmap(item['source'])['kind'] == 'hadith';
    final prompt = _pick(item['prompt']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('هكذا يراه الطفل', 'What the child sees'), style: AppType.overline(context))),
          if (checking)
            SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.strong))
          else if (error != null)
            Icon(Icons.error_outline_rounded, size: AppIconSize.md, color: c.danger)
          else
            Icon(Icons.check_circle_outline_rounded, size: AppIconSize.md, color: c.success),
        ]),
        AppSpace.gapSm,
        Text(prompt.isEmpty ? t('اكتب نص السؤال', 'Write the question') : prompt, style: AppType.section(context)),
        AppSpace.gapSm,
        _bodyView(context, type, body, sacred),
        if (error != null) ...[
          AppSpace.gapSm,
          Text(error!, style: AppType.meta(context).copyWith(color: c.danger)),
        ],
      ]),
    );
  }

  Widget _chip(BuildContext context, String text, {bool good = false, bool sacred = false}) {
    final c = context.colors;
    final empty = text.trim().isEmpty;
    final style = sacred && isArabicText(text) ? quranTextStyle(16, color: c.textDark) : AppType.row(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: good ? c.success.withValues(alpha: 0.14) : c.cardBg2,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: good ? c.success : c.divider, width: AppBorder.hairline),
      ),
      child: Text(empty ? '…' : text, style: style, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _wrap(List<Widget> kids) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: kids);

  Widget _bodyView(BuildContext context, String type, Json body, bool sacred) {
    switch (type) {
      case 'mcq':
      case 'select_all':
        final opts = jlist(body['options']);
        final ans = type == 'mcq'
            ? {jint(body['answer'], -1)}
            : {for (final a in (body['answers'] is List ? body['answers'] as List : const [])) jint(a, -1)};
        return _wrap([for (var i = 0; i < opts.length; i++) _chip(context, '${opts[i]['text'] ?? ''}', good: ans.contains(i))]);
      case 'true_false':
        return _wrap([_chip(context, t('صح', 'True'), good: body['answer'] == true), _chip(context, t('خطأ', 'False'), good: body['answer'] == false)]);
      case 'sequence':
        final rb = jmap(resolved?['body'])['tokens'];
        final toks = rb is List ? rb : (body['tokens'] is List ? body['tokens'] as List : null);
        if (toks == null) return Text('${body['tokens'] ?? ''}', textDirection: TextDirection.ltr, style: AppType.meta(context));
        return Directionality(
          textDirection: toks.any((x) => isArabicText('$x')) ? TextDirection.rtl : Directionality.of(context),
          child: _wrap([for (var i = 0; i < toks.length; i++) _chip(context, '${toks[i]}', sacred: sacred)]),
        );
      case 'classify':
        final bks = jlist(body['buckets']);
        final tks = jlist(body['tokens']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final b in bks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: Text(_pick(b['label']).isEmpty ? '…' : _pick(b['label']), style: AppType.bodyStrong(context))),
                Expanded(
                  flex: 3,
                  child: _wrap([for (final x in tks) if (x['bucket'] == b['key']) _chip(context, '${x['text'] ?? ''}')]),
                ),
              ]),
            ),
        ]);
      case 'pair':
        return Column(children: [
          for (final p in jlist(body['pairs']))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(children: [
                Expanded(child: _chip(context, '${p['a'] ?? ''}')),
                const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.xs), child: Icon(Icons.swap_horiz_rounded, size: AppIconSize.md)),
                Expanded(child: _chip(context, '${p['b'] ?? ''}')),
              ]),
            ),
        ]);
      case 'fraction':
        if (body.containsKey('op')) {
          String f(Object? x) => x is List && x.length == 2 ? '${x[0]}/${x[1]}' : '?';
          return Text('${f(body['a'])}  ${body['op'] == 'sub' ? '−' : '+'}  ${f(body['b'])}  = ?', textDirection: TextDirection.ltr, style: AppType.figureLarge(context));
        }
        return Text('${body['n'] ?? '?'}/${body['d'] ?? '?'}  (${body['shape'] ?? ''})', textDirection: TextDirection.ltr, style: AppType.figureLarge(context));
      case 'program':
        return Text(
          t('لوحة ${body['w']}×${body['h']} · حتى ${body['max']} أمراً · الحل الأمثل ${body['par']}',
              'Board ${body['w']}×${body['h']} · up to ${body['max']} commands · best ${body['par']}'),
          style: AppType.body(context),
        );
      case 'combine':
        final ing = jlist(body['ingredients']);
        return _wrap([
          for (final i in ing)
            _chip(context, _pick(i['label']), good: (body['answer'] is List ? body['answer'] as List : const []).contains(i['key'])),
        ]);
    }
    return const SizedBox.shrink();
  }
}
