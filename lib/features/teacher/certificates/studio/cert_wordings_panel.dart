// features/teacher/certificates/studio/cert_wordings_panel.dart
//
// The studio's wording library (D-402): ready preambles from the server, read with sample values, inserted as an ordinary
// text block that is then edited like any other. Plain values in, plain values out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../design/app_kit.dart';
import '../../../admin/admin_common.dart' show t;
import 'cert_engine_api.dart';
import 'cert_engine_presets.dart' show certSampleValues;

/// [text] with its `{{variables}}` replaced by [values] (an unknown one stays as it is).
String certFillSample(String text, Map<String, String> values) => text.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) => values[m.group(1)] ?? m.group(0)!);

class CertWordingsPanel extends StatefulWidget {
  const CertWordingsPanel({super.key, required this.lang, required this.load, required this.onInsert});
  final String lang;
  final Future<List<CertPreamble>> Function() load;
  final ValueChanged<CertPreamble> onInsert;

  @override
  State<CertWordingsPanel> createState() => _CertWordingsPanelState();
}

class _CertWordingsPanelState extends State<CertWordingsPanel> {
  late final Future<List<CertPreamble>> _items = widget.load();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<List<CertPreamble>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero));
        final list = snap.data ?? const <CertPreamble>[];
        if (list.isEmpty) return Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppEmpty(icon: Icons.format_quote_rounded, title: t('لا توجد صيغ الآن', 'No wordings right now')));
        final samples = certSampleValues(widget.lang, const ['hours']);
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpace.sm),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, i) {
            if (i == 0) return Text(t('أدرج صيغة ثم عدّلها كأي نص. يمكن إضافة أكثر من صيغة.', 'Insert a wording, then edit it like any text. You can add more than one.'), style: appText(12.5, c: c.textMedium));
            final p = list[i - 1];
            return Container(
              key: ValueKey('cert-wording-${p.key}'),
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(p.title(widget.lang), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  certFillSample(p.text(widget.lang), samples),
                  textDirection: widget.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  style: appText(12.5, c: c.textMedium),
                ),
                const SizedBox(height: AppSpace.xs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    key: ValueKey('cert-insert-${p.key}'),
                    onPressed: () => widget.onInsert(p),
                    icon: const Icon(Icons.add_rounded, size: AppIconSize.sm),
                    label: Text(t('إدراج', 'Insert')),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}
