// lib/design/shell_pins.dart — pin any page to a dashboard's tabs, and give every tab a colour box (D-1170).
//
//   ShellPinButton(title:)          the pin in a pushed page's header (AppHeader, AppPageHeader, OrgPageHeader draw
//                                   it next to the focus toggle). It shows only on a page opened INSIDE a role tab;
//                                   one tap pins the page, a second unpins it (both with Undo).
//   ShellPinScope                   the pins and tab colours of one person on one dashboard, kept on the device
//                                   (SharedPreferences `ui.shell_tabs.v1.<user>|<dashboard>`, like D-1157).
//   ShellColorBox                   a tab's icon on a filled tile of its colour (the "colour box").
//   showShellTabsSheet              Customize tabs: a colour per tab, reorder / unpin the pinned pages.
//   ShellPinStrip                   phones: the pins as a row of colour boxes at the top of the Home tab (the
//                                   bottom bar keeps its 5 tabs, D-1160); a tap opens the page inside Home.
//
// Where the pins go: on the desktop sidebar and the tablet rail every pin is its own entry under "Pinned" (AppShell
// adds them after the role's tabs, each with its own back stack); on phones they are the Home strip.
//
// How a pin is rebuilt: the page's own route builder, captured when it is pinned. A page with a URL (a named route,
// AppRoutes.locationOf) is rebuilt after a restart through the app's router; any other page keeps its pin, and the
// pin reconnects by itself the next time the person opens that page (matched by its title) — until then the tab
// says so and offers Unpin. Colours are the theme's own roles (ShellTabColor), never a new palette.
// Pure parts are unit-tested in test/ui/shell_pins_test.dart.
library;

import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart' show Trans;
import '../config/theme/theme_config_provider.dart';
import 'app_contrast.dart' show contrastRatio;
import 'app_kit.dart' show showAppSheet;
import 'app_notice.dart' show showAppNotice;
import 'app_sheet_header.dart' show AppSheetContent;
import 'app_states.dart' show AppEmpty;
import 'app_tokens.dart';
import 'app_shell_nav.dart';
import 'chrome_button.dart' show ChromeIconButton;

// ─────────────────────────────────────────────────────────────────────────────
// Colours
// ─────────────────────────────────────────────────────────────────────────────

/// The colours a tab can wear. [primary] is the theme's brand colour; the others are hues far enough apart to tell
/// steps of a flow at a glance (the theme's own accents sit too close: peach / rust, success / primary), each drawn
/// at one weight so no box shouts louder than another, and lifted in dark mode. Not a theme preset: only these boxes
/// use them.
enum ShellTabColor { primary, coral, amber, sky, indigo, plum, slate }

extension ShellTabColorRole on ShellTabColor {
  /// The hue of every colour but [ShellTabColor.primary] (degrees).
  double get _hue => switch (this) {
        ShellTabColor.primary => 0,
        ShellTabColor.coral => 8,
        ShellTabColor.amber => 36,
        ShellTabColor.sky => 200,
        ShellTabColor.indigo => 230,
        ShellTabColor.plum => 285,
        ShellTabColor.slate => 210,
      };

  /// The box's fill.
  Color fill(ThemeConfigProvider c) {
    if (this == ShellTabColor.primary) return c.primary;
    final sat = this == ShellTabColor.slate ? 0.14 : 0.58;
    return HSLColor.fromAHSL(1, _hue, sat, c.isDark ? 0.62 : 0.45).toColor();
  }

  /// The glyph on the box: the light or the dark ink, whichever reads better on the fill.
  Color ink(ThemeConfigProvider c) => shellInkOn(fill(c), light: c.onHero, dark: c.charcoalDark);

  String get labelKey => 'shell_color_$name';
}

/// [light] or [dark], whichever has more contrast on [fill].
Color shellInkOn(Color fill, {required Color light, required Color dark}) =>
    contrastRatio(light, fill) >= contrastRatio(dark, fill) ? light : dark;

/// A new pin's colour: the next one round the palette after the primary (the brand stays the tabs' default look).
ShellTabColor shellPinDefaultColor(int index) {
  const ring = [ShellTabColor.coral, ShellTabColor.sky, ShellTabColor.amber, ShellTabColor.indigo, ShellTabColor.plum, ShellTabColor.slate];
  return ring[index % ring.length];
}

ShellTabColor? shellTabColorByName(Object? name) {
  for (final v in ShellTabColor.values) {
    if (v.name == name) return v;
  }
  return null;
}

/// A tab's icon on a filled, rounded tile of its colour.
class ShellColorBox extends StatelessWidget {
  const ShellColorBox({super.key, required this.icon, required this.color, this.size = 28, this.iconSize = AppIconSize.md});

  final IconData icon;
  final ShellTabColor color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.fill(c), borderRadius: AppRadius.chipAll),
      child: Icon(icon, size: iconSize, color: color.ink(c)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model + store
// ─────────────────────────────────────────────────────────────────────────────

/// The id prefix of a pinned page's tab (`pin_k3x9`); never a role tab's key. It survives the `<home>/<tab>` URL
/// (AppRoutes.tabLocation turns `_` into `-` and back).
const kShellPinTabPrefix = 'pin_';

/// At most this many pins per dashboard: the sidebar stays a list to scan, not a second menu.
const kShellPinMax = 8;

/// One pinned page. [route] / [args]: the named route that rebuilds it after a restart (null: only the builder of
/// this session, or the next visit, can).
@immutable
class ShellPin {
  const ShellPin({required this.id, required this.title, this.route, this.args});

  final String id;
  final String title;
  final String? route;
  final Object? args;

  String get tabId => '$kShellPinTabPrefix$id';

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'route': ?route, 'args': ?args};

  static ShellPin? parse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    final route = j['route'];
    return ShellPin(id: id, title: title, route: route is String && route.isNotEmpty ? route : null, args: j['args']);
  }

  @override
  bool operator ==(Object other) =>
      other is ShellPin && other.id == id && other.title == title && other.route == route && other.args == args;

  @override
  int get hashCode => Object.hash(id, title, route, args);
}

/// The pins and colours of one dashboard, as stored (pure: encoded, decoded and edited in tests).
@immutable
class ShellPinState {
  const ShellPinState({this.pins = const [], this.colors = const {}});

  final List<ShellPin> pins;

  /// Tab id (a role tab's key, or a pin's [ShellPin.tabId]) → its colour. A role tab without one keeps the shell's
  /// own look; a pin always has one.
  final Map<String, ShellTabColor> colors;

  factory ShellPinState.fromJson(Map<String, dynamic> j) {
    final pins = <ShellPin>[];
    final seen = <String>{};
    for (final p in j['pins'] is List ? j['pins'] as List : const []) {
      final pin = ShellPin.parse(p);
      if (pin != null && seen.add(pin.id) && pins.length < kShellPinMax) pins.add(pin);
    }
    final colors = <String, ShellTabColor>{};
    final cj = j['colors'];
    if (cj is Map) {
      cj.forEach((k, v) {
        final col = shellTabColorByName(v);
        if (k is String && col != null) colors[k] = col;
      });
    }
    return ShellPinState(pins: pins, colors: colors);
  }

  Map<String, dynamic> toJson() => {
        'pins': [for (final p in pins) p.toJson()],
        'colors': {for (final e in colors.entries) e.key: e.value.name},
      };

  ShellTabColor? colorOf(String tabId) => colors[tabId];

  ShellPin? byId(String id) {
    for (final p in pins) {
      if (p.id == id) return p;
    }
    return null;
  }

  ShellPin? byTitle(String title) {
    for (final p in pins) {
      if (p.title == title) return p;
    }
    return null;
  }

  /// Adds [pin] at the end with the next colour of the ring (no-op when full or already there).
  ShellPinState add(ShellPin pin) {
    if (pins.length >= kShellPinMax || byId(pin.id) != null) return this;
    return ShellPinState(
      pins: [...pins, pin],
      colors: {...colors, pin.tabId: colors[pin.tabId] ?? shellPinDefaultColor(pins.length)},
    );
  }

  ShellPinState remove(String id) => ShellPinState(
        pins: [for (final p in pins) if (p.id != id) p],
        colors: {for (final e in colors.entries) if (e.key != '$kShellPinTabPrefix$id') e.key: e.value},
      );

  /// Moves pin [id] by [delta] places (clamped).
  ShellPinState move(String id, int delta) {
    final i = pins.indexWhere((p) => p.id == id);
    if (i < 0) return this;
    final j = (i + delta).clamp(0, pins.length - 1);
    if (i == j) return this;
    final l = [...pins];
    final p = l.removeAt(i);
    l.insert(j, p);
    return ShellPinState(pins: l, colors: colors);
  }

  /// [color] null: back to the default look (a pin goes back to its ring colour).
  ShellPinState withColor(String tabId, ShellTabColor? color) {
    final next = {...colors};
    if (color != null) {
      next[tabId] = color;
    } else {
      final i = pins.indexWhere((p) => p.tabId == tabId);
      if (i >= 0) {
        next[tabId] = shellPinDefaultColor(i);
      } else {
        next.remove(tabId);
      }
    }
    return ShellPinState(pins: pins, colors: next);
  }

  /// Every role tab back to its own look; the pins back to their ring colours.
  ShellPinState resetColors() =>
      ShellPinState(pins: pins, colors: {for (var i = 0; i < pins.length; i++) pins[i].tabId: shellPinDefaultColor(i)});
}

/// A new pin id: short, unique enough per dashboard, letters and digits only (it ends up in a URL).
String shellNewPinId([DateTime? now]) => (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36);

/// The builder that draws [route]'s page again, or null when the route kind keeps it private.
WidgetBuilder? shellPageBuilderOf(Route<dynamic>? route) {
  if (route is MaterialPageRoute) return route.builder;
  if (route is CupertinoPageRoute) return route.builder;
  if (route is PageRouteBuilder) {
    final r = route;
    return (context) => r.pageBuilder(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation);
  }
  return null;
}

/// The named route that rebuilds [route] after a restart, when it has one the router can build from plain values.
({String name, Object? args})? shellRestorableRoute(Route<dynamic>? route) {
  final s = route?.settings;
  final name = s?.name;
  if (route == null || name == null || !name.startsWith('/') || shellRouteGoesToRoot(route)) return null;
  final a = s!.arguments;
  if (a != null && a is! int && a is! String && a is! bool && a is! double) return null;
  return (name: name, args: a);
}

/// One dashboard's pins and colours for one person, loaded once and written on every change.
class ShellPinScope extends ChangeNotifier {
  ShellPinScope(this.key);

  /// `<user id>|<dashboard>`.
  final String key;

  ShellPinState _state = const ShellPinState();
  bool _loaded = false;
  bool _loading = false;

  /// The builders this session knows, by pin id (captured on pin, rebuilt from a route, or rebound on a visit).
  final Map<String, WidgetBuilder> _builders = {};

  ShellPinState get state => _state;
  List<ShellPin> get pins => _state.pins;
  bool get loaded => _loaded;

  String get prefKey => 'ui.shell_tabs.v1.$key';

  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(prefKey);
      if (s != null && s.isNotEmpty) {
        final j = jsonDecode(s);
        if (j is Map) _state = ShellPinState.fromJson(j.cast<String, dynamic>());
      }
    } catch (_) {
      // no storage (private window): the pins of this session only
    }
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  void _set(ShellPinState next) {
    if (identical(next, _state)) return;
    _state = next;
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(prefKey, jsonEncode(_state.toJson()));
    } catch (_) {
      // see load
    }
  }

  WidgetBuilder? builderOf(String id) => _builders[id];

  /// Pins [title]; false when the dashboard already holds [kShellPinMax] pins.
  bool pin({required String title, required WidgetBuilder builder, String? route, Object? args}) {
    if (pins.length >= kShellPinMax) return false;
    final id = shellNewPinId();
    _builders[id] = builder;
    _set(_state.add(ShellPin(id: id, title: title, route: route, args: args)));
    return true;
  }

  /// Unpins [id] and returns what puts it back exactly (place and colour), for Undo.
  VoidCallback? unpin(String id) {
    final before = _state;
    final b = _builders[id];
    if (before.byId(id) == null) return null;
    _set(before.remove(id));
    return () {
      if (b != null) _builders[id] = b;
      _set(before);
    };
  }

  void move(String id, int delta) => _set(_state.move(id, delta));
  void setColor(String tabId, ShellTabColor? color) => _set(_state.withColor(tabId, color));
  void resetColors() => _set(_state.resetColors());

  /// A page was opened again: a pin of the same title that lost its builder (a restart) gets it back.
  void rebind(String title, WidgetBuilder builder) {
    final p = _state.byTitle(title);
    if (p == null || _builders.containsKey(p.id)) return;
    _builders[p.id] = builder;
    notifyListeners();
  }

  /// The builder of [pin] now: this session's, else the router's for its route (cached), else null.
  WidgetBuilder? resolve(ShellPin pin, BuildContext context) {
    final known = _builders[pin.id];
    if (known != null) return known;
    final name = pin.route;
    if (name == null) return null;
    final gen = Navigator.maybeOf(context, rootNavigator: true)?.widget.onGenerateRoute;
    final b = shellPageBuilderOf(gen?.call(RouteSettings(name: name, arguments: pin.args)));
    if (b != null) _builders[pin.id] = b;
    return b;
  }

  @visibleForTesting
  void debugSet(ShellPinState s) {
    _state = s;
    _loaded = true;
    notifyListeners();
  }
}

/// Every dashboard's scope, by key (one per person and dashboard while the app runs).
class ShellPins {
  ShellPins._();

  static final _scopes = <String, ShellPinScope>{};

  static ShellPinScope scope(String key) => _scopes.putIfAbsent(key, () => ShellPinScope(key)..load());

  @visibleForTesting
  static void debugReset() => _scopes.clear();
}

// ─────────────────────────────────────────────────────────────────────────────
// The pin button
// ─────────────────────────────────────────────────────────────────────────────

/// The header's pin: on a page opened inside a role tab (not a tab's own first page, not a page outside a shell).
class ShellPinButton extends StatelessWidget {
  const ShellPinButton({super.key, required this.title});

  /// The page's title: the pinned tab's name.
  final String title;

  @override
  Widget build(BuildContext context) {
    final tabs = ShellScope.maybeOf(context);
    final scope = tabs?.pins;
    final route = ModalRoute.of(context);
    if (tabs == null || scope == null || route == null || title.trim().isEmpty) return const SizedBox.shrink();
    final tab = tabs.holding(route);
    if (tab == null || tab.pinned || identical(tab.root, route)) return const SizedBox.shrink();
    final builder = shellPageBuilderOf(route);
    if (builder == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: scope,
      builder: (context, _) {
        final pin = scope.state.byTitle(title);
        if (pin != null && scope.builderOf(pin.id) == null) {
          // a pin of this page lost its builder (a restart): this visit reconnects it
          WidgetsBinding.instance.addPostFrameCallback((_) => scope.rebind(title, builder));
        }
        return ChromeIconButton(
          key: const ValueKey('shell.pin'),
          icon: pin != null ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          label: pin != null ? 'shell_unpin'.tr : 'shell_pin'.tr,
          onTap: () {
            if (pin != null) {
              final undo = scope.unpin(pin.id);
              showAppNotice('shell_unpinned_notice'.tr, actionLabel: 'shell_undo'.tr, onAction: undo);
              return;
            }
            final r = shellRestorableRoute(route);
            if (!scope.pin(title: title, builder: builder, route: r?.name, args: r?.args)) {
              showAppNotice('shell_pins_full'.tr, error: true);
              return;
            }
            final added = scope.state.byTitle(title);
            showAppNotice('shell_pinned_notice'.tr,
                icon: Icons.push_pin_rounded,
                actionLabel: 'shell_undo'.tr,
                onAction: added == null ? null : () => scope.unpin(added.id));
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A pinned page
// ─────────────────────────────────────────────────────────────────────────────

/// A pin's page: its builder's page, or — a page that cannot be rebuilt until it is visited again — a calm note with
/// Unpin.
class ShellPinnedPage extends StatelessWidget {
  const ShellPinnedPage({super.key, required this.scope, required this.pin});

  final ShellPinScope scope;
  final ShellPin pin;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: scope,
        builder: (context, _) {
          final b = scope.resolve(pin, context);
          if (b != null) return b(context);
          return Material(
            color: context.colors.background,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: AppEmpty(
                    icon: Icons.push_pin_outlined,
                    title: pin.title,
                    message: 'shell_pin_reconnect_body'.tr,
                    actionLabel: 'shell_unpin'.tr,
                    onAction: () => scope.unpin(pin.id),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Customize tabs
// ─────────────────────────────────────────────────────────────────────────────

/// One row of the sheet: a tab as the shell draws it.
@immutable
class ShellTabEntry {
  const ShellTabEntry({required this.tabId, required this.label, required this.icon, this.pinId});

  final String tabId;
  final String label;
  final IconData icon;

  /// Set for a pinned page (it can move and be unpinned).
  final String? pinId;
}

/// Customize tabs: a colour per tab and, for the pinned pages, their order and Unpin.
Future<void> showShellTabsSheet(BuildContext context, {required ShellPinScope scope, required List<ShellTabEntry> tabs}) =>
    showAppSheet<void>(context, (_) => ShellTabsSheet(scope: scope, tabs: tabs));

class ShellTabsSheet extends StatelessWidget {
  const ShellTabsSheet({super.key, required this.scope, required this.tabs});

  final ShellPinScope scope;

  /// The role's tabs (in order); the pins are read from [scope] so the list follows Unpin / reorder.
  final List<ShellTabEntry> tabs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: scope,
      builder: (context, _) {
        final pins = scope.pins;
        // the kit's sheet body: the tinted header, the gutter, and a scroll once 5 tabs and 8 pins outgrow a phone
        return AppSheetContent(
          title: 'shell_customize'.tr,
          subtitle: 'shell_customize_hint'.tr,
          icon: Icons.palette_outlined,
          children: [
            const SizedBox(height: AppSpace.sm),
            for (final t in tabs) _ShellTabRow(scope: scope, entry: t),
            if (pins.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text('shell_group_pinned'.tr, style: AppType.label(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              for (var i = 0; i < pins.length; i++)
                _ShellTabRow(
                  scope: scope,
                  entry: ShellTabEntry(tabId: pins[i].tabId, label: pins[i].title, icon: Icons.push_pin_rounded, pinId: pins[i].id),
                  first: i == 0,
                  last: i == pins.length - 1,
                ),
            ],
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: scope.resetColors,
                icon: const Icon(Icons.format_color_reset_outlined, size: AppIconSize.md),
                label: Text('shell_reset_colors'.tr),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShellTabRow extends StatelessWidget {
  const _ShellTabRow({required this.scope, required this.entry, this.first = true, this.last = true});

  final ShellPinScope scope;
  final ShellTabEntry entry;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = scope.state.colorOf(entry.tabId);
    final pinId = entry.pinId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              current == null
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(entry.icon, size: AppIconSize.md, color: c.textMedium),
                    )
                  : ShellColorBox(icon: entry.icon, color: current),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(entry.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              ),
              if (pinId != null) ...[
                IconButton(
                  tooltip: 'shell_move_up'.tr,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: first ? null : () => scope.move(pinId, -1),
                  icon: const Icon(Icons.arrow_upward_rounded, size: AppIconSize.md),
                ),
                IconButton(
                  tooltip: 'shell_move_down'.tr,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: last ? null : () => scope.move(pinId, 1),
                  icon: const Icon(Icons.arrow_downward_rounded, size: AppIconSize.md),
                ),
                IconButton(
                  tooltip: 'shell_unpin'.tr,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: () {
                    final undo = scope.unpin(pinId);
                    showAppNotice('shell_unpinned_notice'.tr, actionLabel: 'shell_undo'.tr, onAction: undo);
                  },
                  icon: Icon(Icons.push_pin_outlined, size: AppIconSize.md, color: c.danger),
                ),
              ],
            ]),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              if (pinId == null)
                _Swatch(
                  label: 'shell_color_default'.tr,
                  selected: current == null,
                  onTap: () => scope.setColor(entry.tabId, null),
                  child: Icon(Icons.block_rounded, size: AppIconSize.sm, color: c.textMedium),
                ),
              for (final col in ShellTabColor.values)
                _Swatch(
                  label: col.labelKey.tr,
                  selected: current == col,
                  onTap: () => scope.setColor(entry.tabId, col),
                  fill: col.fill(c),
                  child: current == col ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: col.ink(c)) : null,
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// One colour to choose: a 48 px target around a 28 px dot, ringed when chosen.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.selected, required this.onTap, this.fill, this.child});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? fill;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: AppTouch.min / 2,
          child: SizedBox(
            width: AppTouch.min,
            height: AppTouch.min,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill ?? c.inputBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.textDark : c.divider,
                    width: selected ? AppBorder.focus : AppBorder.hairline,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phones: the strip on Home
// ─────────────────────────────────────────────────────────────────────────────

/// The pins as colour boxes in one row that scrolls sideways, then the Customize button. A tap opens the page; a long
/// press opens Customize.
class ShellPinStrip extends StatelessWidget {
  const ShellPinStrip({super.key, required this.pins, required this.colors, required this.onOpen, required this.onCustomize});

  final List<ShellPin> pins;
  final Map<String, ShellTabColor> colors;
  final ValueChanged<ShellPin> onOpen;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'shell_group_pinned'.tr,
      child: SizedBox(
        height: AppTouch.min + AppSpace.sm,
        child: Row(children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xxs, bottom: AppSpace.xxs),
              children: [
                for (var i = 0; i < pins.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                    child: _StripChip(
                      pin: pins[i],
                      color: colors[pins[i].tabId] ?? shellPinDefaultColor(i),
                      onTap: () => onOpen(pins[i]),
                      onLongPress: onCustomize,
                    ),
                  ),
              ],
            ),
          ),
          // always in reach, however many pins scroll beside it
          IconButton(
            key: const ValueKey('shell.strip.customize'),
            tooltip: 'shell_customize'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: onCustomize,
            icon: Icon(Icons.palette_outlined, size: AppIconSize.md, color: c.textMedium),
          ),
          const SizedBox(width: AppSpace.xxs),
        ]),
      ),
    );
  }
}

class _StripChip extends StatelessWidget {
  const _StripChip({required this.pin, required this.color, required this.onTap, required this.onLongPress});

  final ShellPin pin;
  final ShellTabColor color;
  final VoidCallback onTap, onLongPress;

  /// The widest a chip grows before its title ends in an ellipsis.
  static const double _maxW = 200;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = color.fill(c);
    return Semantics(
      button: true,
      label: pin.title,
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: StadiumBorder(side: BorderSide(color: fill, width: AppBorder.focus)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min, maxWidth: _maxW),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs + 2, end: AppSpace.md),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ShellColorBox(icon: Icons.push_pin_rounded, color: color, size: 32, iconSize: AppIconSize.sm),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(pin.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// True for a pinned page's tab id.
bool isShellPinTab(String tabId) => tabId.startsWith(kShellPinTabPrefix);
