// HelpInfoButton (workstream f3): the "i" in a page header. It opens the page's help (a bottom sheet on phones, a side
// panel on wide screens): title, summary, the sections with what each button does, "Ask about this page" and, when
// the entry has one, "Take the tour".
//
//   HelpInfoButton(pageId: 'home.student')      // hidden when the page has no help (bundled index / cached catalogue)
//
// Showing the button costs no request (HelpService.has reads the bundled index); the catalogue is fetched when the
// button is TAPPED ([showHelpForPage]): the sheet opens at once from the cache, else with a skeleton.
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
      unawaited(HelpService.instance.loadLocal(userKey: u, orgId: _orgOfContext())); // local only: no request
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

  bool get _has => _user != null && HelpService.instance.has(widget.pageId);

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
    if (!_has) return const SizedBox.shrink();
    // The tour only starts from an entry already cached (no fetch on open); it waits for the first tap's fetch.
    final cached = HelpService.instance.entry(widget.pageId);
    if (cached != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeAutoTour(cached));
      });
    }
    final label = AppConfig.lang == 'ar' ? 'معلومات عن هذه الصفحة' : 'About this page';
    return ParentComponent(
      featureKey: helpInfoFeatureKey,
      child: ChromeIconButton(
        icon: Icons.info_outline_rounded,
        label: label,
        onTap: () => unawaited(showHelpForPage(context, widget.pageId)),
      ),
    );
  }
}

/// Width from which the help opens as a side panel instead of a bottom sheet.
const helpPanelFrom = 900.0;

/// Opens [entry] as a bottom sheet (phones) or a side panel (wide screens).
Future<void> showHelpFor(BuildContext context, HelpEntry entry) =>
    _present(context, (ctx) => HelpEntryView(entry: entry, onClose: () => Navigator.pop(ctx), host: context));

/// The Info button's tap: opens the help of [pageId] and fetches the catalogue now (this is the ONLY place that asks
/// the server): from the cache at once when there is one, else a skeleton and then the content.
Future<void> showHelpForPage(BuildContext context, String pageId) {
  final user = helpUserKeyOf(context);
  if (user == null) return Future.value();
  final org = _orgOfContext();
  return _present(context, (ctx) => HelpPageBody(pageId: pageId, userKey: user, orgId: org, host: context, onClose: () => Navigator.pop(ctx)));
}

Future<void> _present(BuildContext context, Widget Function(BuildContext ctx) body) {
  final wide = MediaQuery.sizeOf(context).width >= helpPanelFrom;
  if (!wide) return showAppSheet<void>(context, body);
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
              child: SingleChildScrollView(child: body(ctx)),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

/// The sheet of one page: shows the cached entry at once, else a skeleton while [HelpService.ensure] fetches the
/// catalogue, else a friendly "not available" line with Retry (offline, or the page has no entry for this person).
class HelpPageBody extends StatefulWidget {
  const HelpPageBody({super.key, required this.pageId, required this.userKey, this.orgId, required this.onClose, this.host});

  final String pageId, userKey;
  final int? orgId;
  final VoidCallback onClose;
  final BuildContext? host;

  @override
  State<HelpPageBody> createState() => _HelpPageBodyState();
}

class _HelpPageBodyState extends State<HelpPageBody> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    HelpService.instance.addListener(_changed);
    _load(false);
  }

  @override
  void dispose() {
    HelpService.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _load(bool force) {
    _loading = true;
    unawaited(HelpService.instance
        .ensure(userKey: widget.userKey, orgId: widget.orgId, force: force)
        .whenComplete(() => mounted ? setState(() => _loading = false) : null));
    if (mounted && context.mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = HelpService.instance.entry(widget.pageId);
    if (e != null) return HelpEntryView(entry: e, onClose: widget.onClose, host: widget.host);
    final ar = AppConfig.lang == 'ar';
    final c = context.colors;
    final title = ar ? 'معلومات عن هذه الصفحة' : 'About this page';
    if (_loading) {
      return AppSheetContent(title: title, children: [
        Semantics(
          label: ar ? 'جارٍ التحميل' : 'Loading',
          child: Column(children: [
            for (final w in const [1.0, 0.9, 0.6]) ...[
              FractionallySizedBox(
                widthFactor: w,
                child: Container(
                    height: 16, decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip))),
              ),
              AppSpace.gapSm,
            ],
          ]),
        ),
      ]);
    }
    return AppSheetContent(title: title, children: [
      Text(
        ar ? 'المساعدة غير متاحة الآن. تأكد من الاتصال بالإنترنت ثم حاول مرة أخرى.' : 'Help is not available right now. Check your connection and try again.',
        style: appText(15, c: c.textMedium, h: 1.6),
      ),
      AppSpace.gapMd,
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
        onPressed: () => _load(true),
        child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
      ),
    ]);
  }
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

/// Whether a menu item for [pageId] should be offered (the live room's "More" menu, a course space's top actions):
/// false for guests, when `help.info` is off, or when the page has no help. No request; open it with [showHelpForPage].
bool helpAvailableForMenu(BuildContext context, String pageId) {
  final u = helpUserKeyOf(context);
  if (u == null || AppConfig.disableList.contains(helpInfoFeatureKey)) return false;
  unawaited(HelpService.instance.loadLocal(userKey: u, orgId: _orgOfContext()));
  return HelpService.instance.has(pageId);
}
