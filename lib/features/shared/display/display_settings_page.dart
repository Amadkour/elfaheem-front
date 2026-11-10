// lib/features/shared/display/display_settings_page.dart
//
// "Display & reading" — every role's settings open it (DisplaySettingsTile, feature key `profile.display`):
//
//   preview        a heading + a paragraph in the chosen Arabic and English fonts, at the chosen size
//   presets        Standard · Young learners · Easy reading (one tap sets every field below)
//   fonts          one choice for Arabic, one for English (each option drawn in its own font)
//   size           text size (on top of the phone's) and the whole interface's zoom, with − / + steps
//   comfort        bold text · high contrast · reduce motion · larger touch targets
//
// Everything applies at once to the whole app (DisplaySettings → AppDisplayScope) and is kept on the device.
// DisplaySettingsView takes plain values (prefs in, a new prefs out) so test/ui/display_settings_layout_test.dart
// can pump it without the singleton.
library;

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../core/display/display_settings.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/base_page.dart';
import '../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/design/app_motion_kit.dart' show appAnimationsOffForAll;

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
        subtitle: t('الخط، حجم النص، التكبير، التباين', 'Font, text size, zoom, contrast'),
        keywords: 'font zoom size scale contrast bold accessibility خط حجم تكبير تباين',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisplaySettingsPage())),
      );
}

class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = DisplaySettings.instance;
    return BasePage(
      key: const ValueKey('profile.display'),
      appBar: ScreenAppBar(title: t('العرض والقراءة', 'Display & reading')), // the app's back chip + title (L4)
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => DisplaySettingsView(prefs: s.prefs, onChanged: s.update),
      ),
    );
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
    Widget w(Widget child, {double bottom = 8}) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: Padding(padding: EdgeInsets.only(bottom: bottom), child: child),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        w(_Preview(prefs: prefs), bottom: 20),
        w(AppSectionTitle(t('أوضاع جاهزة', 'Quick setups'))),
        w(_Presets(selected: presetId, onPick: (p) => onChanged(p.prefs)), bottom: 24),
        w(AppSectionTitle(t('الخط العربي', 'Arabic font'))),
        for (final f in AppFonts.catalog.where((f) => f.arabic))
          w(_FontOptionTile(
              option: f,
              selected: f.id == prefs.arabicFont,
              sample: 'خطٌّ واضحٌ لقراءةٍ مريحة ١٢٣',
              load: loadFonts,
              onTap: () => onChanged(prefs.copyWith(arabicFont: f.id)))),
        w(const SizedBox(height: 16), bottom: 0),
        w(AppSectionTitle(t('الخط الإنجليزي', 'English font'))),
        for (final f in AppFonts.optionsFor('en'))
          w(_FontOptionTile(
              option: f,
              selected: f.id == prefs.latinFont,
              sample: 'The quick brown fox · 0123',
              load: loadFonts,
              onTap: () => onChanged(prefs.copyWith(latinFont: f.id)))),
        w(const SizedBox(height: 16), bottom: 0),
        w(AppSectionTitle(t('الحجم', 'Size'))),
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
              const Divider(height: 28),
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
          bottom: 24,
        ),
        w(AppSectionTitle(t('الراحة', 'Comfort'))),
        w(
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          bottom: 20,
        ),
        if (!prefs.isDefault)
          w(
            Center(
              child: TextButton.icon(
                onPressed: () => onChanged(const DisplayPrefs()),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(t('استعادة الإعدادات الافتراضية', 'Restore the defaults')),
              ),
            ),
          ),
      ],
    );
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.format_line_spacing_rounded, size: 20, color: c.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(t('تباعد القراءة', 'Reading spacing'), style: appText(14, w: FontWeight.w700, c: c.textDark))),
        ]),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 30),
          child: Text(
              t('سطور أعلى ومسافات أوسع بين الكلمات — أسهل للقرّاء الصغار ولعُسر القراءة',
                  'Taller lines and wider gaps between words — easier for young readers and dyslexia'),
              style: appText(11.5, c: c.textLight, h: 1.35)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
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
    final c = context.colors;
    final ar = AppFonts.byId(prefs.arabicFont, arabic: true);
    final en = AppFonts.byId(prefs.latinFont, arabic: false);
    TextStyle s(AppFontOption f, double size, FontWeight w, Color color) =>
        TextStyle(fontFamily: f.family, fontFamilyFallback: AppFonts.fallback, fontSize: size, fontWeight: w, color: color, height: 1.45);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.visibility_rounded, size: 18, color: c.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t('معاينة', 'Preview'), style: appText(12.5, w: FontWeight.w700, c: c.textLight))),
        ]),
        const SizedBox(height: 10),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('درس اليوم: الكسور العشرية', style: s(ar, 18, FontWeight.w800, c.textDark)),
            const SizedBox(height: 4),
            Text('اقرأ الفقرة ثم أجب عن الأسئلة. يبدأ البث المباشر الساعة ٤:٣٠ مساءً.', style: s(ar, 14, FontWeight.w400, c.textMedium)),
          ]),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Today's lesson: decimals", style: s(en, 18, FontWeight.w800, c.textDark)),
            const SizedBox(height: 4),
            Text('Read the passage, then answer the questions. The live session starts at 4:30 PM.',
                style: s(en, 14, FontWeight.w400, c.textMedium)),
          ]),
        ),
      ]),
    );
  }
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
              Icon(p.icon, color: p.id == selected ? c.primary : c.textMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(p.nameAr, p.nameEn), style: appText(14, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 2),
                  Text(t(p.noteAr, p.noteEn), style: appText(12, c: c.textMedium, h: 1.35)),
                ]),
              ),
            ]),
          ),
      ];
      if (!wide) {
        return Column(children: [
          for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
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
                maxLines: 1, overflow: TextOverflow.ellipsis, style: own.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: c.textDark)),
            const SizedBox(height: 2),
            Text(widget.sample,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: own.copyWith(fontSize: 13.5, color: c.textMedium, height: 1.4)),
            const SizedBox(height: 2),
            Text(f.note(AppConfig.lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textLight)),
          ]),
        ),
        const SizedBox(width: 10),
        Icon(widget.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: widget.selected ? c.primary : c.textLight),
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
    final r = BorderRadius.circular(c.radiusLarge - 6);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1)),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
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
        Icon(widget.icon, size: 20, color: c.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.title, style: appText(14, w: FontWeight.w700, c: c.textDark))),
        Text('${(v * 100).round()}%', style: appText(14, w: FontWeight.w800, c: c.primary)),
      ]),
      const SizedBox(height: 2),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 30),
        child: Text(widget.hint, style: appText(11.5, c: c.textLight, h: 1.35)),
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
