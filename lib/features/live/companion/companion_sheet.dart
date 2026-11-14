// lib/features/live/companion/companion_sheet.dart — the "Your phone" sheet of the room and the pre-join page (D-520).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/live/companion/companion_core.dart';
import 'package:flutter_education_app/features/live/companion/companion_link.dart';
import 'package:flutter_education_app/features/live/companion/companion_parts.dart';

/// The link the QR carries (the web app: this site; a desktop app: the public site).
String companionQrUrl(String secret) => AppLink.companion(secret).url(kIsWeb ? Uri.base.origin : AppLink.site);

Future<void> showCompanionSheet(BuildContext context, CompanionLink link) => showAppSheet<void>(context, (ctx) => _CompanionSheet(link: link));

class _CompanionSheet extends StatefulWidget {
  const _CompanionSheet({required this.link});
  final CompanionLink link;

  @override
  State<_CompanionSheet> createState() => _CompanionSheetState();
}

class _CompanionSheetState extends State<_CompanionSheet> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.link,
      builder: (context, _) {
        final l = widget.link;
        final running = l.stage != CompanionStage.idle;
        final sources = l.request?.sources ?? l.wanted;
        return CompanionChooserBody(
          stage: l.stage,
          sources: running ? sources : l.wanted,
          busy: l.busy,
          error: l.error,
          noPhone: l.noPhoneToPush,
          qrUrl: l.secret == null ? null : companionQrUrl(l.secret!),
          showQr: _showQr,
          onShowQr: () => setState(() => _showQr = true),
          onToggle: (s) {
            final next = {...(running ? sources : l.wanted)};
            next.contains(s) ? next.remove(s) : next.add(s);
            if (l.stage == CompanionStage.active) {
              if (next.isNotEmpty) l.setSources(next);
            } else {
              l.setWanted(next);
            }
          },
          onAsk: l.ask,
          onCancel: l.cancel,
          onStop: () {
            l.stop();
            Navigator.of(context).maybePop();
          },
        );
      },
    );
  }
}

/// The pre-join page's picker: returns the sources to ask for at Join (empty: none).
Future<Set<CompanionSource>?> pickCompanionSources(BuildContext context, Set<CompanionSource> current) {
  return showAppSheet<Set<CompanionSource>>(context, (ctx) => _PreJoinPicker(initial: current));
}

class _PreJoinPicker extends StatefulWidget {
  const _PreJoinPicker({required this.initial});
  final Set<CompanionSource> initial;

  @override
  State<_PreJoinPicker> createState() => _PreJoinPickerState();
}

class _PreJoinPickerState extends State<_PreJoinPicker> {
  late final Set<CompanionSource> _picked = widget.initial.isEmpty ? {CompanionSource.camera} : {...widget.initial};

  @override
  Widget build(BuildContext context) => CompanionChooserBody(
        stage: CompanionStage.idle,
        sources: _picked,
        onToggle: (s) => setState(() => _picked.contains(s) ? _picked.remove(s) : _picked.add(s)),
        onAsk: () => Navigator.of(context).pop({..._picked}),
        onCancel: () => Navigator.of(context).pop(),
        onStop: () {},
      );
}
