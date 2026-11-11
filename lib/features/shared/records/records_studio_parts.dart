// lib/features/shared/records/records_studio_parts.dart — the Studio (D-312, the edit bay D-320, premium D-590 …
// D-597): the record editor's plain-values widgets. No API, no player, no provider, so
// test/ui/records_studio_layout_test.dart pumps them with the layout harness on every size, language and a 1.3 text
// scale. The page (records_studio.dart) owns the player, the project, the job and the keyboard. The timeline is
// studio_timeline.dart, the overlays on the picture studio_stage.dart, the Edit / Text / Picture / History panels
// studio_panels.dart.
//
//   StudioBay             the edit bay's colours: dark in BOTH themes (top bar, rail, stage, transport, timeline), all
//                         derived from the server theme; the inspector beside it follows the theme. The canvas around
//                         the picture can be dark, grey or light (D-597: judge a text against more than one surround)
//   StudioTool            two groups: the edit (Edit · Text · Picture · History — one project, one render) and the
//                         output (Quality · Two files · Merge · Cover)
//   StudioTopBar          the slim dark bar: back, "Studio", the record's name, autosave, canvas, Download original
//   StudioTransport       exact time (hundredths) / total, frame step · −5 s · play · +5 s, preview speed, zoom slider
//   StudioToolRail        the tools on wide screens: an icon rail in two groups
//   StudioToolBar         the tools on phones: a bottom strip
//   StudioToolPanel       Quality and size · Cover · Merge (the edit tools' panels: studio_panels.dart)
//   StudioSummary         what comes out ("New length 12:40", the merge's total) or why not
//   StudioSaveArea        the name, Keep / Replace the original (`form`) · Undo / Redo and the one primary button
//   StudioJobCard         a saved edit's job, inline: the stages, % and time left, Cancel · ready (Play, Download,
//                         Continue editing) · failed / stopped (Retry)
//   RecordStudioLayout    all of it: wide = rail · stage over transport and timeline · inspector; phones = the stage,
//                         transport and timeline pinned, the inspector as a sheet under them, the tool strip at the foot
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../live/meeting_recording.dart' show recordingSizeLabel;
import 'records_api.dart';
import 'records_parts.dart' show RecordCover, recordsCountText;

// ─────────────────────────────────────────────────────────────────────────────
// The edit bay's colours
// ─────────────────────────────────────────────────────────────────────────────

/// The edit bay is dark in both themes, as every video editor is: a picture is judged against a dark surround, and the
/// frame of a clip reads best on it. Everything comes from the server theme ([ThemeConfigProvider.heroShade] and the
/// on-hero ink), so a re-themed platform keeps a matching bay.
class StudioBay {
  StudioBay.of(BuildContext context) : c = context.colors;

  final ThemeConfigProvider c;

  /// Around the picture: the deepest surface.
  Color get floor {
    final h = HSLColor.fromColor(c.heroShade);
    return h.withLightness(h.lightness * 0.58).toColor();
  }

  Color get deck => c.heroShade;

  /// The canvas around the picture for [shade] (D-597).
  Color canvas(StudioCanvas shade) => switch (shade) {
        StudioCanvas.dark => floor,
        StudioCanvas.grey => Color.lerp(floor, c.onHero, 0.32)!,
        StudioCanvas.light => Color.lerp(floor, c.onHero, 0.86)!,
      };
  Color get raised => Color.alphaBlend(c.onHero.withValues(alpha: 0.08), deck);
  Color get line => c.onHero.withValues(alpha: 0.11);
  Color get ink => c.onHero;
  Color get muted => c.onHeroMuted;
  Color get faint => c.onHeroFaint;

  /// The one bright colour of the bay: the selected tool, the clip frame.
  Color get accent => _lifted(c.accent2);

  /// What is removed.
  Color get cut => _lifted(c.danger);

  /// Raises a theme colour until it reads on the dark deck.
  Color _lifted(Color base) {
    var out = base;
    for (var i = 1; i <= 8 && out.computeLuminance() < 0.24; i++) {
      out = Color.lerp(base, c.onHero, i * 0.08)!;
    }
    return out;
  }
}

/// The canvas around the picture.
enum StudioCanvas {
  dark,
  grey,
  light;

  String get label => switch (this) {
        StudioCanvas.dark => t('خلفية داكنة', 'Dark canvas'),
        StudioCanvas.grey => t('خلفية رمادية', 'Grey canvas'),
        StudioCanvas.light => t('خلفية فاتحة', 'Light canvas'),
      };
}

TextStyle _tabular(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// Wide enough for the rail · stage · inspector layout (also a phone held sideways: a stack would leave no stage).
bool studioIsWide(Size size) => size.width >= studioWideMin || (size.width >= 640 && size.width / math.max(1, size.height) >= 1.5);

// ─────────────────────────────────────────────────────────────────────────────
// Tools
// ─────────────────────────────────────────────────────────────────────────────

enum StudioTool {
  edit,
  text,
  image,
  history,
  quality,
  split,
  merge,
  cover;

  /// The edit tools share one project and one render; the output tools make something else of it.
  bool get isEditing => index <= StudioTool.history.index;

  /// What the Save of this tool sends (cover saves at once; merge has its own call).
  RecordOp? get op => switch (this) {
        StudioTool.edit || StudioTool.text || StudioTool.image || StudioTool.history || StudioTool.quality => RecordOp.project,
        StudioTool.split => RecordOp.split,
        StudioTool.merge => RecordOp.merge,
        StudioTool.cover => null,
      };

  String get label => switch (this) {
        StudioTool.edit => t('تحرير', 'Edit'),
        StudioTool.text => t('نص', 'Text'),
        StudioTool.image => t('صورة', 'Picture'),
        StudioTool.history => t('السجل', 'History'),
        StudioTool.quality => t('الجودة والحجم', 'Quality and size'),
        StudioTool.split => t('ملفّان', 'Two files'),
        StudioTool.cover => t('الغلاف', 'Cover'),
        StudioTool.merge => t('دمج', 'Merge'),
      };

  /// The rail's and the strip's word: one short word each.
  String get short => switch (this) {
        StudioTool.quality => t('الجودة', 'Quality'),
        _ => label,
      };

  String get description => switch (this) {
        StudioTool.edit => t('قسّم عند المؤشر، احذف جزءاً أو فترة محددة، اسحب طرفي الجزء لقصّه، وغيّر سرعة أي جزء. كل خطوة تُحفظ في السجل.',
            'Split at the playhead, remove a part or a marked period, drag a part’s edges to trim it, change any part’s speed. Every step goes into the history.'),
        StudioTool.text => t('أضف نصاً في أي وقت: الخط واللون والخلفية، ثم اسحبه على الصورة وحدّد ظهوره واختفاءه.',
            'Add a text at any moment: font, colour and background, then drag it on the picture and choose how it comes in and out.'),
        StudioTool.image => t('أضف شعاراً أو صورة فوق الفيديو، غيّر حجمها وشفافيتها وحركتها.',
            'Put a logo or a picture over the video; change its size, opacity and animation.'),
        StudioTool.history => t('كل ما فعلته بالترتيب. اضغط أي خطوة للعودة إليها؛ تبقى الخطوات التالية حتى تبدأ تعديلاً جديداً.',
            'Everything you did, in order. Tap any step to go back to it; the later steps stay until you make a new change.'),
        StudioTool.split => t('احفظ التعديل فيديوين منفصلين يُقسمان عند المؤشر.', 'Save the edit as two separate videos, split at the playhead.'),
        StudioTool.quality => t('غيّر دقة الفيديو وجودته لتكبير الملف أو تصغيره؛ يبقى الأصل كما هو.', 'Change the resolution and quality to make the file larger or smaller; the original stays as it is.'),
        StudioTool.cover => t('الصورة التي تظهر في المكتبة وعند المشاركة، وتنتقل إلى التعديلات.', 'The picture shown in the library and when shared; edits keep it.'),
        StudioTool.merge => t('أضف تسجيلات أخرى بعد هذا التسجيل لتصبح ملفاً واحداً (من الأصول، دون تعديلات المشروع).',
            'Add other recordings after this one to make a single file (from the originals, without the project’s edits).'),
      };

  IconData get icon => switch (this) {
        StudioTool.edit => Icons.content_cut_rounded,
        StudioTool.text => Icons.title_rounded,
        StudioTool.image => Icons.add_photo_alternate_outlined,
        StudioTool.history => Icons.history_rounded,
        StudioTool.split => Icons.call_split_rounded,
        StudioTool.quality => Icons.high_quality_rounded,
        StudioTool.cover => Icons.image_outlined,
        StudioTool.merge => Icons.merge_rounded,
      };
}

/// The preview speeds of the transport (what the player plays at; not an edit).
const studioPreviewSpeeds = <double>[1, 1.25, 1.5, 2, 0.75];

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

/// Where the autosave stands.
enum StudioSaveState { idle, saving, saved, failed }

class StudioTopBar extends StatelessWidget implements PreferredSizeWidget {
  const StudioTopBar({
    super.key,
    required this.title,
    this.facts = const [],
    this.saveState = StudioSaveState.idle,
    this.canvas = StudioCanvas.dark,
    this.onCanvas,
    this.onDownload,
    this.downloading,
  });

  final String title;

  /// The record's length · size · place, on wide windows.
  final List<String> facts;
  final StudioSaveState saveState;
  final StudioCanvas canvas;
  final VoidCallback? onCanvas;

  /// Download the original (null: not offered).
  final VoidCallback? onDownload;

  /// A download in progress (0–1; null: none).
  final double? downloading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final (IconData saveIcon, String saveText, Color saveTone) = switch (saveState) {
      StudioSaveState.saving => (Icons.cloud_sync_outlined, t('يحفظ…', 'Saving…'), bay.muted),
      StudioSaveState.saved => (Icons.cloud_done_outlined, t('حُفظ العمل', 'Work saved'), bay.muted),
      StudioSaveState.failed => (Icons.cloud_off_outlined, t('لم يُحفظ — سيُعاد', 'Not saved — retrying'), bay.cut),
      StudioSaveState.idle => (Icons.cloud_outlined, '', bay.faint),
    };
    return Material(
      color: bay.deck,
      child: Container(
        height: kToolbarHeight,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bay.line))),
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, end: AppSpace.xs),
        child: Row(children: [
          const AppBackButton(key: ValueKey('studio.back'), onHero: true),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t('الاستوديو', 'Studio'),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: AppType.overline(context).copyWith(color: bay.accent, letterSpacing: 0)),
              Text(title,
                  key: const ValueKey('studio.title_bar'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: AppType.bodyStrong(context).copyWith(color: bay.ink)),
            ]),
          ),
          if (facts.isNotEmpty && MediaQuery.sizeOf(context).width >= 1100) ...[
            const SizedBox(width: AppSpace.md),
            Text(facts.join('  ·  '), textDirection: TextDirection.ltr, maxLines: 1, style: _tabular(AppType.meta(context).copyWith(color: bay.faint))),
          ],
          if (saveState != StudioSaveState.idle)
            Tooltip(
              message: saveText,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(saveIcon, size: AppIconSize.sm, color: saveTone, key: const ValueKey('studio.autosave')),
                  if (wide) ...[
                    const SizedBox(width: AppSpace.xxs),
                    Text(saveText, maxLines: 1, textScaler: TextScaler.noScaling, style: AppType.meta(context).copyWith(color: saveTone)),
                  ],
                ]),
              ),
            ),
          if (onCanvas != null)
            IconButton(
              key: const ValueKey('studio.canvas'),
              tooltip: '${canvas.label} — ${t('غيّر', 'change')}',
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              onPressed: onCanvas,
              icon: Icon(
                  switch (canvas) {
                    StudioCanvas.dark => Icons.dark_mode_outlined,
                    StudioCanvas.grey => Icons.contrast_rounded,
                    StudioCanvas.light => Icons.light_mode_outlined,
                  },
                  color: bay.muted),
            ),
          if (onDownload != null)
            downloading != null
                ? SizedBox(
                    width: AppTouch.min,
                    height: AppTouch.min,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, value: downloading! > 0 ? downloading : null, color: bay.accent),
                      ),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('studio.download_original'),
                    tooltip: t('تنزيل الأصل', 'Download the original'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: onDownload,
                    icon: Icon(Icons.download_rounded, color: bay.ink),
                  ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport
// ─────────────────────────────────────────────────────────────────────────────

/// A small quiet chip on the deck (the preview speed, the zoom on phones), with a full touch target.
class _BayChip extends StatelessWidget {
  const _BayChip({super.key, required this.label, required this.tip, this.icon, this.lit = false, this.onTap});

  final String label;
  final String tip;
  final IconData? icon;
  final bool lit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs + 1),
              decoration: BoxDecoration(
                color: lit ? bay.accent.withValues(alpha: 0.18) : bay.raised,
                borderRadius: AppRadius.chipAll,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: AppIconSize.xs, color: lit ? bay.accent : bay.muted),
                  const SizedBox(width: 2),
                ],
                Text(label,
                    textScaler: TextScaler.noScaling,
                    style: _tabular(AppType.label(context).copyWith(color: lit ? bay.accent : bay.muted, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class StudioTransport extends StatelessWidget {
  const StudioTransport({
    super.key,
    required this.position,
    required this.duration,
    this.playing = false,
    this.previewSpeed = 1,
    this.enabled = true,
    this.zoom = 1,
    this.maxZoom = 16,
    this.onPlayPause,
    this.onSkip,
    this.onPreviewSpeed,
    this.onZoom,
  });

  final double position;
  final double duration;
  final bool playing;
  final double previewSpeed;
  final bool enabled;

  /// The timeline's zoom (1 = the whole video fits) and the most it goes.
  final double zoom;
  final double maxZoom;
  final VoidCallback? onPlayPause;

  /// Seconds to move: ±5, or ±1/30 (one frame).
  final ValueChanged<double>? onSkip;

  /// The next preview speed was asked for.
  final VoidCallback? onPreviewSpeed;
  final ValueChanged<double>? onZoom;

  static const frame = 1 / 30;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    Widget skip(double by, IconData icon, String tip, String key) => IconButton(
          key: ValueKey('studio.skip.$key'),
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, color: enabled ? bay.ink : bay.faint),
          onPressed: enabled ? () => onSkip?.call(by) : null,
        );
    final play = Tooltip(
      message: playing ? t('إيقاف مؤقت (مسافة)', 'Pause (Space)') : t('تشغيل (مسافة)', 'Play (Space)'),
      child: Semantics(
        button: true,
        label: playing ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play'),
        child: InkResponse(
          key: const ValueKey('studio.play'),
          onTap: enabled ? onPlayPause : null,
          radius: 30,
          child: SizedBox(
            width: AppTouch.primary,
            height: AppTouch.primary,
            child: Center(
              child: Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? bay.ink : bay.raised),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: enabled ? bay.deck : bay.faint, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
    final speed = _BayChip(
      key: const ValueKey('studio.preview_speed'),
      label: speedLabel(previewSpeed),
      tip: t('سرعة المعاينة (لا تغيّر الملف)', 'Preview speed (does not change the file)'),
      lit: previewSpeed != 1,
      onTap: enabled ? onPreviewSpeed : null,
    );
    return Directionality(
      // LTR like the timeline: back on the left, forward on the right in every language
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < 620;
        final time = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: studioTimecodeShort(position), style: _tabular(appText(compact ? 14 : 16, w: FontWeight.w700, c: bay.ink))),
              TextSpan(text: compact ? '\n${mmss(duration)}' : '  /  ${mmss(duration)}', style: _tabular(appText(compact ? 11.5 : 13, c: bay.faint))),
            ]),
            key: const ValueKey('studio.time'),
            maxLines: compact ? 2 : 1,
            textScaler: TextScaler.noScaling,
          ),
        );
        final zoomable = onZoom != null && maxZoom > 1.01;
        Widget zoomBtn(IconData icon, String tip, double to, String key) => IconButton(
              key: ValueKey('studio.zoom.$key'),
              tooltip: tip,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(icon, size: AppIconSize.md, color: bay.ink),
              onPressed: () => onZoom!(to.clamp(1.0, maxZoom)),
            );
        // the slider runs on a log scale: every step doubles or halves the zoom
        final logMax = math.log(maxZoom);
        final zoomSlider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: bay.accent,
            inactiveTrackColor: bay.line,
            thumbColor: bay.ink,
            overlayColor: bay.accent.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Semantics(
            label: t('تكبير الخط الزمني', 'Timeline zoom'),
            child: Slider(
              key: const ValueKey('studio.zoom.slider'),
              value: (math.log(zoom.clamp(1.0, maxZoom)) / math.max(1e-6, logMax)).clamp(0.0, 1.0),
              onChanged: (v) => onZoom!(math.exp(v * logMax)),
            ),
          ),
        );
        if (compact) {
          return Row(children: [
            Expanded(child: time),
            skip(-5, Icons.replay_5_rounded, t('رجوع 5 ثوانٍ (J)', 'Back 5 s (J)'), 'back'),
            play,
            skip(5, Icons.forward_5_rounded, t('تقديم 5 ثوانٍ (L)', 'Forward 5 s (L)'), 'fwd'),
            speed,
            if (zoomable)
              _BayChip(
                key: const ValueKey('studio.zoom.level'),
                label: '×${zoom < 10 ? zoom.toStringAsFixed(zoom < 2 ? 1 : 0) : zoom.round()}',
                icon: Icons.zoom_in_rounded,
                tip: t('تكبير الخط الزمني', 'Timeline zoom'),
                lit: zoom > 1.05,
                onTap: () => onZoom!(zoom * 2 > maxZoom + 0.01 ? 1 : zoom * 2),
              ),
          ]);
        }
        return Row(children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: time)),
          skip(-StudioTransport.frame, Icons.keyboard_arrow_left_rounded, t('إطار للخلف (←)', 'One frame back (←)'), 'frame_back'),
          skip(-5, Icons.replay_5_rounded, t('رجوع 5 ثوانٍ (J)', 'Back 5 s (J)'), 'back'),
          play,
          skip(5, Icons.forward_5_rounded, t('تقديم 5 ثوانٍ (L)', 'Forward 5 s (L)'), 'fwd'),
          skip(StudioTransport.frame, Icons.keyboard_arrow_right_rounded, t('إطار للأمام (→)', 'One frame forward (→)'), 'frame_fwd'),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              speed,
              if (zoomable) ...[
                const SizedBox(width: AppSpace.xxs),
                zoomBtn(Icons.zoom_out_rounded, t('تصغير', 'Zoom out'), zoom / 2, 'out'),
                Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: zoomSlider)),
                zoomBtn(Icons.zoom_in_rounded, t('تكبير (Ctrl + العجلة)', 'Zoom in (Ctrl + wheel)'), zoom * 2, 'in'),
              ],
            ]),
          ),
        ]);
      }),
    );
  }
}

/// The transport's time: "01:23.4" (tenths) under an hour, "1:01:23" from there.
String studioTimecodeShort(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  if (s >= 3600) return mmss(s);
  final tenth = ((s - s.floor()) * 10).floor().clamp(0, 9);
  return '${mmss(s)}.$tenth';
}

/// The ruler's step (seconds) so labels stand at least [minGap] px apart.
double studioRulerStep(double pxPerSecond, {double minGap = 72}) {
  const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200];
  for (final s in steps) {
    if (s * pxPerSecond >= minGap) return s;
  }
  return steps.last;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool pickers
// ─────────────────────────────────────────────────────────────────────────────

/// The tools on wide screens: a dark icon rail, the selected one lit with a bar on its leading edge.
class StudioToolRail extends StatelessWidget {
  const StudioToolRail({super.key, required this.tool, this.onTool, this.enabled = true, this.tools = StudioTool.values});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  /// The source's tools (a session material has no Cover, D-315).
  final List<StudioTool> tools;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final motion = AppMotion.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (final (i, x) in tools.indexed) ...[
            if (i > 0 && tools[i - 1].isEditing && !x.isEditing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.sm),
                child: Divider(height: 1, thickness: 1, color: bay.line),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Tooltip(
                message: x.label,
                waitDuration: const Duration(milliseconds: 400),
                child: Semantics(
                  selected: x == tool,
                  button: true,
                  label: x.label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('studio.tool.${x.name}'),
                    borderRadius: AppRadius.chipAll,
                    hoverColor: bay.c.onHero.withValues(alpha: 0.06),
                    onTap: enabled ? () => onTool?.call(x) : null,
                    child: Stack(children: [
                      AnimatedContainer(
                        duration: motion.fast,
                        curve: AppMotion.curve,
                        constraints: const BoxConstraints(minHeight: 62),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: AppSpace.xs),
                        decoration: BoxDecoration(
                          color: x == tool ? bay.accent.withValues(alpha: 0.14) : null,
                          borderRadius: AppRadius.chipAll,
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(x.icon, size: AppIconSize.lg - 2, color: x == tool ? bay.accent : bay.muted),
                          const SizedBox(height: AppSpace.xxs),
                          Text(x.short,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.linear(math.min(1.1, MediaQuery.textScalerOf(context).scale(1))),
                              style: appText(11, w: x == tool ? FontWeight.w700 : FontWeight.w500, c: x == tool ? bay.ink : bay.muted)),
                        ]),
                      ),
                      if (x == tool)
                        PositionedDirectional(
                          start: 0,
                          top: 16,
                          bottom: 16,
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(color: bay.accent, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The tools on phones: a dark strip at the foot (icon + one word); narrow phones scroll it sideways.
class StudioToolBar extends StatelessWidget {
  const StudioToolBar({super.key, required this.tool, this.onTool, this.enabled = true, this.tools = StudioTool.values});

  final StudioTool tool;
  final ValueChanged<StudioTool>? onTool;
  final bool enabled;

  /// The source's tools (a session material has no Cover, D-315).
  final List<StudioTool> tools;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final motion = AppMotion.of(context);
    Widget cell(StudioTool x) => Semantics(
          selected: x == tool,
          button: true,
          label: x.label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('studio.bar.${x.name}'),
            borderRadius: AppRadius.chipAll,
            onTap: enabled ? () => onTool?.call(x) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: motion.fast,
                  curve: AppMotion.curve,
                  width: 44,
                  height: 28,
                  decoration: BoxDecoration(
                    color: x == tool ? bay.accent.withValues(alpha: 0.20) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(x.icon, size: AppIconSize.md, color: x == tool ? bay.accent : bay.muted),
                ),
                const SizedBox(height: 2),
                Text(x.short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.linear(math.min(1.1, MediaQuery.textScalerOf(context).scale(1))),
                    style: appText(10.5, w: x == tool ? FontWeight.w700 : FontWeight.w500, c: x == tool ? bay.ink : bay.muted)),
              ]),
            ),
          ),
        );
    return Material(
      color: bay.deck,
      child: SafeArea(
        top: false,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth / math.max(1, tools.length) >= 50) {
                return Row(children: [for (final x in tools) Expanded(child: cell(x))]);
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [for (final x in tools) SizedBox(width: 60, child: cell(x))]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The tool's controls
// ─────────────────────────────────────────────────────────────────────────────

/// One merge candidate: picked or not, and its place.
class StudioMergePick {
  const StudioMergePick({required this.item, this.order});
  final RecordItem item;

  /// 1-based place after the open record (null: not picked).
  final int? order;
}

/// One option of a set, equal in width to its neighbours (speed, resolution, level, keep / replace).
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, this.onTap, this.icon, this.tone});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The selected colour (null: the theme's primary).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final on = tone ?? c.primary;
    final ink = selected ? (c.isDark && tone == null ? c.textDark : on) : c.textDark;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? on.withValues(alpha: c.isDark ? 0.32 : 0.10) : c.inputBg,
            borderRadius: AppRadius.chipAll,
            border: Border.all(
              color: selected ? (c.isDark && tone == null ? c.textMedium : on) : c.divider,
              width: selected ? AppBorder.strong : AppBorder.hairline,
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: AppIconSize.sm, color: ink),
              const SizedBox(width: AppSpace.xxs),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: _tabular(appText(12.5, w: selected ? FontWeight.w700 : FontWeight.w500, c: ink, h: 1.25))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A row of equal [_Choice]s.
class _Choices extends StatelessWidget {
  const _Choices({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Expanded(child: w),
          ],
        ]),
      );
}

/// Now against the new file's ceiling: the bar is the ceiling, the tick is today's size.
class _SizeMeter extends StatelessWidget {
  const _SizeMeter({required this.now, required this.next});
  final int now;
  final int next;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final top = math.max(now, next).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(alignment: AlignmentDirectional.centerStart, children: [
          Container(height: 8, decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(4))),
          AnimatedContainer(
            duration: motion.base,
            curve: AppMotion.curve,
            height: 8,
            width: w * (next / top).clamp(0.02, 1.0),
            decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(4)),
          ),
          AnimatedPositionedDirectional(
            duration: motion.base,
            curve: AppMotion.curve,
            start: math.max(0, w * (now / top) - 2),
            top: 0,
            bottom: 0,
            child: Container(width: 2, decoration: BoxDecoration(color: c.textDark, borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      );
    });
  }
}

class StudioToolPanel extends StatelessWidget {
  const StudioToolPanel({
    super.key,
    required this.tool,
    required this.item,
    required this.duration,
    this.height,
    this.level = StudioQualityLevel.balanced,
    this.merge = const [],
    this.enabled = true,
    this.showImages = true,
    this.onQuality,
    this.onPickCover,
    this.onRemoveCover,
    this.onToggleMerge,
  });

  final StudioTool tool;
  final RecordItem item;

  /// The edit's output length (the size estimate).
  final double duration;

  /// Quality and size: the output's short side (null: as it is) and its level.
  final int? height;
  final StudioQualityLevel level;
  final List<StudioMergePick> merge;
  final bool enabled;
  final bool showImages;
  final void Function(int? height, StudioQualityLevel level)? onQuality;
  final VoidCallback? onPickCover;
  final VoidCallback? onRemoveCover;
  final ValueChanged<RecordItem>? onToggleMerge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget caption(String text) => Text(text, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600));
    Widget note(String text, {Key? key}) => Text(text, key: key, style: AppType.meta(context).copyWith(color: c.textMedium));
    Widget here(String key, String label, IconData icon, String tip, VoidCallback? onTap) => AppButton(
          key: ValueKey('studio.$key'),
          label: label,
          icon: icon,
          tooltip: tip,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          expand: true,
          onPressed: enabled ? onTap : null,
        );
    final List<Widget> body;
    switch (tool) {
      case StudioTool.edit:
      case StudioTool.text:
      case StudioTool.image:
      case StudioTool.history:
      case StudioTool.split:
        body = const [];
      case StudioTool.quality:
        final sourceHeight = item.quality.maxHeight;
        final ceiling = studioQualityCeilingBytes(duration, height: height, level: level, sourceHeight: sourceHeight);
        // "700.0 MB" stays in that order inside an Arabic sentence.
        String weight(int bytes) => '${String.fromCharCode(0x2066)}${recordingSizeLabel(bytes)}${String.fromCharCode(0x2069)}';
        body = [
          caption(t('الدقة', 'Resolution')),
          const SizedBox(height: AppSpace.xs),
          _Choices(children: [
            _Choice(
              key: const ValueKey('studio.height.original'),
              label: t('الأصلية', 'Original'),
              selected: height == null,
              onTap: enabled ? () => onQuality?.call(null, level) : null,
            ),
            for (final h in studioQualityHeights)
              _Choice(
                key: ValueKey('studio.height.$h'),
                label: '${h}p',
                selected: height == h,
                onTap: enabled ? () => onQuality?.call(h, level) : null,
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          caption(t('الجودة', 'Quality')),
          const SizedBox(height: AppSpace.xs),
          _Choices(children: [
            for (final l in StudioQualityLevel.values)
              _Choice(
                key: ValueKey('studio.level.${l.wire}'),
                label: l.label,
                selected: level == l,
                onTap: enabled ? () => onQuality?.call(height, l) : null,
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          if (item.size > 0 && duration > 0) ...[
            _SizeMeter(now: item.size, next: ceiling),
            const SizedBox(height: AppSpace.xxs),
          ],
          Text(
            key: const ValueKey('studio.quality.size'),
            [
              if (item.size > 0) t('الحجم الحالي ${weight(item.size)}', 'Now ${weight(item.size)}'),
              if (duration > 0) t('الجديد حتى نحو ${weight(ceiling)}', 'New: up to about ${weight(ceiling)}'),
            ].join(' · '),
            style: _tabular(AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          ),
          if (height != null && height! > sourceHeight && sourceHeight > 0) ...[
            const SizedBox(height: AppSpace.xxs),
            note(
                t('رفع الدقة يكبّر الصورة والملف، ولا يضيف تفاصيل غير موجودة في الأصل.',
                    'A higher resolution makes the picture and the file larger; it cannot add detail the original lacks.'),
                key: const ValueKey('studio.quality.upscale')),
          ],
        ];
      case StudioTool.cover:
        body = [
          LayoutBuilder(builder: (context, box) => RecordCover(item: item, width: math.min(box.maxWidth, 360), showImage: showImages)),
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(
              child: here('cover_pick', item.coverUrl == null ? t('اختيار صورة', 'Choose a picture') : t('تغيير الصورة', 'Change the picture'),
                  Icons.add_photo_alternate_outlined, t('اختر صورة من جهازك', 'Pick a picture from your device'), onPickCover),
            ),
            if (item.coverUrl != null) ...[
              const SizedBox(width: AppSpace.xs),
              Expanded(child: here('cover_remove', t('إزالة', 'Remove'), Icons.hide_image_outlined, t('إزالة الغلاف', 'Remove the cover'), onRemoveCover)),
            ],
          ]),
          const SizedBox(height: AppSpace.sm),
          note(t('يُحفظ الغلاف فوراً دون إنشاء تسجيل جديد.', 'A cover is saved at once, no new recording is made.')),
        ];
      case StudioTool.merge:
        Widget badge(String s, {bool on = true}) => CircleAvatar(
              radius: 12,
              backgroundColor: on ? c.primary : c.inputBg,
              child: Text(s, style: _tabular(AppType.overline(context).copyWith(color: on ? c.onHero : c.textMedium, letterSpacing: 0))),
            );
        Widget row(RecordItem r, Widget lead, {bool picked = false, String? tag}) => AnimatedContainer(
              duration: AppMotion.of(context).fast,
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs + 2),
              decoration: BoxDecoration(
                color: picked ? c.primaryTint : null,
                borderRadius: AppRadius.chipAll,
                border: Border.all(color: picked ? c.primary.withValues(alpha: 0.35) : c.divider),
              ),
              child: Row(children: [
                SizedBox(width: 28, child: Center(child: lead)),
                const SizedBox(width: AppSpace.xs),
                RecordCover(item: r, width: 56, showImage: showImages),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tag ?? r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                    Text(r.facts().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ]),
                ),
              ]),
            );
        body = merge.isEmpty
            ? [note(t('لا توجد تسجيلات جاهزة أخرى للدمج.', 'There are no other ready recordings to merge.'))]
            : [
                note(t('بالترتيب: هذا التسجيل أولاً ثم ما تختاره.', 'In order: this recording first, then what you pick.')),
                const SizedBox(height: AppSpace.xs),
                row(item, badge('1'), tag: t('هذا التسجيل', 'This recording')),
                for (final m in merge) ...[
                  const SizedBox(height: AppSpace.xxs + 2),
                  InkWell(
                    key: ValueKey('studio.merge.${m.item.id}'),
                    borderRadius: AppRadius.chipAll,
                    onTap: enabled ? () => onToggleMerge?.call(m.item) : null,
                    child: row(
                      m.item,
                      m.order == null
                          ? Icon(Icons.add_circle_outline_rounded, color: c.textLight, size: AppIconSize.md)
                          : badge('${m.order! + 1}'),
                      picked: m.order != null,
                    ),
                  ),
                ],
              ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body);
  }
}

/// The inspector's head: which tool, and what it does.
class _InspectorHead extends StatelessWidget {
  const _InspectorHead({required this.tool});
  final StudioTool tool;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
        child: Icon(tool.icon, size: AppIconSize.md, color: c.isDark ? c.textDark : c.primary),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(tool.label, key: const ValueKey('studio.tool_title'), style: AppType.section(context)),
          const SizedBox(height: 2),
          Text(tool.description, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary · save · job
// ─────────────────────────────────────────────────────────────────────────────

/// What the result will be, or why it cannot be made (null [result] and [problem]: nothing to say — cover).
class StudioSummary extends StatelessWidget {
  const StudioSummary({super.key, required this.original, this.result = const [], this.problem});

  final double original;

  /// The new length(s): one, two for a split.
  final List<double> result;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bad = problem != null;
    final String line;
    if (bad) {
      line = problem!;
    } else if (result.length == 2) {
      line = t('ينتج تسجيلين: ${mmss(result[0])} و${mmss(result[1])}', 'Makes two recordings: ${mmss(result[0])} and ${mmss(result[1])}');
    } else if (result.isNotEmpty) {
      line = t('المدة الجديدة ${mmss(result.first)}', 'New length ${mmss(result.first)}');
    } else {
      return const SizedBox.shrink();
    }
    final tone = bad ? c.danger : c.success;
    return Container(
      key: const ValueKey('studio.summary'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs + 2),
      decoration: BoxDecoration(
        color: bad ? c.dangerTint : c.successTint,
        borderRadius: AppRadius.chipAll,
      ),
      child: Row(children: [
        Icon(bad ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded, color: tone, size: AppIconSize.md),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(line, style: _tabular(AppType.row(context).copyWith(color: bad ? c.danger : c.textDark, fontWeight: FontWeight.w600))),
            if (!bad)
              Text(t('الأصل ${mmss(original)}', 'Original ${mmss(original)}'), style: _tabular(AppType.meta(context).copyWith(color: c.textMedium))),
          ]),
        ),
      ]),
    );
  }
}

/// The name and what happens to the original ([form], scrolling with the tool) and Undo with the one primary button
/// ([actions], pinned under the inspector). Standing alone it draws the two together.
class StudioSaveArea extends StatelessWidget {
  const StudioSaveArea({
    super.key,
    required this.title,
    this.replace = false,
    this.canSave = false,
    this.canUndo = false,
    this.busy = false,
    this.merge = false,
    this.draft = false,
    this.onReplace,
    this.onUndo,
    this.onRedo,
    this.canRedo = false,
    this.onReset,
    this.onSave,
    this.saveLabel,
  });

  final VoidCallback? onRedo;
  final bool canRedo;

  /// The primary button's words (null: by [draft] / [replace]).
  final String? saveLabel;

  /// A session material (D-315): the result is a DRAFT students don't see until it is published — no keep /
  /// replace choice here (that is the publish step), "Save as draft".
  final bool draft;

  /// The name field (the page owns its controller).
  final Widget title;
  final bool replace;
  final bool canSave;
  final bool canUndo;
  final bool busy;

  /// A merge: "Replace the originals".
  final bool merge;
  final ValueChanged<bool>? onReplace;
  final VoidCallback? onUndo;
  final VoidCallback? onReset;
  final VoidCallback? onSave;

  Widget get form => _StudioSaveForm(area: this);
  Widget get actions => _StudioSaveActions(area: this);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [form, const SizedBox(height: AppSpace.sm), actions],
      );
}

class _StudioSaveForm extends StatelessWidget {
  const _StudioSaveForm({required this.area});
  final StudioSaveArea area;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = area;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      a.title,
      const SizedBox(height: AppSpace.xxs),
      if (a.draft)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_off_outlined, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Text(
              t('يُحفظ مسودة لا يراها الطلاب. بعد أن تجهز اختر نشرها مادة جديدة أو استبدال الأصل.',
                  "Saved as a draft students don't see. Once it is ready, publish it as a new material or in place of the original."),
              key: const ValueKey('studio.draft.note'),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
          ),
        ])
      else
        _Choices(children: [
          _Choice(
            key: const ValueKey('studio.keep'),
            label: a.merge ? t('أبقِ الأصول', 'Keep the originals') : t('أبقِ الأصل', 'Keep the original'),
            icon: Icons.copy_all_rounded,
            selected: !a.replace,
            onTap: a.busy ? null : () => a.onReplace?.call(false),
          ),
          _Choice(
            key: const ValueKey('studio.replace'),
            label: a.merge ? t('استبدل الأصول', 'Replace the originals') : t('استبدل الأصل', 'Replace the original'),
            icon: Icons.swap_horiz_rounded,
            selected: a.replace,
            tone: c.warning,
            onTap: a.busy ? null : () => a.onReplace?.call(true),
          ),
        ]),
      if (a.replace && !a.draft) ...[
        const SizedBox(height: AppSpace.xs),
        Text(
          t('يُحذف الأصل من القائمة ومن السحابة بعد نجاح التعديل فقط.', 'The original is deleted from the list and the drive only once the edit is done.'),
          style: AppType.meta(context).copyWith(color: c.warning),
        ),
      ],
    ]);
  }
}

class _StudioSaveActions extends StatelessWidget {
  const _StudioSaveActions({required this.area});
  final StudioSaveArea area;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = area;
    final can = a.canUndo && !a.busy;
    return Row(children: [
      IconButton(
        key: const ValueKey('studio.undo'),
        tooltip: t('تراجع (Ctrl+Z)', 'Undo (Ctrl+Z)'),
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.undo_rounded, color: can ? c.textDark : c.textLight),
        onPressed: can ? a.onUndo : null,
      ),
      IconButton(
        key: const ValueKey('studio.redo'),
        tooltip: t('إعادة (Ctrl+Shift+Z)', 'Redo (Ctrl+Shift+Z)'),
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.redo_rounded, color: a.canRedo && !a.busy ? c.textDark : c.textLight),
        onPressed: a.canRedo && !a.busy ? a.onRedo : null,
      ),
      IconButton(
        key: const ValueKey('studio.reset'),
        tooltip: t('من جديد', 'Start over'),
        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
        icon: Icon(Icons.restart_alt_rounded, color: can ? c.textDark : c.textLight),
        onPressed: can ? a.onReset : null,
      ),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: AppButton.primary(
          key: const ValueKey('studio.save'),
          label: a.saveLabel ?? (a.draft
              ? t('حفظ كمسودة', 'Save as draft')
              : a.replace
                  ? t('حفظ واستبدال', 'Save and replace')
                  : t('حفظ كتسجيل جديد', 'Save as new')),
          icon: Icons.save_alt_rounded,
          busy: a.busy,
          expand: true,
          size: AppButtonSize.lg,
          onPressed: a.canSave && !a.busy ? a.onSave : null,
        ),
      ),
    ]);
  }
}

/// A job's stages in order (the strip over its bar).
const studioJobStages = <String>['queued', 'downloading', 'processing', 'uploading'];

String studioStageLabel(String stage) => switch (stage) {
      'queued' => t('في الدور', 'Queued'),
      'downloading' => t('جلب', 'Fetch'),
      'processing' => t('تعديل', 'Edit'),
      'uploading' => t('حفظ', 'Save'),
      _ => stage,
    };

/// "About 3 min left" (null: not known yet).
String? studioEtaText(Duration? eta) {
  if (eta == null) return null;
  final s = eta.inSeconds;
  if (s < 10) return t('ثوانٍ قليلة متبقية', 'A few seconds left');
  if (s < 60) return t('أقل من دقيقة', 'Under a minute left');
  final m = (s / 60).ceil();
  return t('نحو $m د متبقية', 'About $m min left');
}

/// A saved edit, inline: its stages, % and time left, Cancel; then Play · Download · Continue (ready) or Retry
/// (failed / stopped).
class StudioJobCard extends StatelessWidget {
  const StudioJobCard({
    super.key,
    required this.items,
    this.onPlay,
    this.onRetry,
    this.onCancel,
    this.onDownload,
    this.onContinue,
    this.onAgain,
    this.onLibrary,
    this.actionsFor,
    this.eta = const {},
    this.downloading = const {},
    this.drafts = false,
    this.libraryLabel,
  });

  final List<RecordItem> items;
  final ValueChanged<RecordItem>? onPlay;
  final ValueChanged<RecordItem>? onRetry;
  final ValueChanged<RecordItem>? onCancel;
  final ValueChanged<RecordItem>? onDownload;

  /// Open its project again (a finished project job).
  final ValueChanged<RecordItem>? onContinue;

  /// A finished item's own buttons next to Play (a material draft: Publish, Discard — D-315).
  final Widget? Function(RecordItem r)? actionsFor;

  /// Time left per item id.
  final Map<int, Duration?> eta;

  /// A download running per item id (0–1).
  final Map<int, double> downloading;

  /// The items are drafts (a session material): "Draft ready — publish it" instead of "Ready in Records".
  final bool drafts;

  /// The back-to-the-list button's words (null: "To Records").
  final String? libraryLabel;

  /// Edit the original again.
  final VoidCallback? onAgain;
  final VoidCallback? onLibrary;

  Widget _stages(BuildContext context, RecordItem r) {
    final c = context.colors;
    final at = math.max(0, studioJobStages.indexOf(r.status == 'uploading' ? 'uploading' : (r.stage ?? 'queued')));
    return Row(children: [
      for (final (i, s) in studioJobStages.indexed)
        Expanded(
          child: Row(children: [
            Icon(i < at ? Icons.check_circle_rounded : (i == at ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                size: AppIconSize.xs, color: i <= at ? (c.isDark ? c.textDark : c.primary) : c.textLight),
            const SizedBox(width: 3),
            Flexible(
              child: Text(studioStageLabel(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText(11, w: i == at ? FontWeight.w700 : FontWeight.w500, c: i == at ? c.textDark : c.textMedium)),
            ),
            if (i < studioJobStages.length - 1)
              Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 3), color: i < at ? c.primary.withValues(alpha: c.isDark ? 0.7 : 0.5) : c.divider)),
          ]),
        ),
    ]);
  }

  Widget _row(BuildContext context, RecordItem r) {
    final c = context.colors;
    final (IconData icon, Color tone) = r.isFailed
        ? (r.cancelled ? Icons.stop_circle_outlined : Icons.error_outline_rounded, r.cancelled ? c.textMedium : c.danger)
        : r.isDone
            ? (Icons.check_rounded, c.success)
            : (Icons.movie_filter_rounded, c.isDark ? c.textDark : c.primary);
    final dl = downloading[r.id];
    final etaText = studioEtaText(eta[r.id]);
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: tone),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          ),
          if (r.inProgress && r.progress != null) ...[
            const SizedBox(width: AppSpace.xs),
            Text('${r.progress}%', key: ValueKey('studio.job.pct.${r.id}'), style: _tabular(AppType.row(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600))),
          ],
        ]),
        if (r.inProgress) ...[
          const SizedBox(height: AppSpace.xs),
          _stages(context, r),
          const SizedBox(height: AppSpace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: r.progress == null ? 0 : (r.progress! / 100).clamp(0.0, 1.0)),
              duration: AppMotion.of(context).slow,
              builder: (_, v, _) => LinearProgressIndicator(
                value: r.progress == null ? null : v,
                minHeight: 6,
                color: c.isDark ? c.textDark : c.primary,
                backgroundColor: c.divider,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Row(children: [
            Expanded(
              child: Text([recordStatusLabel(r), ?etaText].join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ),
            if (onCancel != null)
              TextButton.icon(
                key: ValueKey('studio.job.cancel.${r.id}'),
                onPressed: () => onCancel!(r),
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.danger),
                icon: const Icon(Icons.stop_rounded, size: AppIconSize.sm),
                label: Text(t('إيقاف', 'Stop')),
              ),
          ]),
        ] else if (r.isFailed) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(r.cancelled ? t('أوقفت هذا التعديل. يمكنك إعادته متى شئت.', 'You stopped this edit. You can run it again any time.') : (r.error ?? t('تعذّر إكمال العمل', 'The work could not finish')),
              style: AppType.meta(context).copyWith(color: r.cancelled ? c.textMedium : c.danger)),
          if ((onRetry != null && r.retryMode != 'auto') || actionsFor != null) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              if (onRetry != null && r.retryMode != 'auto')
                AppPill(
                    key: ValueKey('studio.job.retry.${r.id}'),
                    icon: Icons.refresh_rounded,
                    label: r.cancelled ? t('تشغيل من جديد', 'Run again') : t('إعادة المحاولة', 'Retry'),
                    color: c.warning,
                    onTap: () => onRetry!(r)),
              ?actionsFor?.call(r),
            ]),
          ],
        ] else if (r.isDone) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (onPlay != null)
              AppPill(key: ValueKey('studio.job.play.${r.id}'), icon: Icons.play_arrow_rounded, label: t('تشغيل', 'Play'),
                  color: c.success, onTap: () => onPlay!(r)),
            if (onDownload != null)
              AppPill(
                  key: ValueKey('studio.job.download.${r.id}'),
                  icon: dl != null ? Icons.downloading_rounded : Icons.download_rounded,
                  label: dl != null ? (dl > 0 ? '${(dl * 100).round()}%' : t('يُنزّل…', 'Downloading…')) : t('تنزيل', 'Download'),
                  onTap: dl != null ? null : () => onDownload!(r)),
            if (onContinue != null && r.hasProject)
              AppPill(key: ValueKey('studio.job.continue.${r.id}'), icon: Icons.edit_note_rounded, label: t('متابعة التعديل', 'Continue editing'),
                  onTap: () => onContinue!(r)),
            ?actionsFor?.call(r),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = items.isNotEmpty && items.every((r) => r.isDone);
    final failed = !done && items.isNotEmpty && !items.any((r) => r.inProgress) && items.any((r) => r.isFailed);
    final stopped = failed && items.every((r) => !r.isFailed || r.cancelled);
    final tone = done ? c.success : (failed ? (stopped ? c.textMedium : c.danger) : (c.isDark ? c.textDark : c.primary));
    final String head = done
        ? (drafts ? t('المسودة جاهزة', 'The draft is ready') : t('جاهز في «التسجيلات»', 'Ready in Records'))
        : failed
            ? (stopped ? t('أوقفت الحفظ', 'You stopped the save') : t('تعذّر إكمال العمل', 'The work could not finish'))
            : t('يجري الحفظ', 'Saving');
    final String? sub = done
        ? (drafts ? t('شغّلها ثم انشرها', 'Play it, then publish it') : null)
        : failed
            ? null
            : (drafts
                ? t('يمكنك المتابعة، تظهر المسودة في مواد الحصة', 'Carry on, the draft shows in the session materials')
                : t('يمكنك المتابعة، سيصلك إشعار', 'Carry on, you will be notified'));
    return Column(
      key: const ValueKey('studio.job'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: 0.14)),
            child: done || failed
                ? Icon(done ? Icons.check_circle_rounded : (stopped ? Icons.stop_circle_outlined : Icons.error_outline_rounded), color: tone, size: AppIconSize.md)
                : Padding(
                    padding: const EdgeInsets.all(AppSpace.xs + 1),
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: tone),
                  ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(head, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              if (sub != null) Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
        ]),
        for (final r in items) ...[
          const SizedBox(height: AppSpace.xs),
          _row(context, r),
        ],
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          if (onAgain != null)
            Expanded(
              child: AppButton(
                key: const ValueKey('studio.job.again'),
                label: t('تعديل', 'Edit'),
                icon: Icons.edit_rounded,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.md,
                expand: true,
                onPressed: onAgain,
              ),
            ),
          if (onAgain != null && onLibrary != null) const SizedBox(width: AppSpace.xs),
          if (onLibrary != null)
            Expanded(
              child: AppButton(
                key: const ValueKey('studio.job.library'),
                label: libraryLabel ?? t('إلى التسجيلات', 'To Records'),
                icon: Icons.video_library_rounded,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.md,
                expand: true,
                onPressed: onLibrary,
              ),
            ),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The whole Studio
// ─────────────────────────────────────────────────────────────────────────────

/// Below this width (upright) the Studio stacks: stage, timeline, the inspector as a sheet, the tool strip.
const studioWideMin = 960.0;

/// The round play mark over a paused picture.
class StudioPlayMark extends StatelessWidget {
  const StudioPlayMark({super.key, required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: playing ? 0 : 1,
          duration: AppMotion.of(context).fast,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.heroShade.withValues(alpha: 0.55),
              border: Border.all(color: c.heroGlassBorder),
            ),
            child: Icon(Icons.play_arrow_rounded, color: c.onHero, size: AppIconSize.xl + 4),
          ),
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.preview, this.note, this.rounded = false, this.aspect = 16 / 9});
  final Widget preview;
  final String? note;
  final bool rounded;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final bay = StudioBay.of(context);
    final radius = BorderRadius.circular(rounded ? AppRadius.card : 0);
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: rounded
                ? [BoxShadow(color: bay.floor.withValues(alpha: 0.7), blurRadius: 36, offset: const Offset(0, 14))]
                : null,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: ColoredBox(
              color: bay.deck,
              child: Stack(fit: StackFit.expand, children: [
                preview,

                if (note != null)
                  PositionedDirectional(
                    top: AppSpace.sm,
                    start: AppSpace.sm,
                    end: AppSpace.sm,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          key: const ValueKey('studio.stage_note'),
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 1),
                          decoration: BoxDecoration(color: bay.ink.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(14)),
                          child: Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: bay.deck, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class RecordStudioLayout extends StatelessWidget {
  const RecordStudioLayout({
    super.key,
    required this.preview,
    required this.transport,
    required this.timeline,
    required this.tool,
    required this.panel,
    required this.summary,
    required this.save,
    this.job,
    this.onTool,
    this.busy = false,
    this.footer,
    this.stageNote,
    this.tools = StudioTool.values,
    this.canvas = StudioCanvas.dark,
    this.aspect = 16 / 9,
  });

  final StudioCanvas canvas;

  /// The picture's width / height (the stage keeps it).
  final double aspect;

  /// The source's tools (StudioSource.tools).
  final List<StudioTool> tools;

  /// The player (or a still / a placeholder in tests), drawn 16:9 on the stage.
  final Widget preview;
  final Widget transport;
  final Widget timeline;
  final StudioTool tool;
  final Widget panel;
  final Widget summary;

  /// The save area (cover: none — it saves at once).
  final StudioSaveArea? save;

  /// A saved edit's job: replaces the save area.
  final Widget? job;
  final ValueChanged<StudioTool>? onTool;
  final bool busy;

  /// Under the inspector's content (the keyboard hint on the web).
  final Widget? footer;

  /// Said on the stage (what is being dragged: "Start 01:23.45").
  final String? stageNote;

  /// The inspector's scrolling content, on phones and wide screens alike. A running or finished job takes it over: the
  /// tools are off until "Another edit" anyway, and on a phone the job must not wait below the fold.
  Widget _inspectorBody() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (job != null)
          job!
        else ...[
          _InspectorHead(tool: tool),
          const SizedBox(height: AppSpace.md),
          panel,
          const SizedBox(height: AppSpace.md),
          summary,
          if (save != null) const SizedBox(height: AppSpace.md),
          ?save?.form,
        ],
        ?footer,
      ]);

  /// Undo and the primary button, pinned under the inspector (none while a job runs).
  Widget? _actionBar(BuildContext context, EdgeInsets padding) {
    final s = save;
    if (job != null || s == null) return null;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.divider))),
      child: Padding(padding: padding, child: s.actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bay = StudioBay.of(context);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight, w = box.maxWidth;
      if (studioIsWide(box.biggest)) {
        final inspectorW = math.max(300.0, math.min(380.0, w * 0.34));
        return Material(
          color: bay.deck,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 80,
              child: DecoratedBox(
                decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: bay.line))),
                child: StudioToolRail(tool: tool, onTool: onTool, enabled: !busy, tools: tools),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: ColoredBox(
                    color: bay.canvas(canvas),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: _Stage(preview: preview, note: stageNote, rounded: true, aspect: aspect),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: bay.line))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, AppSpace.sm),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      transport,
                      const SizedBox(height: AppSpace.xxs),
                      timeline,
                    ]),
                  ),
                ),
              ]),
            ),
            SizedBox(
              width: inspectorW,
              child: Material(
                color: c.cardBg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('studio.side'),
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: _inspectorBody(),
                    ),
                  ),
                  ?_actionBar(context, const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.sm, AppSpace.md, AppSpace.sm)),
                ]),
              ),
            ),
          ]),
        );
      }
      // Phones: the picture and the timeline stay in view while the inspector scrolls under them. The on-screen
      // keyboard folds the bay away (Offstage, so the player and the typed name keep their state): the field needs the room.
      final keyboard = View.of(context).viewInsets.bottom > 0;
      final stageH = math.min(w / aspect.clamp(0.5, 3.0), h * (h < 600 ? 0.24 : 0.30));
      return Material(
        color: bay.deck,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Visibility(
            visible: !keyboard,
            maintainState: true,
            maintainAnimation: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: stageH, child: ColoredBox(color: bay.canvas(canvas), child: _Stage(preview: preview, note: stageNote, aspect: aspect))),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  transport,
                  timeline,
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.sheetTop,
              child: Material(
                color: c.cardBg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('studio.scroll'),
                      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
                      child: _inspectorBody(),
                    ),
                  ),
                  ?_actionBar(context, const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.md, AppSpace.xs)),
                ]),
              ),
            ),
          ),
          Visibility(
            visible: !keyboard,
            maintainState: true,
            child: StudioToolBar(tool: tool, onTool: onTool, enabled: !busy, tools: tools),
          ),
        ]),
      );
    });
  }
}

/// The web / desktop keys, shown at the end of the inspector.
class StudioKeysHint extends StatelessWidget {
  const StudioKeysHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String k, String what) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: c.divider),
            ),
            child: Text(k, textDirection: TextDirection.ltr, style: AppType.overline(context).copyWith(color: c.textDark, letterSpacing: 0)),
          ),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
        ]);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        key(t('مسافة', 'Space'), t('تشغيل / إيقاف', 'Play / pause')),
        key('J · K · L', t('رجوع · إيقاف · تقديم', 'Back · pause · forward')),
        key('← →', t('إطار (Shift: ثانية)', 'A frame (Shift: a second)')),
        key('I · O', t('علامة البداية / النهاية', 'Mark in / out')),
        key('S', t('تقسيم عند المؤشر', 'Split at the playhead')),
        key('Del', t('حذف المحدد', 'Delete the selection')),
        key('Ctrl+Z', t('تراجع', 'Undo')),
        key('Ctrl+Shift+Z', t('إعادة', 'Redo')),
        key('Ctrl + ${t('العجلة', 'wheel')}', t('تكبير الخط الزمني', 'Zoom the timeline')),
      ]),
    );
  }
}

/// Merge candidates for [item]: the other ready items of [all], [picked] (ids, in order) numbered.
List<StudioMergePick> studioMergePicks(RecordItem item, List<RecordItem> all, List<int> picked) => [
      for (final r in all)
        if (r.id != item.id && r.mergeable)
          StudioMergePick(item: r, order: picked.contains(r.id) ? picked.indexOf(r.id) + 1 : null),
    ];

/// "2 recordings · 1:20:00", the merge's line.
String studioMergeLine(List<RecordItem> parts) => '${recordsCountText(parts.length)} · ${mmss(mergedDuration(parts))}';
