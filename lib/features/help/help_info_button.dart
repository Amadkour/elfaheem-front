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

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/rag/chat/assistant_page_context.dart' show openAssistantForPage;
import 'package:flutter_education_app/features/help/help_models.dart';
import 'package:flutter_education_app/features/help/help_service.dart';
import 'package:flutter_education_app/features/help/help_tour.dart';

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

String _defaultHelpRole(BuildContext context) {
  String? platform;
  try {
    platform = Provider.of<MyAuthProvider>(context, listen: false).currentUser?.role;
  } on ProviderNotFoundException {
    platform = null;
  }
  var inOrg = false, orgAdmin = false;
  try {
    final m = AppModeController.instance;
    final cur = m.isOrg ? m.current : null;
    inOrg = cur != null;
    final roles = cur?['roles'];
    orgAdmin = roles is List && roles.any((r) => '$r' == 'org_admin');
  } catch (_) {}
  return HelpService.helpRoleOf(platform, inOrg: inOrg, orgAdmin: orgAdmin);
}

/// The person's help role (server rules); tests replace it.
String Function(BuildContext context) helpRoleOfContext = _defaultHelpRole;

/// Local only (no request): bundled index + cached catalogue for this person, role and organization.
Future<void> _loadHelpLocal(BuildContext context, String user) =>
    HelpService.instance.loadLocal(userKey: user, orgId: _orgOfContext(), helpRole: helpRoleOfContext(context));

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
      unawaited(_loadHelpLocal(context, u)); // local only: no request
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
    barrierColor: appScrimColor(context),
    transitionDuration: AppMotion.of(context).slow,
    pageBuilder: (ctx, _, _) => Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: _HelpPanel(child: body(ctx)),
    ),
    // the panel slides in from the end edge on the kit's ease-out and leaves the same way
    transitionBuilder: (ctx, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: AppEase.out, reverseCurve: AppEase.outReversed);
      return SlideTransition(
        position: Tween<Offset>(begin: Offset(ar ? -_HelpPanel.slide : _HelpPanel.slide, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// The wide-screen help: a floating paper panel at the end edge (radius sheet, a warm hairline, the modal shadow) at
/// a sheet's reading measure, the body scrolling inside.
class _HelpPanel extends StatelessWidget {
  const _HelpPanel({required this.child});

  /// The panel's width: a phone sheet's reading measure beside the page.
  static double get _width => AppWidth.form.max - AppSpace.xxxl * 2 - AppSpace.md;

  /// How far (a fraction of its width) the panel travels in.
  static const double slide = 0.4;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: SizedBox(
            width: _width,
            height: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                border: Border.all(color: c.divider, width: AppBorder.hairline),
                boxShadow: AppElevation.of(context, 4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                child: Material(
                  type: MaterialType.transparency,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in const [1.0, 0.9, 0.6]) ...[
              FractionallySizedBox(widthFactor: w, child: const AppSkeletonBox(height: AppSpace.md)),
              AppSpace.gapSm,
            ],
            AppSpace.gapMd,
            const FractionallySizedBox(widthFactor: 0.45, child: AppSkeletonBox(height: AppSpace.md + AppSpace.xxs)),
            AppSpace.gapSm,
            const AppSkeletonBox(height: AppSpace.xxl + AppSpace.md, radius: AppRadius.card),
          ]),
        ),
      ]);
    }
    return AppSheetContent(title: title, children: [
      Text(
        ar ? 'المساعدة غير متاحة الآن. تأكد من الاتصال بالإنترنت ثم حاول مرة أخرى.' : 'Help is not available right now. Check your connection and try again.',
        style: AppType.body(context).copyWith(color: c.textMedium, height: 1.6),
      ),
      AppSpace.gapMd,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(label: ar ? 'إعادة المحاولة' : 'Retry', icon: Icons.refresh_rounded, onPressed: () => _load(true)),
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
        // the lede: what the page is for, in the ink (the sections under it read in the muted body)
        if (summary.isNotEmpty) Text(summary, style: AppType.body(context).copyWith(color: c.textDark, height: 1.6)),
        for (final s in entry.sections) ...[
          const SizedBox(height: AppSpace.lg),
          Semantics(
            header: true,
            child: Text(s.title.of(lang), style: AppType.section(context).copyWith(color: c.textDark)),
          ),
          if (!s.body.isEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(s.body.of(lang), style: AppType.body(context).copyWith(color: c.textMedium, height: 1.6)),
          ],
          if (s.items.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            HelpItemList(items: [for (final i in s.items) (label: i.label.of(lang), text: i.text.of(lang))]),
          ],
        ],
        const SizedBox(height: AppSpace.xl),
        AppButtonRow(
          primary: AppButton.primary(label: askLabel, icon: Icons.auto_awesome_rounded, onPressed: ask),
          secondary: [
            if (entry.hasTour) AppButton.secondary(label: tourLabel, icon: Icons.tour_outlined, onPressed: tour),
          ],
        ),
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
  unawaited(_loadHelpLocal(context, u));
  return HelpService.instance.has(pageId);
}

/// A help section's named items (a button, a field, a tab) on ONE paper card, parted by warm hairlines: the name in
/// the strong ink, what it does under it in the muted body. Plain values (the layout harness pumps it).
class HelpItemList extends StatelessWidget {
  const HelpItemList({super.key, required this.items});

  final List<({String label, String text})> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var n = 0; n < items.length; n++) ...[
          if (n > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(items[n].label, style: AppType.bodyStrong(context).copyWith(color: c.textDark, height: 1.4)),
              if (items[n].text.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(items[n].text, style: AppType.body(context).copyWith(color: c.textMedium, height: 1.5)),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}
