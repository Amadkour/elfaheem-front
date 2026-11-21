// lib/features/games/admin/games_admin_page.dart — SUPER ADMIN: the educational games editor (Learning Hub v2 §3,
// D-1589..D-1591), kill switch `admin.games`, opened from the services hub next to the grammar content.
//
//   GamesAdminPage      every game (any status) in its order: drag the handle to reorder (POST reorder), the switch
//                       is published ↔ hidden (CONTRACT C10), Edit / Delete in the row's menu; Add game
//   GameEditorPage      one game: the basics (titles, key, type, category, difficulty, level, theme, points, cover),
//                       a typed form per engine (game_config_draft.dart) and a live preview played by the engine
//                       itself inside the GameShell; Save as draft / Publish
//   GamesAdminListBody / GameEditorForm   the bodies over plain values and callbacks (test/ui/games_v2_layout_test.dart)
//
// The engines offered are the server's (`/admin/games/engines`) that this app can edit; an older server without
// that route gets the app's own list.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/game_config_draft.dart';
import 'package:flutter_education_app/features/games/admin/games_admin_api.dart';
import 'package:flutter_education_app/features/games/engines/game_engine.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/games/shell/game_round.dart';
import 'package:flutter_education_app/features/games/shell/game_shell.dart';
import 'package:image_picker/image_picker.dart';

String gameStatusName(String s) => switch (s) {
      'published' => t('منشورة', 'Published'),
      'hidden' => t('مخفية', 'Hidden'),
      _ => t('مسودة', 'Draft'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The list
// ═════════════════════════════════════════════════════════════════════════════

class GamesAdminPage extends StatefulWidget {
  const GamesAdminPage({super.key, this.api});

  final GamesAdminApi? api;

  @override
  State<GamesAdminPage> createState() => _GamesAdminPageState();
}

class _GamesAdminPageState extends State<GamesAdminPage> {
  late final GamesAdminApi _api = widget.api ?? GamesAdminApi();
  List<GameSummary>? _games;
  List<GameAdminEngine>? _engines;
  String? _error;
  DateTime? _loadedAt;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _api.engines().then((e) {
      if (mounted) setState(() => _engines = e);
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final g = await _api.games();
      if (!mounted) return;
      setState(() {
        _games = g;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = gamesAdminErrorText(e));
    }
  }

  Future<void> _toggle(GameSummary g, bool on) async {
    setState(() => _busy.add(g.id));
    try {
      await _api.update(g.id, {'status': on ? 'published' : 'hidden'});
      showAppNotice(on ? t('نُشرت اللعبة', 'Game published') : t('أُخفيت اللعبة', 'Game hidden'));
      await _load();
    } catch (e) {
      showAppNotice(gamesAdminErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(g.id));
  }

  Future<void> _reorder(int from, int to) async {
    final list = [...?_games];
    if (to > from) to--;
    final g = list.removeAt(from);
    list.insert(to, g);
    setState(() => _games = list);
    try {
      await _api.reorder([for (final x in list) x.id]);
    } catch (e) {
      showAppNotice(gamesAdminErrorText(e), error: true);
      await _load();
    }
  }

  Future<void> _delete(GameSummary g) async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${g.title}»؟ لعبة لُعبت من قبل تُخفى بدل حذفها.',
            'Delete "${g.title}"? A game that has been played is hidden instead.'));
    if (!ok) return;
    try {
      final deleted = await _api.delete(g.id);
      showAppNotice(deleted ? t('حُذفت اللعبة', 'Game deleted') : t('لُعبت هذه اللعبة من قبل، فأُخفيت', 'This game has been played, so it was hidden'));
      await _load();
    } catch (e) {
      showAppNotice(gamesAdminErrorText(e), error: true);
    }
  }

  Future<void> _edit([GameSummary? g]) async {
    var full = g;
    if (g != null && g.config.isEmpty) {
      try {
        full = await _api.game(g.id);
      } catch (e) {
        showAppNotice(gamesAdminErrorText(e), error: true);
        return;
      }
    }
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: RouteSettings(name: g == null ? '/admin/games/new' : '/admin/games/${g.id}'),
      builder: (_) => GameEditorPage(initial: full, engines: _engines, api: _api),
    ));
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('الألعاب التعليمية', 'Educational games'),
      subtitle: t('الألعاب التي يراها الطلاب في تبويب الألعاب: محتواها وترتيبها ونشرها.',
          'The games students see in the Games tab: their content, order and publishing.'),
      icon: Icons.extension_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(
        key: const ValueKey('games.admin.add'),
        label: t('إضافة لعبة', 'Add game'),
        icon: Icons.add_rounded,
        onPressed: _games == null ? null : () => _edit(),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: GamesAdminListBody(
          games: _games,
          error: _error,
          busy: _busy,
          onRetry: _load,
          onToggle: _toggle,
          onEdit: _edit,
          onDelete: _delete,
          onReorder: _reorder,
        ),
      ),
    );
  }
}

/// The games over plain values: a reorderable list of rows.
class GamesAdminListBody extends StatelessWidget {
  const GamesAdminListBody({
    super.key,
    required this.games,
    this.error,
    this.busy = const {},
    this.onRetry,
    this.onToggle,
    this.onEdit,
    this.onDelete,
    this.onReorder,
  });

  /// Null: loading.
  final List<GameSummary>? games;
  final String? error;
  final Set<int> busy;
  final VoidCallback? onRetry;
  final void Function(GameSummary game, bool on)? onToggle;
  final ValueChanged<GameSummary>? onEdit, onDelete;
  final void Function(int from, int to)? onReorder;

  @override
  Widget build(BuildContext context) {
    final g = games;
    if (error != null && g == null) return AppErrorState(message: error, onRetry: onRetry);
    if (g == null) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    if (g.isEmpty) {
      return AppEmpty(
        icon: Icons.extension_rounded,
        title: t('لا ألعاب بعد', 'No games yet'),
        message: t('أضف لعبة واختر نوعها: ${kGameEngines.values.map((e) => e.nameAr).join('، ')}.',
            'Add a game and pick its type: ${kGameEngines.values.map((e) => e.nameEn).join(', ')}.'),
      );
    }
    return ReorderableListView.builder(
      key: const ValueKey('games.admin.list'),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      itemCount: g.length,
      onReorder: (a, b) => onReorder?.call(a, b),
      itemBuilder: (context, i) => Padding(
        key: ValueKey('games.admin.row.${g[i].id}'),
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: GameAdminRow(
          game: g[i],
          index: i,
          busy: busy.contains(g[i].id),
          onToggle: onToggle == null ? null : (v) => onToggle!(g[i], v),
          onEdit: onEdit == null ? null : () => onEdit!(g[i]),
          onDelete: onDelete == null ? null : () => onDelete!(g[i]),
        ),
      ),
    );
  }
}

class GameAdminRow extends StatelessWidget {
  const GameAdminRow({super.key, required this.game, required this.index, this.busy = false, this.onToggle, this.onEdit, this.onDelete});

  final GameSummary game;
  final int index;
  final bool busy;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      gameEngineName(game.engine),
      if (game.category.isNotEmpty) gameCategoryName(game.category),
      if (game.difficulty.isNotEmpty) gameDifficultyName(game.difficulty),
      if ((game.level ?? '').isNotEmpty) game.level!,
      gameStatusName(game.status),
    ].join(' · ');
    final well = gameThemeColors(context, game.theme);
    final cover = game.coverUrl;
    // a phone row (N13): the switch moves into the menu ("Publish" / "Hide"), so the title and its meta keep the room
    // (the meta already says the status)
    return AppCard(
      onTap: onEdit,
      child: LayoutBuilder(builder: (context, box) {
        final roomy = box.maxWidth >= 420;
        return Row(children: [
        ReorderableDragStartListener(
          index: index,
          child: Semantics(
            label: t('اسحب لتغيير الترتيب', 'Drag to reorder'),
            child: SizedBox(
              width: AppTouch.min,
              height: AppTouch.min,
              child: Icon(Icons.drag_indicator_rounded, color: c.textLight),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: AppRadius.chipAll,
          child: SizedBox(
            width: AppTouch.min,
            height: AppTouch.min,
            child: cover == null
                ? ColoredBox(color: well.surface, child: Icon(gameEngineIcon(game.engine), color: well.ink))
                : Image.network(cover,
                    fit: BoxFit.cover,
                    cacheWidth: (AppTouch.min * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, _, _) => ColoredBox(color: well.surface, child: Icon(gameEngineIcon(game.engine), color: well.ink))),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(game.title.isEmpty ? game.key : game.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: game.published ? null : c.textLight)),
            Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        if (roomy)
          AppSwitch(
            key: ValueKey('games.admin.toggle.${game.id}'),
            value: game.published,
            semanticLabel: t('منشورة', 'Published'),
            onChanged: busy ? null : onToggle,
          ),
        PopupMenuButton<String>(
          key: ValueKey('games.admin.menu.${game.id}'),
          tooltip: t('المزيد', 'More'),
          onSelected: (v) => switch (v) {
            'toggle' => onToggle?.call(!game.published),
            'edit' => onEdit?.call(),
            _ => onDelete?.call(),
          },
          itemBuilder: (_) => [
            if (!roomy)
              PopupMenuItem(
                value: 'toggle',
                enabled: onToggle != null && !busy,
                child: Text(game.published ? t('إخفاء عن الطلاب', 'Hide from students') : t('نشر', 'Publish')),
              ),
            PopupMenuItem(value: 'edit', enabled: onEdit != null, child: Text(t('تعديل', 'Edit'))),
            PopupMenuItem(value: 'delete', enabled: onDelete != null, child: Text(t('حذف', 'Delete'))),
          ],
        ),
      ]);
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The editor
// ═════════════════════════════════════════════════════════════════════════════

class GameEditorPage extends StatelessWidget {
  const GameEditorPage({super.key, this.initial, this.engines, required this.api});

  final GameSummary? initial;
  final List<GameAdminEngine>? engines;
  final GamesAdminApi api;

  @override
  Widget build(BuildContext context) {
    final g = initial;
    return AdminPage(
      width: AppWidth.wide,
      title: g == null ? t('لعبة جديدة', 'New game') : t('تعديل اللعبة', 'Edit game'),
      icon: Icons.extension_rounded,
      body: GameEditorForm(
          scrolls: true,
          padding: AdminPage.bodyPadding(context),
          initial: g,
          engines: engines,
          onSave: (body) async {
            try {
              if (g == null) {
                await api.create(body);
              } else {
                await api.update(g.id, body);
              }
            } catch (e) {
              return gamesAdminErrorText(e);
            }
            showAppNotice(body['status'] == 'published' ? t('نُشرت اللعبة', 'Game published') : t('حُفظت المسودة', 'Draft saved'));
            if (context.mounted) Navigator.of(context).pop(true);
            return null;
          },
          onUploadCover: g == null
              ? null
              : (bytes, name) async {
                  try {
                    return (url: await api.uploadCover(g.id, bytes, name), error: null);
                  } catch (e) {
                    return (url: null, error: gamesAdminErrorText(e));
                  }
                },
      ),
    );
  }
}

/// The engines the form offers: the server's that this app can edit (null = the app's own list), always under the
/// app's own names ([kGameEngines]), so the type menu, the lists and the student's filter call a type the same thing
/// (D-1673).
List<GameAdminEngine> gameEditorEngines(List<GameAdminEngine>? server) {
  GameAdminEngine named(String e) => (key: e, nameAr: kGameEngines[e]?.nameAr ?? e, nameEn: kGameEngines[e]?.nameEn ?? e);
  if (server == null || server.isEmpty) return [for (final e in kGameEngineForms.keys) named(e)];
  return [for (final s in server) if (kGameEngineForms.containsKey(s.key) && kGameEngines.containsKey(s.key)) named(s.key)];
}

class GameEditorForm extends StatefulWidget {
  const GameEditorForm({
    super.key,
    this.initial,
    this.engines,
    required this.onSave,
    this.onUploadCover,
    this.random,
    this.scrolls = false,
    this.padding = EdgeInsets.zero,
  });

  /// True: the form scrolls by itself inside a bounded box (the editor page), side by side with its preview on a
  /// wide window; false: a plain column for a parent that scrolls.
  final bool scrolls;

  /// The body padding when [scrolls].
  final EdgeInsets padding;

  final GameSummary? initial;
  final List<GameAdminEngine>? engines;

  /// Sends the body; returns the error text (null = saved).
  final Future<String?> Function(Map<String, dynamic> body) onSave;

  /// Null for a game not saved yet (the cover needs its id).
  final Future<({String? url, String? error})> Function(Uint8List bytes, String name)? onUploadCover;

  /// The preview's shuffle (tests pass a seeded one).
  final Random? random;

  @override
  State<GameEditorForm> createState() => _GameEditorFormState();
}

class _GameEditorFormState extends State<GameEditorForm> {
  late final GameSummary? _g = widget.initial;
  late final List<GameAdminEngine> _engines = gameEditorEngines(widget.engines);
  late String _engine = _g?.engine ?? (_engines.isEmpty ? 'quiz' : _engines.first.key);
  late GameConfigDraft _draft = _g == null ? GameConfigDraft.blank(_engine) : GameConfigDraft.fromConfig(_engine, _g.config);
  late final TextEditingController _titleAr = TextEditingController(text: _g?.titleAr ?? '');
  late final TextEditingController _titleEn = TextEditingController(text: _g?.titleEn ?? '');
  late final TextEditingController _key = TextEditingController(text: _g?.key ?? '');
  late final TextEditingController _level = TextEditingController(text: _g?.level ?? '');
  late final TextEditingController _points = TextEditingController(text: '${_g?.pointsReward ?? 0}');
  late String _category = (_g?.category ?? '').isEmpty ? 'general' : _g!.category;
  late String _difficulty = (_g?.difficulty ?? '').isEmpty ? 'easy' : _g!.difficulty;
  late String _theme = _g?.theme ?? 'sand';
  late String? _cover = _g?.coverUrl;
  bool _uploading = false;
  String? _saving;
  String? _error;

  /// The preview's config: follows the draft 400 ms after the last keystroke, so typing never replays a round.
  late Map<String, dynamic> _preview = _draft.toConfig();
  Timer? _debounce;
  int _previewRound = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_titleAr, _titleEn, _key, _level, _points]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _preview = _draft.toConfig());
    });
    setState(() {});
  }

  void _setEngine(String e) {
    if (e == _engine) return;
    setState(() {
      _engine = e;
      _draft = GameConfigDraft.blank(e);
      _preview = _draft.toConfig();
    });
  }

  Future<void> _pickCover() async {
    final upload = widget.onUploadCover;
    if (upload == null) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final img = await cropImageWithName(context, bytes, x.name, shape: CropShape.wide);
      if (img == null || !mounted) return;
      setState(() => _uploading = true);
      final r = await upload(img.bytes, img.name);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        if (r.url != null) _cover = r.url;
      });
      if (r.error != null) showAppNotice(r.error!, error: true);
    } catch (e) {
      if (mounted) setState(() => _uploading = false);
      showAppNotice(t('تعذّر رفع الصورة', 'The image could not be uploaded'), error: true);
    }
  }

  String get _keyValue {
    final k = _key.text.trim();
    if (k.isNotEmpty) return k;
    return 'game-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  }

  Future<void> _save(String status) async {
    setState(() {
      _saving = status;
      _error = null;
    });
    final err = await widget.onSave(gameAdminBody(
      key: _keyValue,
      engine: _engine,
      titleAr: _titleAr.text,
      titleEn: _titleEn.text,
      config: _draft.toConfig(),
      category: _category,
      difficulty: _difficulty,
      theme: _theme,
      level: _level.text,
      pointsReward: int.tryParse(_points.text.trim()) ?? 0,
      coverUrl: _cover,
      status: status,
    ));
    if (!mounted) return;
    setState(() {
      _saving = null;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final form = kGameEngineForms[_engine];
    final problems = _draft.problems();
    final titled = _titleAr.text.trim().isNotEmpty || _titleEn.text.trim().isNotEmpty;
    final canSave = problems.isEmpty && titled && _saving == null;
    final spec = gameEngine(_engine);
    final preview = <Widget>[
      Row(children: [
        Expanded(child: AppSectionTitle(t('معاينة مباشرة', 'Live preview'))),
        IconButton(
          key: const ValueKey('games.edit.replay'),
          tooltip: t('ابدأ المعاينة من جديد', 'Restart the preview'),
          icon: const Icon(Icons.replay_rounded),
          onPressed: () => setState(() => _previewRound++),
        ),
      ]),
      AppCard(
        key: const ValueKey('games.edit.preview'),
        child: spec == null
            ? Text(t('لا معاينة لهذا النوع', 'No preview for this type'), style: AppType.meta(context))
            : GameRound(
                key: ValueKey('preview.$_previewRound.${jsonEncode(_preview)}.$_theme'),
                spec: spec,
                config: _preview,
                theme: _theme,
                showMute: false,
                random: widget.random,
                onFinished: (_, _) => setState(() => _previewRound++),
              ),
      ),
    ];
    final fields = <Widget>[
      // ── basics
      AppSectionTitle(t('الأساسيات', 'Basics')),
      AppField(key: const ValueKey('games.edit.titleAr'), controller: _titleAr, label: t('العنوان بالعربية', 'Title in Arabic'), onChanged: (_) => setState(() {})),
      AppField(key: const ValueKey('games.edit.titleEn'), controller: _titleEn, label: t('العنوان بالإنجليزية', 'Title in English'), onChanged: (_) => setState(() {})),
      if (_g == null)
        AppField(
          key: const ValueKey('games.edit.key'),
          controller: _key,
          label: t('المعرّف', 'Key'),
          hint: 'planets-order',
          ltr: true,
          helper: t('اختياري: حروف إنجليزية صغيرة وأرقام وشرطات', 'Optional: lower-case letters, digits and dashes'),
        ),
      AppDropdown<String>(
        key: const ValueKey('games.edit.engine'),
        decoration: InputDecoration(labelText: t('نوع اللعبة', 'Game type')),
        value: _engine,
        enabled: _g == null,
        items: [
          for (final e in _engines)
            DropdownMenuItem(value: e.key, child: Text(t(e.nameAr.isEmpty ? e.key : e.nameAr, e.nameEn.isEmpty ? e.key : e.nameEn))),
          if (!_engines.any((e) => e.key == _engine)) DropdownMenuItem(value: _engine, child: Text(gameEngineName(_engine))),
        ],
        onChanged: (v) {
          if (v != null) _setEngine(v);
        },
      ),
      const SizedBox(height: AppSpace.sm),
      _Pair(
        a: AppDropdown<String>(
          key: const ValueKey('games.edit.category'),
          decoration: InputDecoration(labelText: t('التصنيف', 'Category')),
          value: _category,
          items: [for (final k in kGameCategories) DropdownMenuItem(value: k, child: Text(gameCategoryName(k), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        b: AppDropdown<String>(
          key: const ValueKey('games.edit.difficulty'),
          decoration: InputDecoration(labelText: t('الصعوبة', 'Difficulty')),
          value: _difficulty,
          items: [for (final k in kGameDifficulties) DropdownMenuItem(value: k, child: Text(gameDifficultyName(k), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _difficulty = v ?? _difficulty),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      _Pair(
        a: AppDropdown<String>(
          key: const ValueKey('games.edit.theme'),
          decoration: InputDecoration(labelText: t('المظهر', 'Theme')),
          value: kGameThemes.contains(_theme) ? _theme : 'sand',
          items: [for (final k in kGameThemes) DropdownMenuItem(value: k, child: Text(gameThemeName(k), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _theme = v ?? _theme),
        ),
        b: AppField(controller: _level, label: t('المستوى (اختياري)', 'Level (optional)'), hint: t('مثلاً: الصف الثالث', 'e.g. Grade 3')),
      ),
      AppField(controller: _points, label: t('نقاط الجولة', 'Points per round'), keyboard: TextInputType.number, ltr: true),
      _CoverRow(url: _cover, uploading: _uploading, onPick: widget.onUploadCover == null ? null : _pickCover),
      const SizedBox(height: AppSpace.lg),

      // ── content
      AppSectionTitle(t('المحتوى', 'Content')),
      if (form == null)
        AppBanner(
            icon: Icons.system_update_rounded,
            color: c.warning,
            text: t('هذا النوع لا يمكن تعديله في هذا الإصدار.', 'This app version cannot edit this game type.'))
      else ...[
        if (form.prompt) ...[
          _DraftField(id: 'prompt_ar.$_engine', label: t('التعليمات بالعربية', 'Instructions in Arabic'), value: _draft.promptAr, onChanged: (v) {
            _draft.promptAr = v;
            _changed();
          }),
          _DraftField(id: 'prompt_en.$_engine', label: t('التعليمات بالإنجليزية', 'Instructions in English'), value: _draft.promptEn, onChanged: (v) {
            _draft.promptEn = v;
            _changed();
          }),
        ],
        if (form.shuffle)
          AppSwitchTile(
            title: t('اخلط ترتيب الأسئلة', 'Shuffle the questions'),
            value: _draft.shuffle,
            onChanged: (v) {
              _draft.shuffle = v;
              _changed();
            },
          ),
        for (var i = 0; i < _draft.rows.length; i++) ...[
          GameDraftRowCard(
            key: ValueKey('games.edit.row.${_draft.rows[i]['_id']}'),
            form: form,
            index: i,
            row: _draft.rows[i],
            problems: _draft.rowProblems(_draft.rows[i]),
            onChanged: _changed,
            onRemove: _draft.rows.length <= 1
                ? null
                : () {
                    _draft.rows.removeAt(i);
                    _changed();
                  },
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_draft.rows.length < form.maxRows)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              key: const ValueKey('games.edit.addRow'),
              label: t('إضافة ${form.rowAr}', 'Add ${form.rowEn.toLowerCase()}'),
              icon: Icons.add_rounded,
              onPressed: () {
                _draft.addRow();
                _changed();
              },
            ),
          ),
      ],
      const SizedBox(height: AppSpace.lg),
    ];
    final save = <Widget>[
      // ── save
      if (problems.isNotEmpty || !titled)
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: [
            if (!titled) t('اكتب عنوان اللعبة.', 'Write the game\'s title.'),
            for (final p in problems.take(4)) p.message,
          ].join('\n'),
        ),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(_error!, style: AppType.meta(context).copyWith(color: c.danger)),
      ],
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, alignment: WrapAlignment.end, children: [
        AppButton.secondary(
          key: const ValueKey('games.edit.draft'),
          label: t('حفظ كمسودة', 'Save as draft'),
          busy: _saving == 'draft',
          onPressed: canSave ? () => _save('draft') : null,
        ),
        AppButton.primary(
          key: const ValueKey('games.edit.publish'),
          label: t('نشر', 'Publish'),
          icon: Icons.publish_rounded,
          busy: _saving == 'published',
          onPressed: canSave ? () => _save('published') : null,
        ),
      ]),
      const SizedBox(height: AppSpace.xl),
    ];
    Widget column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return LayoutBuilder(builder: (context, box) {
      final pad = widget.padding;
      // a wide window (D-1674): the fields at a form's width, the live preview beside them in its own scroll, so
      // it stays in view while the rows are typed
      if (widget.scrolls && box.hasBoundedHeight && box.maxWidth >= kGameEditorTwoPane) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max + pad.horizontal / 2),
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.only(start: pad.left, end: AppSpace.md, top: pad.top, bottom: pad.bottom),
              child: column([...fields, ...save]),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.only(start: AppSpace.md, end: pad.right, top: pad.top, bottom: pad.bottom),
              child: column(preview),
            ),
          ),
        ]);
      }
      final body = column([...fields, ...preview, const SizedBox(height: AppSpace.lg), ...save]);
      return widget.scrolls ? SingleChildScrollView(padding: pad, child: body) : body;
    });
  }
}

/// From this width the editor shows its live preview beside the fields rather than under them.
const double kGameEditorTwoPane = 960;

/// Two fields side by side on a wide box, stacked on a phone.
class _Pair extends StatelessWidget {
  const _Pair({required this.a, required this.b});

  final Widget a, b;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < 480
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: AppSpace.sm), b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: b),
              ]),
      );
}

class _CoverRow extends StatelessWidget {
  const _CoverRow({this.url, this.uploading = false, this.onPick});

  final String? url;
  final bool uploading;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = url;
    return Row(children: [
      ClipRRect(
        borderRadius: AppRadius.chipAll,
        child: SizedBox(
          width: AppTouch.primary * 2,
          height: AppTouch.primary,
          child: u == null
              ? ColoredBox(color: c.inputBg, child: Icon(Icons.image_outlined, color: c.textLight))
              : Image.network(u, fit: BoxFit.cover, cacheWidth: 240, errorBuilder: (_, _, _) => ColoredBox(color: c.inputBg)),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: onPick == null
            ? Text(t('احفظ اللعبة أولاً لإضافة غلاف.', 'Save the game first to add a cover.'), style: AppType.meta(context))
            : Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.secondary(
                  key: const ValueKey('games.edit.cover'),
                  label: u == null ? t('إضافة غلاف', 'Add cover') : t('تغيير الغلاف', 'Change cover'),
                  icon: Icons.image_rounded,
                  busy: uploading,
                  onPressed: onPick,
                ),
              ),
      ),
    ]);
  }
}

/// One row of the draft (a question, a pair, an item, a sentence, a word) with its typed fields.
class GameDraftRowCard extends StatelessWidget {
  const GameDraftRowCard({
    super.key,
    required this.form,
    required this.index,
    required this.row,
    required this.onChanged,
    this.onRemove,
    this.problems = const {},
  });

  final GameEngineForm form;
  final int index;
  final Map<String, dynamic> row;

  /// What is wrong with this row, by field key ([GameConfigDraft.rowProblems]). A field shows its mistake under itself
  /// once it holds text (D-1672); an empty field's "write the …" stays in the summary above Save, so a row being typed
  /// is not painted red field by field.
  final Map<String, String> problems;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final id = row['_id'];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(form.rowLabel(index), style: AppType.section(context))),
          IconButton(
            tooltip: t('حذف', 'Remove'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: onRemove,
          ),
        ]),
        for (final f in form.fields)
          switch (f.kind) {
            GameFieldKind.choices => _QuizChoices(
                row: row,
                label: f.label,
                help: f.help,
                error: problems['options'] ?? problems['answer'],
                onChanged: onChanged,
              ),
            GameFieldKind.lines => _DraftField(
                id: '$id.${f.key}',
                label: f.label,
                helper: f.help,
                error: _shown(f.key),
                maxLines: 4,
                value: [for (final o in (row[f.key] as List? ?? const [])) '$o'].join('\n'),
                onChanged: (v) {
                  row[f.key] = v.split('\n');
                  onChanged();
                },
              ),
            _ => _DraftField(
                id: '$id.${f.key}',
                label: f.label,
                helper: f.help,
                error: _shown(f.key),
                maxLines: f.kind == GameFieldKind.multiline ? 3 : 1,
                value: '${row[f.key] ?? ''}',
                onChanged: (v) {
                  row[f.key] = v;
                  onChanged();
                },
              ),
          },
      ]),
    );
  }
}

extension on GameDraftRowCard {
  /// [key]'s mistake when the field holds text (see [GameDraftRowCard.problems]).
  String? _shown(String key) {
    final v = row[key];
    final typed = v is List ? v.any((x) => '$x'.trim().isNotEmpty) : '${v ?? ''}'.trim().isNotEmpty;
    return typed ? problems[key] : null;
  }
}

/// The quiz's options: one field each, the right one marked with the check, add / remove (2..6).
class _QuizChoices extends StatelessWidget {
  const _QuizChoices({required this.row, required this.label, this.help, this.error, required this.onChanged});

  final Map<String, dynamic> row;
  final String label;
  final String? help, error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final opts = row['options'] as List<String>;
    final answer = row['answer'] is int ? row['answer'] as int : 0;
    final id = row['_id'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: AppType.label(context)),
      if (help != null) Text(help!, style: AppType.meta(context)),
      if (error != null && opts.any((o) => o.trim().isNotEmpty))
        Text(error!, style: AppType.meta(context).copyWith(color: c.danger)),
      const SizedBox(height: AppSpace.xs),
      for (var k = 0; k < opts.length; k++)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconButton(
            key: ValueKey('games.edit.answer.$id.$k'),
            tooltip: t('الإجابة الصحيحة', 'The right answer'),
            icon: Icon(k == answer ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: k == answer ? c.success : c.textLight),
            onPressed: () {
              row['answer'] = k;
              onChanged();
            },
          ),
          Expanded(
            child: _DraftField(
              id: '$id.opt.$k.${opts.length}',
              label: t('الخيار ${k + 1}', 'Option ${k + 1}'),
              value: opts[k],
              onChanged: (v) {
                opts[k] = v;
                onChanged();
              },
            ),
          ),
          IconButton(
            tooltip: t('حذف الخيار', 'Remove option'),
            icon: const Icon(Icons.close_rounded),
            onPressed: opts.length <= 2
                ? null
                : () {
                    opts.removeAt(k);
                    if (answer >= opts.length || answer == k) row['answer'] = 0;
                    if (answer > k) row['answer'] = answer - 1;
                    onChanged();
                  },
          ),
        ]),
      if (opts.length < 6)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(
            label: t('إضافة خيار', 'Add option'),
            icon: Icons.add_rounded,
            onPressed: () {
              opts.add('');
              onChanged();
            },
          ),
        ),
    ]);
  }
}

/// An AppField that owns its controller (the draft holds plain strings).
class _DraftField extends StatefulWidget {
  _DraftField({required this.id, required this.label, required this.value, required this.onChanged, this.helper, this.error, this.maxLines = 1})
      : super(key: ValueKey('games.edit.f.$id'));

  final String id, label, value;
  final String? helper, error;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppField(
        controller: _c,
        label: widget.label,
        helper: widget.helper,
        errorText: widget.error,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
      );
}
