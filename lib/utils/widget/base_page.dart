import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/alfaheem_canvas.dart'; // Alfaheem A-007 (sync/hooks.py)
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/upload/upload_progress_footer.dart';
import '../helpers.dart';
import 'app_bar.dart';

class BasePage extends StatelessWidget {
  const BasePage({
    super.key,
    required this.child,
    this.background,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBar,
    this.useWebCard = false,
    this.maxWith,
    this.width,
    this.enableFooterWidget = true,
  });

  /// The card's max width in pixels — older pages; new code names a [width] role instead.
  final double? maxWith;

  /// The page-width role of a [useWebCard] page (D-304): form · reading · content · wide · full. It wins over
  /// [maxWith]; with neither, the card is [AppWidth.content].
  final AppWidth? width;
  final Widget child;
  final Color? background;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  final bool useWebCard;
  final bool enableFooterWidget;

  /// Stacks the app-wide background-upload progress footer above whatever
  /// bottomNavigationBar the page already wants, so a video upload started
  /// on any screen stays visible while the teacher navigates elsewhere.
  /// Renders nothing when there are no active uploads.
  Widget? _footerWith(Widget? existing) {
    if (existing == null) return const UploadProgressFooter();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [const UploadProgressFooter(), existing],
    );
  }

  /// Several BasePages can be alive in the same route at once (admin shell,
  /// tabs, stacked pages), and every FloatingActionButton is a Hero. Duplicate
  /// hero tags throw "multiple heroes share the same tag", so FABs are excluded
  /// from hero transitions here instead of relying on unique tags per page.
  Widget? _buildFab() {
    final fab = floatingActionButton;
    if (fab == null) return null;
    return HeroMode(enabled: false, child: fab);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the disable list changes (silent FCM push / theme fetch).
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.disableListVersion,
      builder: (context, _, _) => AlfaheemCanvas.page(context, explicit: background, child: _buildPage(context)), // Alfaheem A-007
    );
  }

  Widget _buildPage(BuildContext context) {
    Color bg=background ??AlfaheemCanvas.pageFill(context); // Alfaheem A-007
    if (key case ValueKey(
    value: final v,
    ) when AppConfig.disableList.contains(v)) {
      // "Coming soon" (D-622): a vector mark on a peach block, the title in the editorial face — no emoji, no gold
      return Scaffold(
        appBar: ScreenAppBar(title: (key as ValueKey).value.toString().tr),
        backgroundColor: bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.form.max),
              child: AppBlock(
                tone: AppBlockTone.peach,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.rocket_launch_rounded, size: AppIconSize.hero),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      'coming_soon'.tr,
                      textAlign: TextAlign.center,
                      style: AppType.headline(context).copyWith(color: AppBlock.colorsOf(context).ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    // A card page's header lies across the whole page, on top, like every other page's header (D-575): inside the card it
    // was a second floating box on the page.
    final headerOutside = useWebCard && appBar != null && context.width >= AppWidth.phoneMax;
    final webCard = useWebCard && context.width >= AppWidth.phoneMax;
    // D-948: the canvas is ONE solid colour (the server's background role, light and dark): no pattern, no gradient
    // behind pages. Depth comes from the paper cards and the blocks on it.
    Widget w = Scaffold(
      appBar: headerOutside ? null : appBar,
      backgroundColor:bg,
      floatingActionButton: _buildFab(), // was: floatingActionButton
      bottomNavigationBar:
      enableFooterWidget ? _footerWith(bottomNavigationBar) : null,
      body: Directionality(
        textDirection: Helpers.pageDirection,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.colors.radiusXL),
          ),
          child: child,
        ),
      ),
    );

    if (webCard) {
      return Directionality(
        textDirection: Helpers.pageDirection,
        child: Scaffold(
          backgroundColor: bg,
          appBar: headerOutside ? appBar : null,
          // NOTE: no footer here — `w` below already carries it via its own
          // bottomNavigationBar, and `w` is what actually renders in this
          // branch (nested inside the centered card).
          // The card is measured against the room the page really has (a shell's sidebar or rail already took its
          // share), not the window: the role's width, less a gutter each side once the room is narrower (D-304).
          // The margins are the plain canvas (D-948): the paper cards and blocks on it carry the depth.
          body: LayoutBuilder(builder: (context, box) {
            final cardWidth = width != null
                ? width!.inside(box.maxWidth)
                : AppWidth.content.inside(box.maxWidth, max: maxWith);
            // The body runs the whole height: a margin here stopped the scrolling content 12 px short of the window's
            // edge, cut off by an invisible line (D-560).
            return Align(
              alignment: AlignmentDirectional.topCenter,
              child: SizedBox(width: cardWidth, height: double.infinity, child: w),
            );
          }),
        ),
      );
    }

    return SafeArea(child: w);
  }
}