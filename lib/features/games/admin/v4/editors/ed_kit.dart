// lib/features/games/admin/v4/editors/ed_kit.dart — the small parts every item editor shares (Games v4 T65).
//
//   EdText        a text field that owns its controller (initial value in, every keystroke out)
//   EdBilingual   Arabic + English text pair for the prompt-like fields {ar, en}
//   EdRow         one list row: the fields, a remove button
//   EdAdd         the "Add …" button under a list
//   EdSelect      a dropdown over (value, label) pairs
//   edIndexKey    key for a list row, so removing row i rebuilds the rows after it with their own text
//
// Editors are plain values in, a new body out: `XEditor(body:, onChanged:)`. They read no provider and call no API,
// so test/games/v4_admin_test.dart pumps them directly through `expectNoLayoutErrors`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

Json jmap(Object? x) => x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
List<Json> jlist(Object? x) => x is List ? [for (final e in x) jmap(e)] : <Json>[];
int jint(Object? x, [int d = 0]) => x is num ? x.toInt() : d;

Key edIndexKey(String tag, int i, int n) => ValueKey('$tag-$i-$n');

class EdText extends StatefulWidget {
  const EdText({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines = 1,
    this.ltr = false,
    this.helper,
    this.readOnly = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? helper;
  final int maxLines;
  final bool ltr;
  final bool readOnly;

  @override
  State<EdText> createState() => _EdTextState();
}

class _EdTextState extends State<EdText> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EdText old) {
    super.didUpdateWidget(old);
    // a change that came from outside (a picker filled it): follow it; a keystroke already equals the controller
    if (widget.value != _c.text && widget.value != old.value) _c.text = widget.value;
  }

  @override
  Widget build(BuildContext context) => AppField(
        controller: _c,
        label: widget.label,
        hint: widget.hint,
        helper: widget.helper,
        maxLines: widget.maxLines,
        ltr: widget.ltr,
        readOnly: widget.readOnly,
        onChanged: widget.onChanged,
      );
}

/// `{ar, en}` as two fields.
class EdBilingual extends StatelessWidget {
  const EdBilingual({super.key, required this.label, required this.value, required this.onChanged, this.maxLines = 2});

  final String label;
  final Json value;
  final ValueChanged<Json> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    void set(String k, String v) => onChanged({...value, k: v.trim().isEmpty ? null : v});
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EdText(label: '$label · ${t('عربي', 'Arabic')}', value: '${value['ar'] ?? ''}', maxLines: maxLines, onChanged: (v) => set('ar', v)),
      AppSpace.gapSm,
      EdText(label: '$label · ${t('إنجليزي', 'English')}', value: '${value['en'] ?? ''}', maxLines: maxLines, ltr: true, onChanged: (v) => set('en', v)),
    ]);
  }
}

class EdRow extends StatelessWidget {
  const EdRow({super.key, required this.child, this.onRemove, this.leading});

  final Widget child;
  final VoidCallback? onRemove;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null) ...[leading!, AppSpace.gapSm],
            Expanded(child: child),
            if (onRemove != null)
              AppIconButton(icon: Icons.delete_outline_rounded, tooltip: t('حذف', 'Remove'), onPressed: onRemove),
          ]),
        ),
      );
}

class EdAdd extends StatelessWidget {
  const EdAdd({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.tonal(label: label, icon: Icons.add_rounded, onPressed: onPressed),
      );
}

class EdSelect<T> extends StatelessWidget {
  const EdSelect({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  final String label;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppFieldLabel(label),
        AppDropdown<T>(
          value: value,
          items: [for (final o in options) DropdownMenuItem<T>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ]);
}

/// A section title inside an editor.
class EdTitle extends StatelessWidget {
  const EdTitle(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: AppType.bodyStrong(context)),
          if (hint != null) Text(hint!, style: AppType.meta(context)),
        ]),
      );
}
