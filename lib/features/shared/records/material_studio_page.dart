// lib/features/shared/records/material_studio_page.dart — the Studio on a course session's VIDEO material (D-315).
// Pure parts: material_studio_api.dart; plain values: material_studio_parts.dart; the Studio itself:
// records_studio.dart on a MaterialStudioSource.
//
//   openMaterialStudio(context, sessionId:, materialId:)   the session materials' Studio button and the player's
//                                  Open in Studio (teachers / the course staff only; kill switch materials.studio).
//                                  Pops `true` when something was published, so the session reloads its materials.
//   MaterialStudioDraftsPanel      above a session's materials (staff): its drafts with Play · Publish · Discard,
//                                  Retry, and after a replace Restore the original · Delete the old file. Follows
//                                  running jobs with EventOrPoll on job_updated{kind: material_edit}; draws nothing
//                                  when there is no draft.
//   showMaterialPublishSheet       A new material · Replace the original (what each means), then publish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'material_studio_api.dart';
import 'material_studio_parts.dart';
import 'records_api.dart';
import 'records_share.dart' show RecordPlayerPage;
import 'records_studio.dart';
import 'studio_download_io.dart' if (dart.library.js_interop) 'studio_download_web.dart' as saver;

/// May this person see the Studio entries at all (the kill switch; the server checks who may edit).
bool get materialStudioOn => !AppConfig.disableList.contains(kMaterialsStudioFeatureKey);

/// Bumped every time a Studio closes: the drafts panels load again.
final materialStudioRevision = ValueNotifier<int>(0);

/// Opens the Studio on [navigator] (null: the one of [context]). [replaceTop]: the top route (the player whose Open in
/// Studio was tapped) is REPLACED by the Studio in one step: no pop-then-push from a context the pop may take away.
Future<bool> openMaterialStudio(BuildContext? context,
    {required int sessionId, required int materialId, MaterialStudioApi? api, NavigatorState? navigator, bool replaceTop = false}) async {
  if (!materialStudioOn) return false;
  final nav = navigator ?? Navigator.of(context!, rootNavigator: true); // full screen: an editor needs the room the shell's bars take
  final route = MaterialPageRoute<bool>(
    settings: const RouteSettings(name: '/materials/studio'),
    builder: (_) => MaterialStudioPage(sessionId: sessionId, materialId: materialId, api: api),
  );
  final changed = await (replaceTop ? nav.pushReplacement<bool, Object?>(route) : nav.push<bool>(route));
  materialStudioRevision.value++;
  return changed == true;
}

/// Plays a ready draft in the course player (the staff stream).
Future<void> playMaterialDraft(BuildContext context, MaterialDraft d, MaterialStudioApi api) =>
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/materials/studio/draft'),
      builder: (_) => RecordPlayerPage(
        title: d.item.title,
        subtitle: t('مسودة — لا يراها الطلاب', "Draft — students don't see it"),
        play: () => api.playDraft(d.id),
      ),
    ));

/// The publish sheet. Returns the published draft (null: nothing published).
Future<MaterialDraft?> showMaterialPublishSheet(BuildContext context, MaterialDraft d, MaterialStudioApi api) =>
    showAppSheet<MaterialDraft>(context, (_) => _PublishSheet(draft: d, api: api));

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.draft, required this.api});
  final MaterialDraft draft;
  final MaterialStudioApi api;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  MaterialPublishMode _mode = MaterialPublishMode.asNew;
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final (d, _) = await widget.api.publish(widget.draft.id, _mode);
      if (!mounted) return;
      showAppNotice(_mode == MaterialPublishMode.replace
          ? t('نُشر بدلاً من الأصل — الملف القديم محفوظ حتى تؤكّد حذفه', 'Published in place of the original — the old file is kept until you delete it')
          : t('نُشر مادة جديدة بعد الأصل', 'Published as a new material after the original'));
      Navigator.of(context).pop(d ?? widget.draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(materialStudioErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('نشر «${widget.draft.item.title}»', 'Publish “${widget.draft.item.title}”'),
        children: [
          MaterialPublishChoice(
            mode: _mode,
            canReplace: widget.draft.sourceMaterialId != null,
            busy: _busy,
            onMode: (m) => setState(() => _mode = m),
            onPublish: _go,
          ),
        ],
      );
}

/// The draft actions both the panel and the Studio's job card run. Returns the fresh draft (null: it is gone or
/// nothing changed); [published] is told when a material changed.
Future<MaterialDraft?> runMaterialDraftAction(BuildContext context, MaterialDraft d, MaterialDraftAction a, MaterialStudioApi api,
    {VoidCallback? published}) async {
  try {
    switch (a) {
      case MaterialDraftAction.play:
        await playMaterialDraft(context, d, api);
        return null;
      case MaterialDraftAction.publish:
        final p = await showMaterialPublishSheet(context, d, api);
        if (p != null) published?.call();
        return p;
      case MaterialDraftAction.discard:
        if (!await appConfirm(context,
            message: t('ستُحذف المسودة وملفها. متابعة؟', 'The draft and its file will be deleted. Continue?'),
            danger: true,
            confirmLabel: t('تجاهل', 'Discard'))) {
          return null;
        }
        await api.discard(d.id);
        showAppNotice(t('حُذفت المسودة', 'Draft discarded'));
        return null;
      case MaterialDraftAction.retry:
        return await api.retry(d.id);
      case MaterialDraftAction.cancel:
        if (!await appConfirm(context,
            message: t('إيقاف حفظ «${d.item.title}»؟ يمكنك تشغيله من جديد لاحقاً.', 'Stop saving “${d.item.title}”? You can run it again later.'),
            danger: true,
            confirmLabel: t('إيقاف', 'Stop'))) {
          return null;
        }
        return await api.cancel(d.id);
      case MaterialDraftAction.download:
        final dl = await api.downloadDraft(d.id);
        showAppNotice(t('يُنزّل «${dl.fileName}»…', 'Downloading “${dl.fileName}”…'));
        await saver.studioSaveUrl(dl.url, dl.fileName);
        return null;
      case MaterialDraftAction.restore:
        final r = await api.restore(d.id);
        published?.call();
        showAppNotice(t('عاد الملف الأصلي — المسودة محفوظة', 'The original file is back — the draft is kept'));
        return r;
      case MaterialDraftAction.confirm:
        if (!context.mounted ||
            !await appConfirm(context,
                message: t('سيُحذف الملف القديم نهائياً ولن يمكن استرجاعه. متابعة؟', 'The old file will be deleted for good. Continue?'),
                danger: true,
                confirmLabel: t('حذف الملف القديم', 'Delete the old file'))) {
          return null;
        }
        final r = await api.confirm(d.id);
        showAppNotice(t('حُذف الملف القديم', 'The old file was deleted'));
        return r;
    }
  } catch (e) {
    showAppNotice(materialStudioErrorText(e), error: true);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The Studio page
// ─────────────────────────────────────────────────────────────────────────────

class MaterialStudioPage extends StatefulWidget {
  const MaterialStudioPage({super.key, required this.sessionId, required this.materialId, this.api});
  final int sessionId;
  final int materialId;
  final MaterialStudioApi? api;

  @override
  State<MaterialStudioPage> createState() => _MaterialStudioPageState();
}

class _MaterialStudioPageState extends State<MaterialStudioPage> {
  late final MaterialStudioApi _api = widget.api ?? RemoteMaterialStudioApi();
  late final MaterialStudioSource _src = MaterialStudioSource(sessionId: widget.sessionId, materialId: widget.materialId, api: _api);
  MaterialStudioOpen? _open;
  String? _error;
  bool _changed = false;
  final _published = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await _api.open(widget.sessionId, widget.materialId);
      if (!mounted) return;
      setState(() {
        _open = o;
        if (o == null) _error = t('هذه المادة غير متاحة', 'This material is not available');
      });
    } catch (e) {
      if (mounted) setState(() => _error = materialStudioErrorText(e));
    }
  }

  Widget? _jobActions(BuildContext context, RecordItem r) {
    final d = _src.latest[r.id];
    if (d == null) return null;
    if (_published.contains(d.id)) {
      return AppPill(icon: Icons.check_rounded, label: t('نُشر', 'Published'), color: context.colors.success, onTap: null);
    }
    if (!d.canPublish) return null;
    return AppPill(
      key: ValueKey('studio.job.publish.${d.id}'),
      icon: Icons.publish_rounded,
      label: t('نشر', 'Publish'),
      onTap: () async {
        final p = await runMaterialDraftAction(context, d, MaterialDraftAction.publish, _api, published: () => _changed = true);
        if (p != null && mounted) setState(() => _published.add(d.id));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _open;
    if (o != null) {
      return RecordStudioPage(
        item: o.source,
        others: o.others,
        source: _src,
        jobActions: _jobActions,
        popResult: () => _changed, // the Studio's own PopScope pops with it: ONE pop per Back
        libraryLabel: t('إلى مواد الحصة', 'To the session'),
        onPlay: (ctx, r) {
          final d = _src.latest[r.id];
          if (d != null) playMaterialDraft(ctx, d, _api);
        },
      );
    }
    return BasePage(
      appBar: ScreenAppBar(title: t('الاستوديو', 'Studio')),
      child: _error == null
          ? const AppListSkeleton(items: 3)
          : AppEmpty(
              icon: Icons.movie_edit,
              title: t('تعذّر فتح الاستوديو', "Couldn't open the Studio"),
              message: _error,
              actionLabel: t('إعادة المحاولة', 'Try again'),
              onAction: _load,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The drafts above a session's materials
// ─────────────────────────────────────────────────────────────────────────────

class MaterialStudioDraftsPanel extends StatefulWidget {
  const MaterialStudioDraftsPanel({super.key, required this.sessionId, this.onChanged, this.api});
  final int sessionId;

  /// A material changed (published / restored): the session reloads its materials.
  final VoidCallback? onChanged;
  final MaterialStudioApi? api;

  @override
  State<MaterialStudioDraftsPanel> createState() => _MaterialStudioDraftsPanelState();
}

class _MaterialStudioDraftsPanelState extends State<MaterialStudioDraftsPanel> {
  late final MaterialStudioApi _api = widget.api ?? RemoteMaterialStudioApi();
  List<MaterialDraft> _drafts = const [];
  bool _busy = false;
  EventOrPoll? _watch;

  @override
  void initState() {
    super.initState();
    materialStudioRevision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant MaterialStudioDraftsPanel old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) _load();
  }

  @override
  void dispose() {
    materialStudioRevision.removeListener(_load);
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ds = await _api.sessionDrafts(widget.sessionId);
      if (!mounted) return;
      setState(() => _drafts = ds);
    } catch (_) {
      // drafts are a staff extra: a failed load (an older server, no right) draws nothing
    }
    _follow();
  }

  void _follow() {
    if (!_drafts.any((d) => d.item.inProgress)) {
      _watch?.stop();
      return;
    }
    _watch ??= EventOrPoll(kind: 'material_edit', every: const Duration(seconds: 8), fallbackEvery: const Duration(seconds: 30), poll: _load);
    if (!_watch!.running) _watch!.start();
  }

  Future<void> _act(MaterialDraft d, MaterialDraftAction a) async {
    setState(() => _busy = true);
    await runMaterialDraftAction(context, d, a, _api, published: widget.onChanged);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) => MaterialDraftsStrip(drafts: _drafts, busy: _busy, onAction: _act);
}

/// The Studio button's tooltip / the player action's label.
String get materialStudioLabel => t('فتح في الاستوديو', 'Open in Studio');
