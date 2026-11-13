// lib/features/shared/records/records_page.dart — "Records" (D-311, D-312): My profile › Records and its sheets.
// Pure parts: records_api.dart, records_share_api.dart; plain-values widgets: records_parts.dart,
// records_share_parts.dart, records_studio_parts.dart.
//
//   RecordsPage(highlightId:, shared:)   two tabs — My recordings · Shared with me (kill switch records.share).
//                               Mine: groups by meeting, tap → the PLAYER (the course video player, as a student sees
//                               a lesson) with "Open in Studio" and "Share" on its top bar · ⋯ → the item sheet (play ·
//                               Studio · share · rename · cover · open in drive · retry · delete) · long-press → multi-
//                               select (Merge 2+ ready items in a chosen order · Delete). A running job is watched with
//                               EventOrPoll on `job_updated{kind: recording}` (no timer polling while the live stream
//                               is up). Shared with me: tap → the player. Deep links: AppNavigator modules `records`
//                               and `records_shared`.
//   The Studio (the editor): records_studio.dart · the player and the Share sheet: records_share.dart
//   (records_notice.dart: showRecordsSavingNotice — "Saving your recording to Records" + Open)
//   RecordsSettingsTile         the My-profile tile (kill switch profile.records)
//
// Every edit is a NEW item; the original stays unless the person picks "Replace the original".
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart' show LiveEvent;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../guest/guest_state.dart';
import '../live/meeting_recording_sheets.dart' show openExternalUrl;
import '../session/video/vod_player_parts.dart' show VodAction;
import 'records_api.dart';
import 'records_parts.dart';
import 'records_share.dart';
import 'records_share_api.dart';
import 'records_share_parts.dart';
import 'records_studio.dart';

/// How often the library re-reads while a job runs and the live stream is down / up (an event re-reads at once).
const recordsJobPoll = Duration(seconds: 6);
const recordsJobPollLive = Duration(seconds: 30);

/// My profile › Records.
class RecordsSettingsTile extends StatelessWidget implements AppSettingsSearchable {
  const RecordsSettingsTile({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  String get searchText => '${t('التسجيلات', 'Records')} records recordings meetings video تسجيلات اجتماعات فيديو';

  @override
  Widget build(BuildContext context) {
    if (GuestState.active || ViewAsState.active) return const SizedBox.shrink();
    return ParentComponent(
      featureKey: kRecordsFeatureKey,
      child: AppSettingsTile(
        key: const ValueKey('records.entry'),
        icon: Icons.video_library_rounded,
        color: context.colors.primary,
        label: t('التسجيلات', 'Records'),
        subtitle: t('تسجيلات اجتماعاتك وتعديلها', 'Your meeting recordings and their edits'),
        keywords: 'records recordings meetings video تسجيلات اجتماعات فيديو',
        onTap: onOpen,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library
// ─────────────────────────────────────────────────────────────────────────────

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, this.highlightId, this.api, this.shareApi, this.shared = false});

  /// The item a notification pointed at (outlined).
  final int? highlightId;
  final RecordsApi? api;
  final RecordShareApi? shareApi;

  /// Opens on "Shared with me".
  final bool shared;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  late final RecordsApi _api = widget.api ?? RemoteRecordsApi();
  late final RecordShareApi _shareApi = widget.shareApi ?? RemoteRecordShareApi();
  List<RecordItem> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _selected = {};
  EventOrPoll? _watch;
  late int _tab = widget.shared && _sharing ? 1 : 0;
  List<SharedRecord> _shared = const [];
  bool _sharedLoading = false;
  bool _sharedLoaded = false;
  String? _sharedError;

  bool get _sharing => !AppConfig.disableList.contains(kRecordsShareFeatureKey);

  @override
  void initState() {
    super.initState();
    _load();
    if (_tab == 1) _loadShared();
  }

  Future<void> _loadShared({bool silent = false}) async {
    if (!silent) setState(() => _sharedLoading = true);
    try {
      final list = await _shareApi.sharedWithMe();
      if (!mounted) return;
      setState(() {
        _shared = list;
        _sharedError = null;
        _sharedLoading = false;
        _sharedLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sharedLoading = false;
        _sharedLoaded = true;
        if (!silent) _sharedError = recordsErrorText(e);
      });
    }
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await _api.list();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
        _loading = false;
        _selected.removeWhere((id) => !list.any((r) => r.id == id && r.mergeable));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = recordsErrorText(e);
      });
    }
    _syncWatch();
  }

  /// Watch while something runs: the job's `job_updated` re-reads at once, the slow poll is only the fallback.
  void _syncWatch() {
    if (!mounted) return;
    final running = _items.any((r) => r.inProgress);
    if (!running) {
      _watch?.stop();
      return;
    }
    _watch ??= EventOrPoll(
      kind: 'recording',
      every: recordsJobPoll,
      fallbackEvery: recordsJobPollLive,
      poll: () => _load(silent: true),
      onEvent: _onEvent,
    );
    if (!_watch!.running) _watch!.start();
  }

  /// The event's stage / progress is drawn before the re-read lands.
  void _onEvent(LiveEvent e) {
    final id = int.tryParse(e.id ?? '');
    final i = _items.indexWhere((r) => r.id == id);
    if (i < 0 || !mounted) return;
    final p = int.tryParse('${e.data['progress'] ?? ''}');
    final r = _items[i];
    final status = e.status ?? r.status;
    setState(() {
      _items = [
        ..._items.sublist(0, i),
        RecordItem.fromJson({
          ..._asJson(r),
          'status': status,
          'stage': e.stage,
          'progress': p ?? r.progress,
        })!,
        ..._items.sublist(i + 1),
      ];
    });
  }

  Map<String, dynamic> _asJson(RecordItem r) => {
        'recording_id': r.id,
        'kind': r.kind,
        'title': r.title,
        'custom_title': r.customTitle,
        'status': r.status,
        'stage': r.stage,
        'progress': r.progress,
        'operation': r.operation?.wire,
        'op_params': r.opParams,
        'source_ids': r.sourceIds,
        'cover_url': r.coverUrl,
        'duration_seconds': r.durationSeconds,
        'size': r.size,
        'quality': r.quality.wire,
        'destination': r.destination?.wire,
        'remote_url': r.remoteUrl,
        'error': r.error,
        'retry_mode': r.retryMode,
        'created_at': r.createdAt?.toIso8601String(),
        'finished_at': r.finishedAt?.toIso8601String(),
        'meeting': {'id': r.meetingId, 'title': r.meetingTitle, 'starts_at': r.meetingAt?.toIso8601String()},
        'can_edit': r.canEdit,
        'can_play': r.canPlay,
      };

  void _put(List<RecordItem> fresh) {
    setState(() => _items = mergeRecordItems(_items, fresh));
    _syncWatch();
  }

  // ── taps ──

  void _tap(RecordItem r) {
    if (_selected.isNotEmpty) return _toggle(r);
    if (r.canPlay) {
      _openPlayer(r);
    } else {
      _more(r);
    }
  }

  /// The course video player on the record (D-312), with Open in Studio and Share on its top bar.
  Future<void> _openPlayer(RecordItem r) async {
    final nav = Navigator.of(context);
    final go = await nav.push<String>(MaterialPageRoute(
      settings: const RouteSettings(name: '/records/play'),
      builder: (ctx) => RecordPlayerPage(
        title: r.title,
        subtitle: [if (r.meetingTitle != null && r.meetingTitle != r.title) r.meetingTitle!, ...r.facts()].join(' · '),
        play: () => _api.play(r.id),
        actions: [
          if (r.canEdit)
            VodAction(
                id: 'studio',
                icon: Icons.auto_fix_high_rounded,
                label: t('فتح في الاستوديو', 'Open in Studio'),
                onTap: () => Navigator.of(ctx).pop('studio')),
          if (_sharing)
            VodAction(
                id: 'share',
                icon: Icons.ios_share_rounded,
                label: t('مشاركة', 'Share'),
                onTap: () => showRecordShareSheet(ctx, r, api: _shareApi)),
        ],
      ),
    ));
    if (go == 'studio' && mounted) await _openEditor(r);
  }

  void _playMade(BuildContext context, RecordItem r) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/records/play'),
      builder: (_) => RecordPlayerPage(title: r.title, play: () => _api.play(r.id)),
    ));
  }

  void _toggle(RecordItem r) {
    setState(() {
      if (_selected.contains(r.id)) {
        _selected.remove(r.id);
      } else if (r.mergeable || !r.inProgress) {
        _selected.add(r.id);
      }
    });
  }

  Future<void> _openEditor(RecordItem r) async {
    final made = await Navigator.of(context).push<List<RecordItem>>(MaterialPageRoute(
      settings: const RouteSettings(name: '/records/edit'),
      builder: (_) => RecordStudioPage(item: r, others: _items, api: _api, shareApi: _shareApi, onPlay: _playMade),
    ));
    if (!mounted || made == null || made.isEmpty) return;
    _put(made);       // a source asked to be deleted goes once the job is done: the next read shows it
  }

  Future<void> _more(RecordItem r) async {
    final c = context.colors;
    final action = await showAppSheet<String>(context, (ctx) {
      Widget row(String id, IconData icon, String label, {Color? color}) => ListTile(
            key: ValueKey('records.sheet.$id'),
            minTileHeight: AppTouch.min,
            leading: Icon(icon, color: color ?? c.textDark),
            title: Text(label, style: AppType.bodyStrong(context).copyWith(color: color ?? c.textDark)),
            onTap: () => Navigator.of(ctx).pop(id),
          );
      return AppSheetContent(title: r.title, children: [
        if (r.canPlay) row('play', Icons.play_circle_outline_rounded, t('تشغيل', 'Play')),
        if (r.canEdit) row('edit', Icons.auto_fix_high_rounded, t('فتح في الاستوديو', 'Open in Studio')),
        if (r.canPlay && _sharing) row('share', Icons.ios_share_rounded, t('مشاركة', 'Share')),
        row('rename', Icons.drive_file_rename_outline_rounded, t('تغيير الاسم', 'Rename')),
        row('cover', Icons.image_outlined, r.coverUrl == null ? t('إضافة غلاف', 'Add a cover') : t('تغيير الغلاف', 'Change the cover')),
        if (r.coverUrl != null) row('uncover', Icons.hide_image_outlined, t('إزالة الغلاف', 'Remove the cover')),
        if (r.canEdit) row('select', Icons.checklist_rounded, t('تحديد للدمج', 'Select to merge')),
        if (r.canOpenDrive) row('drive', Icons.open_in_new_rounded, t('فتح في السحابة', 'Open in the drive')),
        if (r.isFailed && r.retryMode != 'auto') row('retry', Icons.refresh_rounded, t('إعادة المحاولة', 'Retry'), color: c.warning),
        if (!r.inProgress) row('delete', Icons.delete_outline_rounded, t('حذف', 'Delete'), color: c.danger),
      ]);
    });
    if (!mounted || action == null) return;
    switch (action) {
      case 'play':
        await _openPlayer(r);
      case 'edit':
        await _openEditor(r);
      case 'share':
        await showRecordShareSheet(context, r, api: _shareApi);
      case 'rename':
        await _rename(r);
      case 'cover':
        await _cover(r);
      case 'uncover':
        await _run(() async {
          final n = await _api.clearCover(r.id);
          if (n != null) _put([n]);
        });
      case 'select':
        _toggle(r);
      case 'drive':
        if (!await openExternalUrl(r.remoteUrl ?? '')) showAppNotice(t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
      case 'retry':
        await _retry(r);
      case 'delete':
        await _delete([r]);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  Future<void> _rename(RecordItem r) async {
    final name = await showAppSheet<String>(context, (_) => _RenameSheet(initial: r.title));
    final title = (name ?? '').trim();
    if (!mounted || title.isEmpty || title == r.title) return;
    await _run(() async {
      final (item, drive) = await _api.rename(r.id, title);
      if (item != null) _put([item]);
      showAppNotice(drive || !r.isDone
          ? t('تم تغيير الاسم', 'Renamed')
          : t('تم تغيير الاسم في القائمة (لم يتغير اسم الملف في السحابة)', 'Renamed in the list (the drive file kept its name)'));
    });
  }

  Future<void> _cover(RecordItem r) async {
    final XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
    } catch (_) {
      if (mounted) showAppNotice(t('تعذّر فتح الصور', "Couldn't open your pictures"), error: true);
      return;
    }
    if (f == null || !mounted) return;
    final raw = await f.readAsBytes();
    if (!mounted) return;
    final cropped = await showAppImageCropper(context, raw, shape: CropShape.wide, allowShapeChange: false);
    if (cropped == null || !mounted) return;
    await _run(() async {
      final n = await _api.setCover(r.id, cropped, fileName: 'cover.png');
      if (n != null) _put([n]);
      showAppNotice(t('تم حفظ الغلاف', 'Cover saved'));
    });
  }

  Future<void> _retry(RecordItem r) => _run(() async {
        final n = await _api.retry(r.id);
        if (n != null) _put([n]);
      });

  Future<void> _delete(List<RecordItem> rs) async {
    final onDrive = rs.any((r) => r.remoteUrl != null);
    final c = context.colors;
    final how = await showAppSheet<String>(context, (ctx) => AppSheetContent(tone: AppTone.danger, icon: Icons.delete_outline_rounded, 
          title: rs.length == 1 ? t('حذف «${rs.first.title}»؟', 'Delete “${rs.first.title}”?') : t('حذف ${recordsCountText(rs.length)}؟', 'Delete ${recordsCountText(rs.length)}?'),
          children: [
            Text(
              onDrive
                  ? t('اختر ما يُحذف. حذف الملف من السحابة يرسله إلى سلة المهملات فيها.', 'Choose what goes. Deleting from the drive moves the file to its bin.')
                  : t('يُحذف من القائمة.', 'It is removed from the list.'),
              style: AppType.body(context).copyWith(color: c.textMedium),
            ),
            const SizedBox(height: AppSpace.sm),
            if (onDrive) ...[
              AppButton(
                key: const ValueKey('records.delete.drive'),
                label: t('من القائمة ومن السحابة', 'From the list and the drive'),
                icon: Icons.delete_forever_rounded,
                variant: AppButtonVariant.danger,
                expand: true,
                onPressed: () => Navigator.of(ctx).pop('drive'),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
            AppButton(
              key: const ValueKey('records.delete.list'),
              label: onDrive ? t('من القائمة فقط (يبقى الملف في السحابة)', 'From the list only (the file stays in the drive)') : t('حذف', 'Delete'),
              icon: Icons.playlist_remove_rounded,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop('list'),
            ),
          ],
        ));
    if (how == null || !mounted) return;
    final gone = <int>{};
    for (final r in rs) {
      try {
        await _api.delete(r.id, drive: how == 'drive');
        gone.add(r.id);
      } catch (e) {
        if (mounted) showAppNotice('${r.title}: ${recordsErrorText(e)}', error: true);
      }
    }
    if (!mounted) return;
    setState(() {
      _items = withoutRecords(_items, gone);
      _selected.removeAll(gone);
    });
    if (gone.isNotEmpty) showAppNotice(t('تم الحذف', 'Deleted'));
  }

  Future<void> _merge() async {
    final picked = [
      for (final id in _selected)
        ?_items.where((r) => r.id == id && r.mergeable).firstOrNull,
    ]..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));   // oldest first by default
    if (picked.length < 2) return;
    final made = await showAppSheet<List<RecordItem>>(context, (_) => _MergeSheet(items: picked, api: _api));
    if (!mounted || made == null) return;
    setState(_selected.clear);
    _put(made);
    showAppNotice(t('جارٍ الدمج — يظهر التسجيل الجديد أعلى القائمة', 'Merging — the new recording is at the top of the list'));
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    final mergeable = _items.where((r) => _selected.contains(r.id) && r.mergeable).length;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) setState(_selected.clear);
      },
      child: BasePage(
        key: const ValueKey('profile.records'),
        useWebCard: true,
        width: AppWidth.wide,
        appBar: ScreenAppBar(title: t('التسجيلات', 'Records'), actions: [
          AppRefreshAction(onRefresh: () => _tab == 1 ? _loadShared() : _load()),
        ]),
        bottomNavigationBar: selecting
            ? RecordsSelectionBar(
                count: _selected.length,
                canMerge: mergeable >= 2 && mergeable == _selected.length && mergeable <= recordMaxMerge,
                onMerge: _merge,
                onDelete: () => _delete([for (final r in _items) if (_selected.contains(r.id)) r]),
                onCancel: () => setState(_selected.clear),
              )
            : null,
        child: Column(children: [
          if (_sharing && !selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              child: AppTabs(
                key: const ValueKey('records.tabs'),
                expand: true,
                index: _tab,
                items: [
                  AppTabItem(t('تسجيلاتي', 'My recordings'), icon: Icons.video_library_outlined,
                      count: _items.isEmpty ? null : _items.length),
                  AppTabItem(t('مُشارَكة معي', 'Shared with me'), icon: Icons.folder_shared_outlined,
                      count: _shared.isEmpty ? null : _shared.length),
                ],
                onChanged: (i) {
                  setState(() => _tab = i);
                  if (i == 1 && !_sharedLoaded) _loadShared();
                },
              ),
            ),
          Expanded(
            child: _tab == 1 && _sharing
                ? AppRefresh(
                    onRefresh: () => _loadShared(silent: true),
                    child: SharedRecordsLayout(
                      items: _shared,
                      loading: _sharedLoading || !_sharedLoaded,
                      error: _sharedError,
                      onReload: _loadShared,
                      onTap: (r) => openSharedRecord(context, r, api: _shareApi),
                    ),
                  )
                : AppRefresh(
          onRefresh: () => _load(silent: true),
          child: RecordsLayout(
            items: _items,
            loading: _loading,
            error: _error,
            selected: _selected,
            highlightId: widget.highlightId,
            onTap: _tap,
            onLongPress: (r) {
              if (r.inProgress) return;
              _toggle(r);
            },
            onMore: _more,
            onRetry: _retry,
            onReload: _load,
          ),
        ),
          ),
        ]),
      ),
    );
  }
}

/// Rename: the field + Save (its own State, so the controller outlives the closing animation).
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial});
  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(title: t('تغيير الاسم', 'Rename'), children: [
        TextField(
          key: const ValueKey('records.rename.field'),
          controller: _ctl,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: t('اسم التسجيل', 'Recording name')),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        const SizedBox(height: AppSpace.sm),
        AppButton.primary(
          key: const ValueKey('records.rename.save'),
          label: t('حفظ', 'Save'),
          expand: true,
          onPressed: () => Navigator.of(context).pop(_ctl.text),
        ),
      ]);
}

/// Merge: the order, the name, "delete the originals", Merge → the new item(s).
class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.items, required this.api});
  final List<RecordItem> items;
  final RecordsApi api;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  late List<RecordItem> _order = widget.items;
  late final TextEditingController _title = TextEditingController(text: defaultEditTitle(widget.items.first.title, RecordOp.merge));
  bool _deleteSources = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final out = await widget.api.merge([for (final r in _order) r.id], title: _title.text, deleteSources: _deleteSources);
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(recordsErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      AppSheetContent(title: t('دمج ${recordsCountText(_order.length)}', 'Merge ${recordsCountText(_order.length)}'), children: [
        MergeOrderLayout(
          items: _order,
          busy: _busy,
          deleteSources: _deleteSources,
          title: TextField(
            key: const ValueKey('records.merge.title'),
            controller: _title,
            maxLength: 120,
            decoration: InputDecoration(labelText: t('اسم التسجيل الجديد', 'Name of the new recording')),
          ),
          onMove: (i, by) => setState(() {
            final next = [..._order];
            final x = next.removeAt(i);
            next.insert(i + by, x);
            _order = next;
          }),
          onDeleteSources: (v) => setState(() => _deleteSources = v),
          onMerge: _go,
        ),
      ]);
}
