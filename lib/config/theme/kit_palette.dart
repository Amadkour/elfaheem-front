// The redesign kit's palette (KIT_SPEC.md §2.1): the model of the theme response's `colors.kit` map. No colour
// value lives here; the defaults are `kit_palette_defaults.dart`, copied from tool/redesign/kit_palette.json.
//
// Widgets read `context.colors.kit` (a [KitColors]): the only place that looks at the brightness.

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show immutable;

/// "#AARRGGBB", the shape the theme cache writes.
String kitHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// "#RRGGBB" or "#AARRGGBB" -> a colour; anything else -> null.
Color? kitParse(Object? v) {
  if (v is! String) return null;
  final h = v.startsWith('#') ? v.substring(1) : v;
  if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(h)) return null;
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

Color _leaf(Map<String, dynamic> j, String key, Color fallback) => kitParse(j[key]) ?? fallback;

Map<String, dynamic> _sub(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
}

/// A colour with its soft background and its text colour (light and dark).
@immutable
class KitTriple {
  const KitTriple({
    required this.c,
    required this.tint,
    required this.ink,
    required this.tintDark,
    required this.inkDark,
  });

  factory KitTriple.fromJson(Map<String, dynamic> j, KitTriple fb) => KitTriple(
        c: _leaf(j, 'c', fb.c),
        tint: _leaf(j, 'tint', fb.tint),
        ink: _leaf(j, 'ink', fb.ink),
        tintDark: _leaf(j, 'tint_dark', fb.tintDark),
        inkDark: _leaf(j, 'ink_dark', fb.inkDark),
      );

  final Color c, tint, ink, tintDark, inkDark;

  Map<String, dynamic> toJson() => {
        'c': kitHex(c),
        'tint': kitHex(tint),
        'ink': kitHex(ink),
        'tint_dark': kitHex(tintDark),
        'ink_dark': kitHex(inkDark),
      };
}

/// A subject: a [KitTriple] plus [fg], the label drawn ON the solid colour (a book cover).
@immutable
class KitSubject extends KitTriple {
  const KitSubject({
    required super.c,
    required super.tint,
    required super.ink,
    required super.tintDark,
    required super.inkDark,
    required this.fg,
  });

  factory KitSubject.fromJson(Map<String, dynamic> j, KitSubject fb) {
    final t = KitTriple.fromJson(j, fb);
    return KitSubject(
      c: t.c,
      tint: t.tint,
      ink: t.ink,
      tintDark: t.tintDark,
      inkDark: t.inkDark,
      fg: _leaf(j, 'fg', fb.fg),
    );
  }

  final Color fg;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'fg': kitHex(fg)};
}

/// One student area or one role accent.
@immutable
class KitAccentSet {
  const KitAccentSet({
    required this.a,
    required this.b,
    required this.heroA,
    required this.heroMid,
    required this.tint,
    required this.ink,
    required this.tintDark,
    required this.inkDark,
    required this.btnA,
    required this.btnB,
    required this.btnFg,
  });

  factory KitAccentSet.fromJson(Map<String, dynamic> j, KitAccentSet fb) => KitAccentSet(
        a: _leaf(j, 'a', fb.a),
        b: _leaf(j, 'b', fb.b),
        heroA: _leaf(j, 'hero_a', fb.heroA),
        heroMid: _leaf(j, 'hero_mid', fb.heroMid),
        tint: _leaf(j, 'tint', fb.tint),
        ink: _leaf(j, 'ink', fb.ink),
        tintDark: _leaf(j, 'tint_dark', fb.tintDark),
        inkDark: _leaf(j, 'ink_dark', fb.inkDark),
        btnA: _leaf(j, 'btn_a', fb.btnA),
        btnB: _leaf(j, 'btn_b', fb.btnB),
        btnFg: _leaf(j, 'btn_fg', fb.btnFg),
      );

  final Color a, b, heroA, heroMid, tint, ink, tintDark, inkDark, btnA, btnB, btnFg;

  Map<String, dynamic> toJson() => {
        'a': kitHex(a),
        'b': kitHex(b),
        'hero_a': kitHex(heroA),
        'hero_mid': kitHex(heroMid),
        'tint': kitHex(tint),
        'ink': kitHex(ink),
        'tint_dark': kitHex(tintDark),
        'ink_dark': kitHex(inkDark),
        'btn_a': kitHex(btnA),
        'btn_b': kitHex(btnB),
        'btn_fg': kitHex(btnFg),
      };
}

/// The keys of `kit.brand`, camelCase.
@immutable
class KitBrand {
  const KitBrand({
    required this.ink,
    required this.deep,
    required this.primary,
    required this.partner,
    required this.warm,
    required this.hot,
    required this.primaryTint,
    required this.primaryInk,
    required this.primaryTintDark,
    required this.primaryInkDark,
    required this.partnerTint,
    required this.partnerInk,
    required this.partnerTintDark,
    required this.partnerInkDark,
    required this.warmTint,
    required this.warmInk,
    required this.warmTintDark,
    required this.warmInkDark,
    required this.hotTint,
    required this.hotInk,
    required this.hotTintDark,
    required this.hotInkDark,
    required this.page,
    required this.text,
    required this.muted,
    required this.line,
    required this.well,
    required this.track,
    required this.fieldEdge,
    required this.topBar,
    required this.warmOnDark,
    required this.hotA,
    required this.hotB,
    required this.hotFg,
  });

  factory KitBrand.fromJson(Map<String, dynamic> j, KitBrand fb) => KitBrand(
        ink: _leaf(j, 'ink', fb.ink),
        deep: _leaf(j, 'deep', fb.deep),
        primary: _leaf(j, 'primary', fb.primary),
        partner: _leaf(j, 'partner', fb.partner),
        warm: _leaf(j, 'warm', fb.warm),
        hot: _leaf(j, 'hot', fb.hot),
        primaryTint: _leaf(j, 'primary_tint', fb.primaryTint),
        primaryInk: _leaf(j, 'primary_ink', fb.primaryInk),
        primaryTintDark: _leaf(j, 'primary_tint_dark', fb.primaryTintDark),
        primaryInkDark: _leaf(j, 'primary_ink_dark', fb.primaryInkDark),
        partnerTint: _leaf(j, 'partner_tint', fb.partnerTint),
        partnerInk: _leaf(j, 'partner_ink', fb.partnerInk),
        partnerTintDark: _leaf(j, 'partner_tint_dark', fb.partnerTintDark),
        partnerInkDark: _leaf(j, 'partner_ink_dark', fb.partnerInkDark),
        warmTint: _leaf(j, 'warm_tint', fb.warmTint),
        warmInk: _leaf(j, 'warm_ink', fb.warmInk),
        warmTintDark: _leaf(j, 'warm_tint_dark', fb.warmTintDark),
        warmInkDark: _leaf(j, 'warm_ink_dark', fb.warmInkDark),
        hotTint: _leaf(j, 'hot_tint', fb.hotTint),
        hotInk: _leaf(j, 'hot_ink', fb.hotInk),
        hotTintDark: _leaf(j, 'hot_tint_dark', fb.hotTintDark),
        hotInkDark: _leaf(j, 'hot_ink_dark', fb.hotInkDark),
        page: _leaf(j, 'page', fb.page),
        text: _leaf(j, 'text', fb.text),
        muted: _leaf(j, 'muted', fb.muted),
        line: _leaf(j, 'line', fb.line),
        well: _leaf(j, 'well', fb.well),
        track: _leaf(j, 'track', fb.track),
        fieldEdge: _leaf(j, 'field_edge', fb.fieldEdge),
        topBar: _leaf(j, 'top_bar', fb.topBar),
        warmOnDark: _leaf(j, 'warm_on_dark', fb.warmOnDark),
        hotA: _leaf(j, 'hot_a', fb.hotA),
        hotB: _leaf(j, 'hot_b', fb.hotB),
        hotFg: _leaf(j, 'hot_fg', fb.hotFg),
      );

  final Color ink;
  final Color deep;
  final Color primary;
  final Color partner;
  final Color warm;
  final Color hot;
  final Color primaryTint;
  final Color primaryInk;
  final Color primaryTintDark;
  final Color primaryInkDark;
  final Color partnerTint;
  final Color partnerInk;
  final Color partnerTintDark;
  final Color partnerInkDark;
  final Color warmTint;
  final Color warmInk;
  final Color warmTintDark;
  final Color warmInkDark;
  final Color hotTint;
  final Color hotInk;
  final Color hotTintDark;
  final Color hotInkDark;
  final Color page;
  final Color text;
  final Color muted;
  final Color line;
  final Color well;
  final Color track;
  final Color fieldEdge;
  final Color topBar;
  final Color warmOnDark;
  final Color hotA;
  final Color hotB;
  final Color hotFg;

  Map<String, dynamic> toJson() => {
        'ink': kitHex(ink),
        'deep': kitHex(deep),
        'primary': kitHex(primary),
        'partner': kitHex(partner),
        'warm': kitHex(warm),
        'hot': kitHex(hot),
        'primary_tint': kitHex(primaryTint),
        'primary_ink': kitHex(primaryInk),
        'primary_tint_dark': kitHex(primaryTintDark),
        'primary_ink_dark': kitHex(primaryInkDark),
        'partner_tint': kitHex(partnerTint),
        'partner_ink': kitHex(partnerInk),
        'partner_tint_dark': kitHex(partnerTintDark),
        'partner_ink_dark': kitHex(partnerInkDark),
        'warm_tint': kitHex(warmTint),
        'warm_ink': kitHex(warmInk),
        'warm_tint_dark': kitHex(warmTintDark),
        'warm_ink_dark': kitHex(warmInkDark),
        'hot_tint': kitHex(hotTint),
        'hot_ink': kitHex(hotInk),
        'hot_tint_dark': kitHex(hotTintDark),
        'hot_ink_dark': kitHex(hotInkDark),
        'page': kitHex(page),
        'text': kitHex(text),
        'muted': kitHex(muted),
        'line': kitHex(line),
        'well': kitHex(well),
        'track': kitHex(track),
        'field_edge': kitHex(fieldEdge),
        'top_bar': kitHex(topBar),
        'warm_on_dark': kitHex(warmOnDark),
        'hot_a': kitHex(hotA),
        'hot_b': kitHex(hotB),
        'hot_fg': kitHex(hotFg),
      };
}

/// The keys of `kit.status`, camelCase.
@immutable
class KitStatus {
  const KitStatus({
    required this.live,
    required this.liveFill,
    required this.liveTint,
    required this.liveInk,
    required this.liveTintDark,
    required this.liveInkDark,
    required this.ok,
    required this.okTint,
    required this.okInk,
    required this.okTintDark,
    required this.okInkDark,
    required this.warn,
    required this.warnTint,
    required this.warnInk,
    required this.warnTintDark,
    required this.warnInkDark,
    required this.lock,
    required this.lockInk,
    required this.lockDark,
    required this.lockInkDark,
    required this.error,
    required this.errorInk,
    required this.errorTint,
    required this.errorTintDark,
    required this.errorInkDark,
  });

  factory KitStatus.fromJson(Map<String, dynamic> j, KitStatus fb) => KitStatus(
        live: _leaf(j, 'live', fb.live),
        liveFill: _leaf(j, 'live_fill', fb.liveFill),
        liveTint: _leaf(j, 'live_tint', fb.liveTint),
        liveInk: _leaf(j, 'live_ink', fb.liveInk),
        liveTintDark: _leaf(j, 'live_tint_dark', fb.liveTintDark),
        liveInkDark: _leaf(j, 'live_ink_dark', fb.liveInkDark),
        ok: _leaf(j, 'ok', fb.ok),
        okTint: _leaf(j, 'ok_tint', fb.okTint),
        okInk: _leaf(j, 'ok_ink', fb.okInk),
        okTintDark: _leaf(j, 'ok_tint_dark', fb.okTintDark),
        okInkDark: _leaf(j, 'ok_ink_dark', fb.okInkDark),
        warn: _leaf(j, 'warn', fb.warn),
        warnTint: _leaf(j, 'warn_tint', fb.warnTint),
        warnInk: _leaf(j, 'warn_ink', fb.warnInk),
        warnTintDark: _leaf(j, 'warn_tint_dark', fb.warnTintDark),
        warnInkDark: _leaf(j, 'warn_ink_dark', fb.warnInkDark),
        lock: _leaf(j, 'lock', fb.lock),
        lockInk: _leaf(j, 'lock_ink', fb.lockInk),
        lockDark: _leaf(j, 'lock_dark', fb.lockDark),
        lockInkDark: _leaf(j, 'lock_ink_dark', fb.lockInkDark),
        error: _leaf(j, 'error', fb.error),
        errorInk: _leaf(j, 'error_ink', fb.errorInk),
        errorTint: _leaf(j, 'error_tint', fb.errorTint),
        errorTintDark: _leaf(j, 'error_tint_dark', fb.errorTintDark),
        errorInkDark: _leaf(j, 'error_ink_dark', fb.errorInkDark),
      );

  final Color live;
  final Color liveFill;
  final Color liveTint;
  final Color liveInk;
  final Color liveTintDark;
  final Color liveInkDark;
  final Color ok;
  final Color okTint;
  final Color okInk;
  final Color okTintDark;
  final Color okInkDark;
  final Color warn;
  final Color warnTint;
  final Color warnInk;
  final Color warnTintDark;
  final Color warnInkDark;
  final Color lock;
  final Color lockInk;
  final Color lockDark;
  final Color lockInkDark;
  final Color error;
  final Color errorInk;
  final Color errorTint;
  final Color errorTintDark;
  final Color errorInkDark;

  Map<String, dynamic> toJson() => {
        'live': kitHex(live),
        'live_fill': kitHex(liveFill),
        'live_tint': kitHex(liveTint),
        'live_ink': kitHex(liveInk),
        'live_tint_dark': kitHex(liveTintDark),
        'live_ink_dark': kitHex(liveInkDark),
        'ok': kitHex(ok),
        'ok_tint': kitHex(okTint),
        'ok_ink': kitHex(okInk),
        'ok_tint_dark': kitHex(okTintDark),
        'ok_ink_dark': kitHex(okInkDark),
        'warn': kitHex(warn),
        'warn_tint': kitHex(warnTint),
        'warn_ink': kitHex(warnInk),
        'warn_tint_dark': kitHex(warnTintDark),
        'warn_ink_dark': kitHex(warnInkDark),
        'lock': kitHex(lock),
        'lock_ink': kitHex(lockInk),
        'lock_dark': kitHex(lockDark),
        'lock_ink_dark': kitHex(lockInkDark),
        'error': kitHex(error),
        'error_ink': kitHex(errorInk),
        'error_tint': kitHex(errorTint),
        'error_tint_dark': kitHex(errorTintDark),
        'error_ink_dark': kitHex(errorInkDark),
      };
}
/// The whole `colors.kit` map.
@immutable
class KitPalette {
  const KitPalette({
    required this.v,
    required this.brand,
    required this.accents,
    required this.status,
    required this.areas,
    required this.roles,
    required this.subjects,
  });

  /// Every leaf missing or malformed in [j] comes from [fallback], key by key. Unknown keys are ignored.
  factory KitPalette.fromJson(Map<String, dynamic> j, {required KitPalette fallback}) {
    Map<String, T> group<T>(String key, Map<String, T> fb, T Function(Map<String, dynamic>, T) parse) {
      final g = _sub(j, key);
      return {for (final e in fb.entries) e.key: parse(_sub(g, e.key), e.value)};
    }

    return KitPalette(
      v: fallback.v,
      brand: KitBrand.fromJson(_sub(j, 'brand'), fallback.brand),
      accents: group('accents', fallback.accents, KitTriple.fromJson),
      status: KitStatus.fromJson(_sub(j, 'status'), fallback.status),
      areas: group('areas', fallback.areas, KitAccentSet.fromJson),
      roles: group('roles', fallback.roles, KitAccentSet.fromJson),
      subjects: group('subjects', fallback.subjects, KitSubject.fromJson),
    );
  }

  final int v;
  final KitBrand brand;

  /// sun mint grape pink lime sky
  final Map<String, KitTriple> accents;
  final KitStatus status;

  /// home learn exam games store quran nahw sched chat money me
  final Map<String, KitAccentSet> areas;

  /// teacher parent admin super
  final Map<String, KitAccentSet> roles;

  /// math physics chem bio english arabic qudurat code quran islamic other
  final Map<String, KitSubject> subjects;

  /// "#AARRGGBB" leaves, the same shape as the server's.
  Map<String, dynamic> toJson() => {
        'v': v,
        'brand': brand.toJson(),
        'accents': {for (final e in accents.entries) e.key: e.value.toJson()},
        'status': status.toJson(),
        'areas': {for (final e in areas.entries) e.key: e.value.toJson()},
        'roles': {for (final e in roles.entries) e.key: e.value.toJson()},
        'subjects': {for (final e in subjects.entries) e.key: e.value.toJson()},
      };

  @override
  bool operator ==(Object other) => other is KitPalette && _deepEq(toJson(), other.toJson());

  @override
  int get hashCode => toJson().toString().hashCode;
}

bool _deepEq(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final o = b[e.key];
    final v = e.value;
    if (v is Map<String, dynamic> && o is Map<String, dynamic>) {
      if (!_deepEq(v, o)) return false;
    } else if (v != o) {
      return false;
    }
  }
  return true;
}

// ── The reading side ─────────────────────────────────────────────────────────────────────────────────────────────

enum AppAccent { sun, mint, grape, pink, lime, sky }

enum AppArea { home, learn, exam, games, store, quran, nahw, sched, chat, money, me }

/// JSON keys: teacher parent admin super.
enum AppRoleAccent { teacher, parent, admin, superAdmin }

extension AppRoleAccentKey on AppRoleAccent {
  String get key => this == AppRoleAccent.superAdmin ? 'super' : name;
}

/// A colour, its soft background and its text colour, resolved for the brightness.
@immutable
class KitTone {
  const KitTone(this.color, this.tint, this.ink);

  final Color color, tint, ink;
}

/// A [KitAccentSet] resolved for the brightness.
@immutable
class KitSet {
  const KitSet({
    required this.a,
    required this.b,
    required this.heroA,
    required this.heroMid,
    required this.heroEnd,
    required this.tint,
    required this.ink,
    required this.btnA,
    required this.btnB,
    required this.btnFg,
  });

  final Color a, b, heroA, heroMid, heroEnd, tint, ink, btnA, btnB, btnFg;

  KitTone get tone => KitTone(a, tint, ink);

  /// RadialGradient stops 0 · 0.45 · 1.
  List<Color> get heroStops => [heroA, heroMid, heroEnd];

  /// 120°: btnA -> btnB.
  LinearGradient get button => LinearGradient(begin: _from120, end: _to120, colors: [btnA, btnB]);

  @override
  bool operator ==(Object other) =>
      other is KitSet && other.a == a && other.b == b && other.heroA == heroA && other.heroMid == heroMid &&
      other.heroEnd == heroEnd && other.tint == tint && other.ink == ink && other.btnA == btnA &&
      other.btnB == btnB && other.btnFg == btnFg;

  @override
  int get hashCode => Object.hash(a, b, heroA, heroMid, heroEnd, tint, ink, btnA, btnB, btnFg);
}

// 120° in CSS terms (0° = up, clockwise): from the bottom-left towards the top-right, a little flatter than 45°.
const Alignment _from120 = Alignment(-1, -0.58);
const Alignment _to120 = Alignment(1, 0.58);

/// The theme's own dark surfaces, which the kit reuses instead of a new hex (P14).
abstract interface class KitSurfaces {
  Color get inputBg;
  Color get divider;
  Color get fieldEdge;
}

/// The view widgets read (`context.colors.kit`).
class KitColors {
  const KitColors(this.palette, {required this.dark, this.surfaces});

  final KitPalette palette;
  final bool dark;

  /// The dark surface roles; null = the brand's light values (tests).
  final KitSurfaces? surfaces;

  KitBrand get _b => palette.brand;
  KitStatus get _s => palette.status;

  // brand
  Color get ink => _b.ink;
  Color get deep => _b.deep;
  Color get primary => _b.primary;
  Color get partner => _b.partner;
  Color get warm => _b.warm;
  Color get hot => _b.hot;
  Color get warmOnDark => _b.warmOnDark;
  Color get topBar => _b.topBar;
  Color get hotA => _b.hotA;
  Color get hotB => _b.hotB;
  Color get hotFg => _b.hotFg;

  KitTone get primaryTone => dark
      ? KitTone(_b.primary, _b.primaryTintDark, _b.primaryInkDark)
      : KitTone(_b.primary, _b.primaryTint, _b.primaryInk);
  KitTone get partnerTone => dark
      ? KitTone(_b.partner, _b.partnerTintDark, _b.partnerInkDark)
      : KitTone(_b.partner, _b.partnerTint, _b.partnerInk);
  KitTone get warmTone =>
      dark ? KitTone(_b.warm, _b.warmTintDark, _b.warmInkDark) : KitTone(_b.warm, _b.warmTint, _b.warmInk);
  KitTone get hotTone =>
      dark ? KitTone(_b.hot, _b.hotTintDark, _b.hotInkDark) : KitTone(_b.hot, _b.hotTint, _b.hotInk);

  /// The forward button: hotA -> hotB at 120°.
  LinearGradient get hotButton => LinearGradient(begin: _from120, end: _to120, colors: [_b.hotA, _b.hotB]);

  // surfaces of the new widgets
  Color get well => dark && surfaces != null ? surfaces!.inputBg : _b.well;
  Color get track => dark && surfaces != null ? surfaces!.divider : _b.track;
  Color get line => dark && surfaces != null ? surfaces!.divider : _b.line;
  Color get fieldEdge => dark && surfaces != null ? surfaces!.fieldEdge : _b.fieldEdge;

  // functional
  KitTone accent(AppAccent a) {
    final t = palette.accents[a.name]!;
    return dark ? KitTone(t.c, t.tintDark, t.inkDark) : KitTone(t.c, t.tint, t.ink);
  }

  KitSet _set(KitAccentSet s) => KitSet(
        a: s.a,
        b: s.b,
        heroA: s.heroA,
        heroMid: s.heroMid,
        heroEnd: _b.deep,
        tint: dark ? s.tintDark : s.tint,
        ink: dark ? s.inkDark : s.ink,
        btnA: s.btnA,
        btnB: s.btnB,
        btnFg: s.btnFg,
      );

  KitSet area(AppArea a) => _set(palette.areas[a.name]!);

  KitSet role(AppRoleAccent r) => _set(palette.roles[r.key]!);

  /// Unknown / null key -> 'other'.
  ({KitTone tone, Color fg}) subject(String? key) {
    final s = palette.subjects[key] ?? palette.subjects['other']!;
    return (tone: dark ? KitTone(s.c, s.tintDark, s.inkDark) : KitTone(s.c, s.tint, s.ink), fg: s.fg);
  }

  KitTone get live => dark ? KitTone(_s.live, _s.liveTintDark, _s.liveInkDark) : KitTone(_s.live, _s.liveTint, _s.liveInk);
  Color get liveFill => _s.liveFill;
  KitTone get ok => dark ? KitTone(_s.ok, _s.okTintDark, _s.okInkDark) : KitTone(_s.ok, _s.okTint, _s.okInk);
  KitTone get warn =>
      dark ? KitTone(_s.warn, _s.warnTintDark, _s.warnInkDark) : KitTone(_s.warn, _s.warnTint, _s.warnInk);

  /// error.ink = errorInk (P12).
  KitTone get error =>
      dark ? KitTone(_s.error, _s.errorTintDark, _s.errorInkDark) : KitTone(_s.error, _s.errorTint, _s.errorInk);
  Color get lock => dark ? _s.lockDark : _s.lock;
  Color get lockInk => dark ? _s.lockInkDark : _s.lockInk;
}

