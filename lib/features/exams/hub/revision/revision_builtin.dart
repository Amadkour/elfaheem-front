// Ready-made paper covers in the revision wizard (D-357): the card that offers one as the first choice, and the one question it
// needs, the paper's full mark. Plain values in, callbacks out; the layout harness pumps them.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart' show markNumberText;
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart' show MarkBuiltin, parseFullMark;

typedef RevisionBuiltinImage = Future<Uint8List?> Function(String key);

/// The blank page of a built-in, in its portrait shape; a soft placeholder until the bytes arrive.
class RevisionBuiltinThumb extends StatefulWidget {
  const RevisionBuiltinThumb({super.key, required this.builtinKey, required this.width, this.load});
  final String builtinKey;
  final double width;
  final RevisionBuiltinImage? load;

  @override
  State<RevisionBuiltinThumb> createState() => _RevisionBuiltinThumbState();
}

class _RevisionBuiltinThumbState extends State<RevisionBuiltinThumb> {
  late final Future<Uint8List?>? _bytes = widget.load?.call(widget.builtinKey);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: widget.width,
      height: widget.width * 1.4,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider), boxShadow: AppElevation.of(context, 1)),
      child: FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (_, s) => s.data == null
            ? Icon(Icons.description_outlined, color: c.textLight)
            : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true, errorBuilder: (_, _, _) => Icon(Icons.description_outlined, color: c.textLight)),
      ),
    );
  }
}

class RevisionBuiltinCard extends StatelessWidget {
  const RevisionBuiltinCard({super.key, required this.builtin, required this.onTap, this.load, this.busy = false, this.selected = false});
  final MarkBuiltin builtin;
  final VoidCallback? onTap;
  final RevisionBuiltinImage? load;
  final bool busy, selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = Theme.of(context).textButtonTheme.style?.foregroundColor?.resolve(const {}) ?? c.primary;
    final n = builtin.fieldsCount;
    return AppCard(
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(children: [
        RevisionBuiltinThumb(builtinKey: builtin.key, width: 76, load: load),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppBadgePill(t('جاهز بلمسة واحدة', 'Ready in one tap'), color: accent),
            const SizedBox(height: AppSpace.xxs),
            Text(builtin.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            if (builtin.note.isNotEmpty) Text(builtin.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            if (n > 0) Text(t('الخانات محددة مسبقًا: ${countText(n, ar1: 'خانة واحدة', ar2: 'خانتان', arFew: '$n خانات', arMany: '$n خانة', en1: '1 field', en: '$n fields')}', 'Already marked: ${countText(n, ar1: 'خانة واحدة', ar2: 'خانتان', arFew: '$n خانات', arMany: '$n خانة', en1: '1 field', en: '$n fields')}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        busy
            ? SizedBox(width: AppIconSize.md, height: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: accent))
            : Icon(selected ? Icons.check_circle_rounded : Icons.arrow_forward_rounded, color: selected ? accent : c.textLight),
      ]),
    );
  }
}

/// The one question a ready-made cover asks. It answers through [onDone] with a mark the server will accept.
class RevisionBuiltinMarkSheet extends StatefulWidget {
  const RevisionBuiltinMarkSheet({super.key, required this.builtin, required this.onDone, this.initial, this.columnMax, this.load});
  final MarkBuiltin builtin;
  final ValueChanged<double> onDone;
  final double? initial;

  /// The degree column's own scale: offered as the default, and named so the teacher knows where it came from.
  final double? columnMax;
  final RevisionBuiltinImage? load;

  @override
  State<RevisionBuiltinMarkSheet> createState() => _RevisionBuiltinMarkSheetState();
}

class _RevisionBuiltinMarkSheetState extends State<RevisionBuiltinMarkSheet> {
  late final _mark = TextEditingController(text: widget.initial == null ? '' : markNumberText(widget.initial));
  bool _invalid = false;

  @override
  void dispose() {
    _mark.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseFullMark(_mark.text);
    if (v == null) {
      setState(() => _invalid = true);
      return;
    }
    widget.onDone(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = widget.columnMax;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RevisionBuiltinThumb(builtinKey: widget.builtin.key, width: 56, load: widget.load),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.builtin.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('الكراسة لا تطبع الدرجة الكلية، فنحتاجها منك مرة واحدة.', "The booklet doesn't print the full mark, so we ask once."), style: AppType.meta(context)),
          ]),
        ),
      ]),
      AppSpace.gapMd,
      Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(key: const ValueKey('rv.builtin.total'), controller: _mark, label: t('الدرجة الكلية للورقة', "The paper's full mark"), min: 0, decimals: 2, onChanged: (_) {
          if (_invalid) setState(() => _invalid = false);
        })),
      if (_invalid)
        Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(t('اكتب رقمًا أكبر من صفر وحتى 1000.', 'Enter a number above 0, up to 1000.'), key: const ValueKey('rv.builtin.invalid'), style: AppType.meta(context).copyWith(color: c.danger)))
      else if (col != null)
        Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(t('اقترحناها من عمود الدرجة في Data Lab (${markNumberText(col)}).', 'Suggested from your Data Lab column (${markNumberText(col)}).'), style: AppType.meta(context))),
      AppSpace.gapMd,
      AppPrimaryButton(key: const ValueKey('rv.builtin.use'), label: t('استخدام هذا الغلاف', 'Use this cover'), icon: Icons.check_rounded, onPressed: _submit),
    ]);
  }
}
