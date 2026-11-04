// HelpInfoButton (workstream f3): the "i" in a page header. It opens the page's help (a bottom sheet on phones, a side
// panel on wide screens): title, summary, the sections with what each button does, "Ask about this page" and, when
// the entry has one, "Take the tour".
//
//   HelpInfoButton(pageId: 'home.student')      // hidden when the server has no entry for this page and role
//
// Headers take an optional `helpPageId` and draw this button (ScreenAppBar, OrgPageHeader, HomeHeader, the shell's
// top bar); a page whose id has no entry shows nothing. Kill switch `help.info` (ParentComponent featureKey).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/app_mode.dart';
import '../../../design/app_kit.dart' show appText, showAppSheet, AppSheetContent;
import '../../../design/app_tokens.dart';
import '../../../design/chrome_button.dart';
import '../../../utils/widget/parent_component.dart';
import '../../auth/auth_provider.dart';
import '../guest/guest_state.dart';
import '../rag/chat/assistant_page_context.dart' show openAssistantForPage;
import 'help_models.dart';
import 'help_service.dart';
import 'help_tour.dart';

/// The kill-switch key that hides every Info button (added to the server's feature catalogue).
const helpInfoFeatureKey = 'help.info';

/// Who is asking, for the cache key: the signed-in user's id, or null (guest / signed out = no help).
typedef HelpUserKey = String? Function(BuildContext context);

String? _defaultUserKey(BuildContext context) {
  if (GuestState.active) return null;
  try {
    final a = Provider.of<MyAuthProvider>(context, listen: false);
    final u = a.currentUser;
    return u == null || !a.isAuthenticated ? null : '${u.id}';
  } on ProviderNotFoundException {
    return null;
  }
}

/// Tests replace it (no providers in a plain widget test).
HelpUserKey helpUserKeyOf = _defaultUserKey;

int? _orgOfContext() {
  try {
    final m = AppModeController.instance;
    return m.isOrg ? m.currentOrgId : null;
  } catch (_) {
    return null;
  }
}

class HelpInfoButton extends StatefulWidget {
  const HelpInfoButton({super.key, required this.pageId, this.autoTour = true});

  /// The page's stable id (`AppRoutes` ids, `home.<role>/<tab>`, or an id from the help seed).
  final String pageId;

  /// Offer the guided tour on the first visit of a page that has one and whose targets are on screen.
  final bool autoTour;

  @override
  State<HelpInfoButton> createState() => _HelpInfoButtonState();
}

class _HelpInfoButtonState extends State<HelpInfoButton> {
  String? _user;
  bool _tourChecked = false;

  @override
  void initState() {
    super.initState();
    HelpService.instance.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = helpUserKeyOf(context);
    if (u != _user) {
      _user = u;
      _tourChecked = false;
    }
    if (u != null && !AppConfig.disableList.contains(helpInfoFeatureKey)) {
      unawaited(HelpService.instance.ensure(userKey: u, orgId: _orgOfContext()));
    }
  }

  @override
  void dispose() {
    HelpService.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  HelpEntry? get _entry => _user == null ? null : HelpService.instance.entry(widget.pageId);

  Future<void> _maybeAutoTour(HelpEntry e) async {
    if (_tourChecked || !widget.autoTour || !e.hasTour || _user == null) return;
    _tourChecked = true;
    final user = _user!;
    if (await HelpService.instance.tourSeen(user, widget.pageId)) return;
    await Future<void>.delayed(const Duration(milliseconds: 700)); // let the page settle
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (helpTourStepsOn(e.tour, pageId: widget.pageId).isEmpty) return; // targets not wired / not on screen
    await HelpService.instance.markTourSeen(user, widget.pageId);
    if (mounted) await runHelpTour(context, e.tour, pageId: widget.pageId);
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    if (e == null) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeAutoTour(e));
    });
    final label = AppConfig.lang == 'ar' ? 'معلومات عن هذه الصفحة' : 'About this page';
    return ParentComponent(
      featureKey: helpInfoFeatureKey,
      child: ChromeIconButton(
        icon: Icons.info_outline_rounded,
        label: label,
        onTap: () => showHelpFor(context, e),
      ),
    );
  }
}

/// Width from which the help opens as a side panel instead of a bottom sheet.
const helpPanelFrom = 900.0;

/// Opens [entry] as a bottom sheet (phones) or a side panel (wide screens).
Future<void> showHelpFor(BuildContext context, HelpEntry entry) {
  final wide = MediaQuery.sizeOf(context).width >= helpPanelFrom;
  if (!wide) {
    return showAppSheet<void>(context, (ctx) => HelpEntryView(entry: entry, onClose: () => Navigator.pop(ctx), host: context));
  }
  final ar = AppConfig.lang == 'ar';
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: ar ? 'إغلاق' : 'Close',
    barrierColor: Colors.black38,
    transitionDuration: AppMotion.of(context).base,
    pageBuilder: (ctx, _, _) => Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: 440,
          height: double.infinity,
          child: Material(
            color: ctx.colors.cardBg,
            child: SafeArea(
              child: SingleChildScrollView(
                child: HelpEntryView(entry: entry, onClose: () => Navigator.pop(ctx), host: context),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

/// The help content: pure over [entry] (the layout test pumps it directly).
class HelpEntryView extends StatelessWidget {
  const HelpEntryView({super.key, required this.entry, required this.onClose, this.host, this.onAsk, this.onTour});

  final HelpEntry entry;
  final VoidCallback onClose;

  /// The page the sheet was opened from (the tour and the assistant start there); null in tests.
  final BuildContext? host;
  final VoidCallback? onAsk, onTour;

  bool get _ar => AppConfig.lang == 'ar';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = AppConfig.lang;
    final title = entry.title.of(lang);
    final askLabel = _ar ? 'اسأل عن هذه الصفحة' : 'Ask about this page';
    final tourLabel = _ar ? 'ابدأ الجولة' : 'Take the tour';
    final ask = onAsk ?? () => _ask(context);
    final tour = onTour ?? () => _tour(context);
    final summary = entry.summary.of(lang);
    return AppSheetContent(
      title: title.isEmpty ? (_ar ? 'معلومات عن هذه الصفحة' : 'About this page') : title,
      children: [
        if (summary.isNotEmpty) Text(summary, style: appText(15, c: c.textMedium, h: 1.6)),
        for (final s in entry.sections) ...[
          AppSpace.gapMd,
          Semantics(
            header: true,
            child: Text(s.title.of(lang), style: appText(16, w: FontWeight.w700, c: c.textDark, h: 1.4)),
          ),
          if (!s.body.isEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(s.body.of(lang), style: appText(14, c: c.textMedium, h: 1.6)),
          ],
          for (final i in s.items) ...[
            const SizedBox(height: AppSpace.xs),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.label.of(lang), style: appText(14, w: FontWeight.w700, c: c.textDark, h: 1.4)),
                const SizedBox(height: 2),
                Text(i.text.of(lang), style: appText(13, c: c.textMedium, h: 1.5)),
              ]),
            ),
          ],
        ],
        AppSpace.gapLg,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: ask,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(askLabel),
          ),
          if (entry.hasTour)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              onPressed: tour,
              icon: const Icon(Icons.tour_outlined, size: 18),
              label: Text(tourLabel),
            ),
        ]),
      ],
    );
  }

  void _ask(BuildContext context) {
    onClose();
    helpAskAboutPage(host ?? context, entry);
  }

  void _tour(BuildContext context) {
    final h = host;
    onClose();
    if (h == null) return;
    // after the sheet has left the screen the targets are visible again
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (h.mounted) unawaited(runHelpTour(h, entry.tour, pageId: entry.pageId));
    });
  }
}

/// "Ask about this page": opens the app assistant on a new chat with a question about the page typed in.
void helpAskAboutPage(BuildContext context, HelpEntry entry) =>
    openAssistantForPage(context, pageId: entry.pageId, pageTitle: entry.title.of(AppConfig.lang));

/// The help entry of [pageId] for a menu item where a header has no room for the Info button (the live room's
/// "More" menu). Null for guests, when `help.info` is off, or while the catalogue is not loaded (it loads on the
/// way; the caller rebuilds on [HelpService]).
HelpEntry? helpEntryForMenu(BuildContext context, String pageId) {
  final u = helpUserKeyOf(context);
  if (u == null || AppConfig.disableList.contains(helpInfoFeatureKey)) return null;
  unawaited(HelpService.instance.ensure(userKey: u, orgId: _orgOfContext()));
  return HelpService.instance.entry(pageId);
}
