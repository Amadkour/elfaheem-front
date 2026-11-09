// "Whose paper is this?": on a handwritten cover number this is the common case of a run, so it is one calm tap and not an error.
// The number as written, the closest students as big choices (those who already have a paper marked and last), search for anyone
// else. Choosing goes through assign_student, and the degree then goes through the same compare as every other paper.
// Plain values in, callbacks out; the layout harness pumps it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../marks/mark_sessions_api.dart' show markNumberText;
import 'revision_models.dart';
import 'revision_wizard_steps.dart' show revisionAccent;

class RevisionChooseStudent extends StatefulWidget {
  const RevisionChooseStudent({super.key, required this.row, this.behind = 0, this.busy = false, this.pendingId, this.loadCrop, this.onChoose, this.onSearch, this.onRetake, this.onLater});

  final RevisionRow row;

  /// Other papers waiting after this one.
  final int behind;
  final bool busy;

  /// The student being linked right now.
  final int? pendingId;
  final Future<Uint8List?> Function(String url)? loadCrop;
  final ValueChanged<int>? onChoose;
  final VoidCallback? onSearch, onRetake, onLater;

  @override
  State<RevisionChooseStudent> createState() => _RevisionChooseStudentState();
}

class _RevisionChooseStudentState extends State<RevisionChooseStudent> {
  Future<Uint8List?>? _crop;

  void _load() {
    final u = widget.row.identifierCropUrl;
    _crop = u != null && u.isNotEmpty && widget.loadCrop != null ? widget.loadCrop!(u) : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RevisionChooseStudent old) {
    super.didUpdateWidget(old);
    if (old.row.identifierCropUrl != widget.row.identifierCropUrl) _load();
  }

  void _pick(RevisionCandidate x) {
    if (widget.busy) return;
    HapticFeedback.selectionClick();
    widget.onChoose?.call(x.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.row;
    final choices = r.choices;
    final used = r.row.proposed;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    final keys = <ShortcutActivator, VoidCallback>{
      for (final (i, x) in choices.indexed) SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), includeRepeats: false): () => _pick(x),
    };
    return CallbackShortcuts(
      bindings: keys,
      child: Focus(
        autofocus: true,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.behind > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(countText(widget.behind, ar1: 'ورقة أخرى بعد هذه', ar2: 'ورقتان أخريان بعد هذه', arFew: '${widget.behind} أوراق أخرى بعد هذه', arMany: '${widget.behind} ورقة أخرى بعد هذه', en1: '1 more after this one', en: '${widget.behind} more after this one'), key: const ValueKey('rv.behind'), style: AppType.meta(context)),
            ),
          Text(t('لمن هذه الورقة؟', 'Whose paper is this?'), key: const ValueKey('rv.name'), style: AppType.pageTitle(context)),
          Text(revisionUnsureText(r.rosterReason, candidates: choices.isNotEmpty), style: AppType.meta(context)),
          AppSpace.gapSm,
          _WrittenNumber(crop: _crop, value: r.row.identifierMasked),
          if (used != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text('${t('درجة الورقة', 'Paper degree')}: ${markNumberText(used)}', style: AppType.meta(context)),
          ],
          AppSpace.gapSm,
          for (final (i, x) in choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: _Choice(key: ValueKey('rv.choice.${x.id}'), candidate: x, top: i == 0 && !x.alreadyMatched && r.rosterReason != 'already_matched', keyHint: wide ? '${i + 1}' : null, pending: widget.pendingId == x.id, onTap: widget.busy ? null : () => _pick(x)),
            ),
          if (choices.any((x) => x.fromName))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text(t('الاسم المكتوب لا يربط الورقة إلا بتأكيدك.', 'A written name is only linked when you confirm it.'), key: const ValueKey('rv.candidate'), style: AppType.meta(context)),
            ),
          choices.isEmpty
              ? AppPrimaryButton(key: const ValueKey('rv.assign'), label: t('البحث عن الطالب', 'Find the student'), icon: Icons.person_search_outlined, busy: widget.busy, onPressed: widget.busy ? null : widget.onSearch)
              : OutlinedButton.icon(
                  key: const ValueKey('rv.assign'),
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.min))),
                  onPressed: widget.busy ? null : widget.onSearch,
                  icon: const Icon(Icons.search_rounded, size: AppIconSize.md),
                  label: Text(t('طالب آخر', 'Someone else'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
          const SizedBox(height: AppSpace.xxs),
          Row(children: [
            Expanded(child: _Quiet(key: const ValueKey('rv.retake'), icon: Icons.replay_rounded, label: t('إعادة التصوير', 'Retake scan'), onTap: widget.busy ? null : widget.onRetake)),
            Expanded(child: _Quiet(key: const ValueKey('rv.later'), icon: Icons.schedule_rounded, label: t('أقرّر لاحقًا', 'Decide later'), onTap: widget.busy ? null : widget.onLater, color: c.textMedium)),
          ]),
        ]),
      ),
    );
  }
}

class _WrittenNumber extends StatelessWidget {
  const _WrittenNumber({required this.crop, required this.value});
  final Future<Uint8List?>? crop;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('rv.written'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.background, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (crop != null)
          SizedBox(
            height: 88,
            child: FutureBuilder<Uint8List?>(
              future: crop,
              builder: (_, s) => s.data == null ? const SizedBox.shrink() : ColoredBox(color: Colors.white, child: Image.memory(s.data!, fit: BoxFit.contain, gaplessPlayback: true, excludeFromSemantics: true)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(children: [
            Expanded(child: Text(t('الرقم المكتوب', 'The number as written'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
            Flexible(child: Text(value.isEmpty ? '—' : value, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.bodyStrong(context))),
          ]),
        ),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.candidate, this.top = false, this.keyHint, this.pending = false, this.onTap});
  final RevisionCandidate candidate;
  final bool top, pending;
  final String? keyHint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = revisionAccent(context);
    final x = candidate;
    final tone = x.alreadyMatched ? c.textMedium : accent;
    final initial = x.name.trim().isEmpty ? '?' : x.name.trim().characters.first;
    return Semantics(
      button: true,
      child: Material(
        color: top ? accent.withValues(alpha: .1) : c.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: top ? accent.withValues(alpha: .55) : c.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Container(
                  width: AppTouch.min - AppSpace.xxs,
                  height: AppTouch.min - AppSpace.xxs,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tone.withValues(alpha: .14), shape: BoxShape.circle),
                  child: Text(initial, style: AppType.bodyStrong(context).copyWith(color: tone)),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(x.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: x.alreadyMatched ? c.textMedium : null)),
                    if (x.alreadyMatched)
                      Text(t('له ورقة أخرى في هذه المراجعة', 'Already has a paper in this revision'), key: const ValueKey('rv.choice.taken'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.warning))
                    else if (top)
                      Text(t('الأقرب لما كُتب', 'Closest to what was written'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: accent)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                if (pending)
                  SizedBox(width: AppIconSize.md, height: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: accent))
                else if (keyHint != null)
                  Container(
                    width: AppSpace.lg,
                    height: AppSpace.lg,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
                    child: Text(keyHint!, style: AppType.meta(context)),
                  )
                else if (!x.alreadyMatched)
                  Icon(Icons.check_rounded, color: tone),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({super.key, required this.icon, required this.label, this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.min)), foregroundColor: color == null ? null : WidgetStatePropertyAll(color)),
        onPressed: onTap,
        icon: Icon(icon, size: AppIconSize.sm),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}
