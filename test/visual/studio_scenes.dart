// The Studio scenes the visual renders draw (studio_golden_test.dart): plain values, no player.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/records/studio_export.dart';
import 'package:flutter_education_app/features/records/studio_panels.dart';
import 'package:flutter_education_app/features/records/studio_project.dart';
import 'package:flutter_education_app/features/records/studio_stage.dart';
import 'package:flutter_education_app/features/records/studio_timeline.dart';

enum StudioScene { edit, text, export, job }

StudioEdit _edit() => StudioEdit.original(3125)
    .split(600)
    .remove(1200, 1500)
    .split(1700)
    .speedOn(1.5, clip: 0)
    .putOverlay(const StudioOverlay(id: 'o1', kind: StudioOverlayKind.text, start: 700, end: 900, x: 0.5, y: 0.82, text: 'Fractions — part 1', size: 0.06))
    .putOverlay(const StudioOverlay(id: 'o3', kind: StudioOverlayKind.text, start: 1800, end: 1950, x: 0.5, y: 0.14, text: 'Exercise 2', size: 0.05))
    .putOverlay(const StudioOverlay(id: 'o2', kind: StudioOverlayKind.image, start: 740, end: 1100, asset: 'a1', aspect: 0.5, x: 0.85, y: 0.15, w: 0.14));

class _FakeFrame extends StatelessWidget {
  const _FakeFrame();
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF243B55), Color(0xFF3C6E71)])),
        child: LayoutBuilder(
          builder: (context, b) => Padding(
            padding: EdgeInsets.all(b.maxWidth * 0.08),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: b.maxHeight * 0.08, width: b.maxWidth * 0.5, color: const Color(0xDDFFFFFF)),
              SizedBox(height: b.maxHeight * 0.06),
              for (var i = 0; i < 4; i++) ...[
                Container(height: b.maxHeight * 0.03, width: b.maxWidth * (0.7 - i * 0.08), color: const Color(0x88FFFFFF)),
                SizedBox(height: b.maxHeight * 0.04),
              ],
            ]),
          ),
        ),
      );
}

List<StudioAction> _clipActions() => [
      StudioAction(id: 'split', icon: Icons.content_cut_rounded, label: 'Split', onTap: () {}),
      StudioAction(id: 'speed', icon: Icons.speed_rounded, label: 'Speed', onTap: () {}),
      StudioAction(id: 'move_back', icon: Icons.keyboard_double_arrow_left_rounded, label: 'Earlier', onTap: () {}),
      StudioAction(id: 'move_fwd', icon: Icons.keyboard_double_arrow_right_rounded, label: 'Later', onTap: () {}),
      StudioAction(id: 'delete_clip', icon: Icons.delete_outline_rounded, label: 'Delete', danger: true, onTap: () {}),
    ];

Widget _sheet(BuildContext context, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  final card = Material(
    color: context.colors.cardBg,
    borderRadius: wide ? BorderRadius.circular(AppRadius.sheet) : AppRadius.sheetTop,
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(child: child),
  );
  return Stack(children: [
    Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
    Align(
      alignment: wide ? Alignment.center : Alignment.bottomCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity, maxHeight: MediaQuery.sizeOf(context).height * 0.86), child: card),
    ),
  ]);
}

Widget studioSceneView(StudioScene scene, {required RecordItem item, ui.Image? sprite, Uint8List? waveform}) {
  final e = _edit();
  final tool = scene == StudioScene.text ? StudioTool.text : StudioTool.edit;
  final pos = scene == StudioScene.text ? 760.0 : 640.0;
  return Builder(builder: (context) {
    final wide = studioIsWide(MediaQuery.sizeOf(context));
    final layout = RecordStudioLayout(
      tool: tool,
      tools: [for (final x in StudioTool.values) if (x.inRail) x],
      onTool: (_) {},
      preview: Stack(fit: StackFit.expand, children: [
        const _FakeFrame(),
        StudioOverlayLayer(edit: e, now: pos, selected: scene == StudioScene.text ? 'o1' : null),
      ]),
      transport: StudioTransport(position: pos, duration: e.duration, zoom: 1, maxZoom: 64, onPlayPause: () {}, onSkip: (_) {}, onPreviewSpeed: () {}, onZoom: (_) {}),
      timeline: StudioTimelineView(
        edit: e,
        position: pos,
        sourceDuration: 3125,
        selectedClip: scene == StudioScene.edit ? 1 : null,
        selectedOverlay: scene == StudioScene.text ? 'o1' : null,
        sprite: sprite,
        spriteCount: 25,
        waveform: waveform,
        onScrub: (_) {},
        onMoveClip: (_, _) {},
      ),
      actions: _clipActions(),
      actionContext: StudioActionContext(label: 'Part 2 of 4 · 05:00.0', onClear: () {}),
      panelOpen: scene == StudioScene.text && !wide,
      onClosePanel: () {},
      panel: tool == StudioTool.edit
          ? StudioEditPanel(edit: e, position: pos, selectedClip: 1, onSplit: () {}, onSpeed: (_) {})
          : StudioOverlayPanel(kind: StudioOverlayKind.text, edit: e, position: pos, selected: e.overlays.first, onChange: (_, {required commit, required kind}) {}),
      footer: wide ? const StudioKeysHint() : null,
    );
    final running = RecordItem.fromJson({'recording_id': 9, 'kind': 'edit', 'status': 'assembling', 'stage': 'processing', 'progress': 55, 'title': 'Lesson 3 · edited'})!;
    final page = Scaffold(
      appBar: StudioTopBar(
        title: item.title,
        facts: item.facts(),
        saveState: StudioSaveState.saved,
        onCanvas: () {},
        onDownload: () {},
        canUndo: true,
        onUndo: () {},
        onRedo: () {},
        onExport: () {},
        exporting: scene == StudioScene.job ? 55 : null,
      ),
      body: layout,
    );
    if (scene == StudioScene.export) {
      return Stack(children: [
        page,
        _sheet(
          context,
          AppSheetContent(title: 'Export', icon: Icons.ios_share_rounded, subtitle: item.title, children: [
            StudioExportSettings(
              item: item,
              duration: e.duration,
              form: StudioSaveArea(title: const TextField(decoration: InputDecoration(labelText: 'Name of the new recording')), onReplace: (_) {}).form,
              height: 720,
              onQuality: (_, _) {},
              halves: (640, e.duration - 640),
              onTwoFiles: (_) {},
              result: [e.duration],
              onExport: () {},
            ),
          ]),
        ),
      ]);
    }
    if (scene == StudioScene.job) {
      return Stack(children: [
        page,
        _sheet(
          context,
          AppSheetContent(title: 'Exporting', icon: Icons.ios_share_rounded, children: [
            StudioExportJob(
              running: true,
              card: StudioJobCard(items: [running], eta: const {9: Duration(minutes: 3)}, onCancel: (_) {}),
              onKeepEditing: () {},
              onExportAgain: () {},
            ),
          ]),
        ),
      ]);
    }
    return page;
  });
}
