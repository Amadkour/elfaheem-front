// lib/features/profile/display/display_settings_page.dart
//
// "Display & reading" — every role's settings open it (DisplaySettingsTile, feature key `profile.display`):
//
//   preview        a heading + a paragraph in the chosen Arabic and English fonts, at the chosen size
//   presets        Standard · Young learners · Easy reading (one tap sets every field below)
//   fonts          one choice for Arabic, one for English (each option drawn in its own font)
//   headings       Editorial (Markazi Text, the default) or Same as text (D-611)
//   size           text size (on top of the phone's) and the whole interface's zoom, with − / + steps
//   comfort        bold text · high contrast · reduce motion · larger touch targets
//
// Everything applies at once to the whole app (DisplaySettings → AppDisplayScope) and is kept on the device.
// DisplaySettingsView takes plain values (prefs in, a new prefs out) so test/ui/display_settings_layout_test.dart
// can pump it without the singleton.
library;

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale, AppReveal, appAnimationsOffForAll;

/// The settings entry (put it next to "Language").
class DisplaySettingsTile extends StatelessWidget {
  const DisplaySettingsTile({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        featureKey: 'profile.display',
        icon: Icons.text_fields_rounded,
        color: color ?? context.colors.primary,
        label: t('العرض والقراءة', 'Display & reading'),
        subtitle: t('الخط، حجم النص، التكبير، التباين، الحركة', 'Font, text size, zoom, contrast, motion'),
        keywords: 'font zoom size scale contrast bold accessibility خط حجم تكبير تباين',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisplaySettingsPage())),
      );
}

class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = DisplaySettings.instance;
    return SdArea(area: AppArea.me, child: BasePage(
      key: const ValueKey('profile.display'),
      appBar: ScreenAppBar(title: t('العرض والقراءة', 'Display & reading')), // the app's back chip + title (L4)
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => DisplaySettingsView(prefs: s.prefs, onChanged: s.update),
      ),
    ));
  }
}

/// The page body: plain values in, the new preferences out.
class DisplaySettingsView extends StatelessWidget {
  const DisplaySettingsView({super.key, required this.prefs, required this.onChanged, this.loadFonts = true});

  final DisplayPrefs prefs;
  final ValueChanged<DisplayPrefs> onChanged;

  /// Registers each option's font to draw its name in it (off in layout tests).
  final bool loadFonts;

  @override
  Widget build(BuildContext context) {
    final presetId = DisplaySettings.presets.where((p) => p.prefs == prefs).firstOrNull?.id;
    // One child per row, so the list builds (and each font tile loads its font) only when it scrolls in:
    // on web a font is a download.
    Widget w(Widget child, {double bottom = AppSpace.xs}) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: Padding(padding: EdgeInsets.only(bottom: bottom), child: child),
          ),
        );
    // a section heading in the editorial rhythm: more room above it than under it
    Widget head(String title) => w(
          Padding(
            padding: EdgeInsets.only(top: AppSpace.sectionHead.top - AppSpace.xs),
            child: SizedBox(
              width: double.infinity,
              child: Semantics(header: true, child: Text(title, style: AppType.section(context))),
            ),
          ),
          bottom: AppSpace.sectionHead.bottom,
        );
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xl),
      children: [
        // the page's one block: the reading sample, drawn in what is chosen below (it enters once with the route)
        w(AppReveal(index: 0, group: 'display', child: _Preview(prefs: prefs)), bottom: 0),
        head(t('أوضاع جاهزة', 'Quick setups')),
        w(_Presets(selected: presetId, onPick: (p) => onChanged(p.prefs)), bottom: 0),
        head(t('الخط العربي', 'Arabic font')),
        for (final f in AppFonts.catalog.where((f) => f.arabic))
          w(_FontOptionTile(
              option: f,
              selected: f.id == prefs.arabicFont,
              sample: 'خطٌّ واضحٌ لقراءةٍ مريحة ١٢٣',
              load: loadFonts,
              onTap: () => onChanged(prefs.copyWith(arabicFont: f.id)))),
        head(t('الخط الإنجليزي', 'English font')),
        for (final f in AppFonts.optionsFor('en'))
          w(_FontOptionTile(
              option: f,
              selected: f.id == prefs.latinFont,
              sample: 'The quick brown fox · 0123',
              load: loadFonts,
              onTap: () => onChanged(prefs.copyWith(latinFont: f.id)))),
        head(t('العناوين', 'Headings')),
        w(
          _HeadingsRow(
              editorial: prefs.editorialHeadings,
              onChanged: (v) => onChanged(prefs.copyWith(editorialHeadings: v))),
          bottom: 0,
        ),
        head(t('الحجم', 'Size')),
        w(
          AppCard(
            child: Column(children: [
              _ScaleRow(
                icon: Icons.format_size_rounded,
                title: t('حجم النص', 'Text size'),
                hint: t('يُضاف إلى حجم النص في إعدادات جهازك', "On top of your device's text size"),
                value: prefs.textScale,
                min: DisplayPrefs.minText,
                max: DisplayPrefs.maxText,
                onChanged: (v) => onChanged(prefs.copyWith(textScale: v)),
              ),
              const Divider(height: AppSpace.xl),
              _ScaleRow(
                icon: Icons.zoom_in_rounded,
                title: t('تكبير الواجهة', 'Interface zoom'),
                hint: t('يكبّر كل شيء: النص والأيقونات والأزرار والمسافات', 'Enlarges everything: text, icons, buttons and spacing'),
                value: prefs.zoom,
                min: DisplayPrefs.minZoom,
                max: DisplayPrefs.maxZoom,
                onChanged: (v) => onChanged(prefs.copyWith(zoom: v)),
              ),
            ]),
          ),
          bottom: 0,
        ),
        head(t('الراحة', 'Comfort')),
        w(
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _SpacingRow(value: prefs.spacing, onChanged: (v) => onChanged(prefs.copyWith(spacing: v))),
              AppSwitchTile(
                icon: Icons.format_bold_rounded,
                title: t('نص عريض', 'Bold text'),
                subtitle: t('كل النصوص بخط أثقل', 'Every text drawn heavier'),
                value: prefs.boldText,
                onChanged: (v) => onChanged(prefs.copyWith(boldText: v)),
              ),
              AppSwitchTile(
                icon: Icons.contrast_rounded,
                title: t('تباين عالٍ', 'High contrast'),
                subtitle: t('النصوص الباهتة والفواصل أوضح', 'Faint text and dividers made darker'),
                value: prefs.highContrast,
                onChanged: (v) => onChanged(prefs.copyWith(highContrast: v)),
              ),
              // D-584: what it stops, and locked on while the Super Admin has animations off for everyone
              AppSwitchTile(
                icon: Icons.motion_photos_off_rounded,
                title: t('تقليل الحركة', 'Reduce motion'),
                subtitle: appAnimationsOffForAll
                    ? t('أوقفت الإدارة الحركة لكل الحسابات', 'Turned off for every account by the administrator')
                    : t('بلا انتقالات بين الصفحات ولا عدّ للأرقام ولا ميل ثلاثي الأبعاد',
                        'No page transitions, counting numbers or 3D tilt'),
                value: prefs.reduceMotion || appAnimationsOffForAll,
                onChanged: appAnimationsOffForAll ? null : (v) => onChanged(prefs.copyWith(reduceMotion: v)),
              ),
              AppSwitchTile(
                icon: Icons.touch_app_rounded,
                title: t('أزرار أكبر للمس', 'Larger touch targets'),
                subtitle: t('مساحة ضغط أوسع للأزرار والقوائم', 'Roomier buttons, chips and list rows'),
                value: prefs.largeTargets,
                onChanged: (v) => onChanged(prefs.copyWith(largeTargets: v)),
              ),
            ]),
          ),
          bottom: AppSpace.lg,
        ),
        if (!prefs.isDefault)
          w(
            Center(
              child: AppButton.ghost(
                onPressed: () => onChanged(const DisplayPrefs()),
                icon: Icons.restart_alt_rounded,
                label: t('استعادة الإعدادات الافتراضية', 'Restore the defaults'),
              ),
            ),
          ),
      ],
    );
  }
}

/// The optical size of a section heading (AppType.section), the size both heading samples are drawn at.
const double _sectionOptical = 18;

/// Headings: Editorial · Same as text (D-611). Each choice is drawn in the face it picks.
class _HeadingsRow extends StatelessWidget {
  const _HeadingsRow({required this.editorial, required this.onChanged});
  final bool editorial;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(bool value, String label, String family) {
      final on = value == editorial;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? c.primaryTint : c.inputBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: on ? c.primary : c.divider, width: on ? AppBorder.focus : AppBorder.hairline),
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
              onTap: () => onChanged(value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(t('درس اليوم', "Today's lesson"),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: family,
                                fontFamilyFallback: AppFonts.fallback,
                                // the editorial face is small on its body: drawn at its optical scale, as AppType does
                                fontSize: family == AppFonts.editorialFamily ? (_sectionOptical * AppFonts.editorialScale()).roundToDouble() : _sectionOptical,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                                color: c.textDark)),
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                      ]),
                    ),
                    if (on) Icon(Icons.check_circle_rounded, size: AppIconSize.md, color: c.primary),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      option(true, t('تحريرية', 'Editorial'), AppFonts.editorialFamily),
      const SizedBox(width: AppSpace.sm),
      option(false, t('مثل النص', 'Same as text'), AppFonts.family),
    ]);
  }
}

/// Reading spacing: Normal · Comfortable · Wide.
class _SpacingRow extends StatelessWidget {
  const _SpacingRow({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = [t('عادي', 'Normal'), t('مريح', 'Comfortable'), t('واسع', 'Wide')];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.format_line_spacing_rounded, size: AppIconSize.md, color: c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(t('تباعد القراءة', 'Reading spacing'), style: AppType.row(context))),
        ]),
        const SizedBox(height: AppSpace.xxs / 2),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppIconSize.md + AppSpace.sm),
          child: Text(
              t('سطور أعلى ومسافات أوسع بين الكلمات — أسهل للقرّاء الصغار ولعُسر القراءة',
                  'Taller lines and wider gaps between words — easier for young readers and dyslexia'),
              style: AppType.meta(context)),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (var i = 0; i < labels.length; i++) AppChoiceChip(label: labels[i], selected: value == i, onTap: () => onChanged(i)),
        ]),
      ]),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.prefs});
  final DisplayPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final ar = AppFonts.byId(prefs.arabicFont, arabic: true);
    final en = AppFonts.byId(prefs.latinFont, arabic: false);
    // the sample uses the reading roles' sizes in the CHOSEN faces (the app may not have applied them yet)
    final bodySize = AppType.body(context).fontSize;
    TextStyle s(AppFontOption f, Color color) =>
        TextStyle(fontFamily: f.family, fontFamilyFallback: AppFonts.fallback, fontSize: bodySize, fontWeight: FontWeight.w400, color: color, height: 1.5);
    // the heading line in the face headings will use: the editorial one, or the chosen text font
    TextStyle h(AppFontOption f, Color color, String lang) => prefs.editorialHeadings
        ? TextStyle(
            fontFamily: AppFonts.editorialFamilyFor(lang),
            fontFamilyFallback: [f.family],
            fontSize: (_sectionOptical * AppFonts.editorialScale(lang)).roundToDouble(),
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.3)
        : s(f, color).copyWith(fontSize: _sectionOptical, fontWeight: FontWeight.w600, height: 1.35);
    return AppBlock(
      tone: AppBlockTone.sky,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.visibility_rounded, size: AppIconSize.sm, color: b.muted),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(t('معاينة', 'Preview'), style: AppType.label(context).copyWith(color: b.muted))),
          ]),
          const SizedBox(height: AppSpace.sm),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('درس اليوم: الكسور العشرية', style: h(ar, b.ink, 'ar')),
              const SizedBox(height: AppSpace.xxs),
              Text('اقرأ الفقرة ثم أجب عن الأسئلة. يبدأ البث المباشر الساعة ٤:٣٠ مساءً.', style: s(ar, b.muted)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: Color.lerp(b.surface, b.ink, _ruleInk)),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Today's lesson: decimals", style: h(en, b.ink, 'en')),
              const SizedBox(height: AppSpace.xxs),
              Text('Read the passage, then answer the questions. The live session starts at 4:30 PM.', style: s(en, b.muted)),
            ]),
          ),
        ]);
      }),
    );
  }

  /// How much of the block's ink the rule between the two samples carries.
  static const double _ruleInk = 0.16;
}

class _Presets extends StatelessWidget {
  const _Presets({required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<DisplayPreset> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 560;
      final cards = [
        for (final p in DisplaySettings.presets)
          _Choice(
            selected: p.id == selected,
            onTap: () => onPick(p),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(p.icon, size: AppIconSize.lg, color: p.id == selected ? c.primary : c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(p.nameAr, p.nameEn), style: AppType.bodyStrong(context)),
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(t(p.noteAr, p.noteEn), style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
      ];
      if (!wide) {
        return Column(children: [
          for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: w),
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Expanded(child: cards[i]),
          ],
        ]),
      );
    });
  }
}

class _FontOptionTile extends StatefulWidget {
  const _FontOptionTile({required this.option, required this.selected, required this.sample, required this.onTap, required this.load});
  final AppFontOption option;
  final bool selected, load;
  final String sample;
  final VoidCallback onTap;

  @override
  State<_FontOptionTile> createState() => _FontOptionTileState();
}

class _FontOptionTileState extends State<_FontOptionTile> {
  @override
  void initState() {
    super.initState();
    if (widget.load && !AppFonts.isLoaded(widget.option.id)) {
      AppFonts.ensureLoaded(widget.option).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.option;
    final own = TextStyle(fontFamily: f.family, fontFamilyFallback: AppFonts.fallback);
    return _Choice(
      selected: widget.selected,
      onTap: widget.onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.name(AppConfig.lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: own.copyWith(fontSize: AppType.bodyStrong(context).fontSize, fontWeight: FontWeight.w600, color: c.textDark)),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(widget.sample,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: own.copyWith(fontSize: AppType.body(context).fontSize, color: c.textMedium, height: 1.4)),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(f.note(AppConfig.lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        Icon(widget.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: AppIconSize.lg, color: widget.selected ? c.primary : c.textLight),
      ]),
    );
  }
}

/// A selectable card: primary border + tint when chosen.
class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    return Semantics(
      selected: selected,
      button: true,
      child: AppPressScale(
        child: Material(
          color: selected ? appTintOn(context, c.primary, surface: c.cardBg) : c.cardBg,
          shape: RoundedRectangleBorder(
              borderRadius: r, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline)),
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: child),
          ),
        ),
      ),
    );
  }
}

/// A − slider + row with the value as a percentage. The value is applied when the drag ends (zooming the page
/// under the finger while it drags would move the slider away from it).
class _ScaleRow extends StatefulWidget {
  const _ScaleRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final IconData icon;
  final String title, hint;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  State<_ScaleRow> createState() => _ScaleRowState();
}

class _ScaleRowState extends State<_ScaleRow> {
  static const _step = 0.05;
  double? _drag;

  double _snap(double v) => ((v / _step).round() * _step).clamp(widget.min, widget.max).toDouble();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = _drag ?? widget.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(widget.icon, size: AppIconSize.md, color: c.textMedium),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(widget.title, style: AppType.row(context))),
        Text('${(v * 100).round()}%', style: AppType.figure(context)),
      ]),
      const SizedBox(height: AppSpace.xxs / 2),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: AppIconSize.md + AppSpace.sm),
        child: Text(widget.hint, style: AppType.meta(context)),
      ),
      Row(children: [
        IconButton(
          tooltip: t('أصغر', 'Smaller'),
          onPressed: v <= widget.min ? null : () => widget.onChanged(_snap(v - _step)),
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) / _step).round(),
            label: '${(v * 100).round()}%',
            onChanged: (x) => setState(() => _drag = _snap(x)),
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onChanged(_snap(x));
            },
          ),
        ),
        IconButton(
          tooltip: t('أكبر', 'Bigger'),
          onPressed: v >= widget.max ? null : () => widget.onChanged(_snap(v + _step)),
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
    ]);
  }
}
