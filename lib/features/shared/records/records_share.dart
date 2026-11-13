// lib/features/shared/records/records_share.dart — Records (D-312): watching a record the way a student watches a
// lesson, and sharing it. Pure parts: records_share_api.dart; plain values: records_share_parts.dart.
//
//   RecordPlayerPage           the course video player (VideoPlayerScreen, the one player of the app) on a record's
//                              signed stream, with the caller's top-bar buttons (Open in Studio · Share)
//   showRecordShareSheet       who may watch (Only people I choose · Anyone with the link), the chosen people (+ the
//                              picker), the link with Copy / Share via, Save, Stop sharing — kill switch records.share;
//                              Guests by e-mail (D-315): people without an account, a personal link each (Guest badge,
//                              Copy link, Resend, Revoke), records_guests_api.dart / records_guests_parts.dart
//   SharedRecordPage(token)    where /s/record/<token> and the `records_shared` notification land: the player, or
//                              "not available" (the server answers 404 to anyone not allowed)
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../admin/admin_common.dart' show t;
import '../session/video/video_player_screen.dart';
import '../session/video/vod_player_parts.dart' show VodAction, VodPlayerSkeleton;
import 'records_api.dart';
import 'records_guests_api.dart';
import 'records_guests_parts.dart';
import 'records_share_api.dart';
import 'records_share_parts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Player
// ─────────────────────────────────────────────────────────────────────────────

/// The app's course player on a record: asks for the signed stream ([play]), then plays it with [actions] on the
/// top bar. A failed [play] shows the reason and a way back.
class RecordPlayerPage extends StatefulWidget {
  const RecordPlayerPage({super.key, required this.title, required this.play, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final Future<RecordPlay> Function() play;
  final List<VodAction> actions;

  @override
  State<RecordPlayerPage> createState() => _RecordPlayerPageState();
}

class _RecordPlayerPageState extends State<RecordPlayerPage> {
  RecordPlay? _play;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.play();
      if (mounted) setState(() => _play = p);
    } catch (e) {
      if (mounted) setState(() => _error = recordsErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _play;
    if (p != null) {
      return VideoPlayerScreen.fromLegacy(
        key: const ValueKey('records.player'),
        qualities: [(label: '720', url: p.url)],
        title: widget.title,
        subtitle: widget.subtitle,
        audioUrl: p.audio ? p.url : null,
        actions: widget.actions,
      );
    }
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.heroShade,
      body: _error == null
          ? VodPlayerSkeleton(title: widget.title, onBack: () => Navigator.maybePop(context))
          : SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.videocam_off_rounded, color: c.onHeroMuted, size: AppIconSize.hero),
                    const SizedBox(height: AppSpace.sm),
                    Text(_error!, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.onHero)),
                    const SizedBox(height: AppSpace.md),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.center, children: [
                      AppButton.secondary(label: t('رجوع', 'Back'), onPressed: () => Navigator.maybePop(context)),
                      AppButton.primary(
                          key: const ValueKey('records.player.retry'), label: t('إعادة المحاولة', 'Try again'), onPressed: _load),
                    ]),
                  ]),
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Share sheet
// ─────────────────────────────────────────────────────────────────────────────

/// The Share sheet of one of my records. Returns the share as saved (null when nothing was saved).
Future<RecordShare?> showRecordShareSheet(BuildContext context, RecordItem r, {RecordShareApi? api, RecordGuestsApi? guestsApi}) {
  if (AppConfig.disableList.contains(kRecordsShareFeatureKey)) return Future.value();
  return showAppSheet<RecordShare>(context,
      (_) => _RecordShareSheet(item: r, api: api ?? RemoteRecordShareApi(), guestsApi: guestsApi ?? RemoteRecordGuestsApi()));
}

class _RecordShareSheet extends StatefulWidget {
  const _RecordShareSheet({required this.item, required this.api, required this.guestsApi});
  final RecordItem item;
  final RecordShareApi api;
  final RecordGuestsApi guestsApi;

  @override
  State<_RecordShareSheet> createState() => _RecordShareSheetState();
}

class _RecordShareSheetState extends State<_RecordShareSheet> {
  RecordShare? _saved;
  RecordShareMode _mode = RecordShareMode.people;
  List<RecordSharePerson> _people = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // guests by e-mail (D-315)
  List<RecordGuest> _guests = const [];
  final _guestEmails = TextEditingController();
  final _guestMessage = TextEditingController();
  int? _guestExpiry = 30;
  bool _guestBusy = false;
  bool _mailUnavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _guestEmails.dispose();
    _guestMessage.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.share(widget.item.id);
      if (!mounted) return;
      setState(() {
        _apply(s);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = recordsErrorText(e);
      });
    }
  }

  void _apply(RecordShare s) {
    _saved = s;
    _mode = s.active ? s.mode : RecordShareMode.people;
    _people = s.people;
    _guests = s.guests;
    _error = null;
  }

  // ── guests by e-mail (D-315) ──

  Future<void> _guestCall(Future<GuestInviteResult> Function() call, {bool clear = false}) async {
    setState(() => _guestBusy = true);
    try {
      final r = await call();
      if (!mounted) return;
      setState(() {
        _guestBusy = false;
        _guests = r.guests;
        _saved = r.share;
        _mailUnavailable = r.mail.unavailable;
        if (clear) {
          _guestEmails.clear();
          _guestMessage.clear();
        }
      });
      showAppNotice(r.mail.notice(), error: r.mail.status == 'failed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guestBusy = false);
      showAppNotice(recordGuestsErrorText(e), error: true);
    }
  }

  void _invite() {
    if (guestEmailsProblem(_guestEmails.text) != null) return;
    final emails = parseGuestEmails(_guestEmails.text).valid;
    _guestCall(() => widget.guestsApi.invite(widget.item.id, emails, message: _guestMessage.text, expiresDays: _guestExpiry),
        clear: true);
  }

  /// The record's ONE open guest link (D-842): made, or re-timed to the picked expiry, then copied.
  Future<void> _openLink() async {
    setState(() => _guestBusy = true);
    try {
      final r = await widget.guestsApi.openLink(widget.item.id, expiresDays: _guestExpiry);
      if (!mounted) return;
      setState(() {
        _guestBusy = false;
        _guests = r.guests;
        _saved = r.share;
      });
      final link = r.guests.where((g) => g.openLink).firstOrNull?.link;
      if (link != null) await Clipboard.setData(ClipboardData(text: link));
      showAppNotice(t('رابط الضيوف جاهز ونُسخ — من يفتحه يشاهد دون حساب', 'Guest link ready and copied — whoever opens it watches without an account'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _guestBusy = false);
      showAppNotice(recordGuestsErrorText(e), error: true);
    }
  }

  Future<void> _revokeGuest(RecordGuest g) async {
    if (!await appConfirm(context,
        message: g.openLink
            ? t('سيتوقف رابط الضيوف فوراً لكل من معه. متابعة؟', 'The guest link stops working at once for everyone who has it. Continue?')
            : t('سيتوقف رابط ${g.email} فوراً. متابعة؟', 'The link of ${g.email} stops working at once. Continue?'),
        danger: true,
        confirmLabel: t('إلغاء الرابط', 'Revoke'))) {
      return;
    }
    if (!mounted) return;
    await _guestCall(() => widget.guestsApi.revoke(widget.item.id, g.id));
  }

  Future<void> _copyGuest(RecordGuest g) async {
    final link = g.link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    showAppNotice(g.openLink ? t('تم نسخ رابط الضيوف', 'Guest link copied') : t('تم نسخ رابط ${g.email}', 'Link of ${g.email} copied'));
  }

  bool get _dirty {
    final s = _saved;
    if (s == null || !s.active) return true;
    if (s.mode != _mode) return true;
    final a = {for (final p in s.people) p.id}, b = {for (final p in _people) p.id};
    return a.length != b.length || !a.containsAll(b);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final s = await widget.api.setShare(widget.item.id, _mode, [for (final p in _people) p.id]);
      if (!mounted) return;
      final fresh = _people.where((p) => !(_saved?.people.any((o) => o.id == p.id) ?? false)).length;
      setState(() {
        _apply(s);
        _busy = false;
      });
      showAppNotice(fresh > 0
          ? t('تمت المشاركة — وصل إشعار لمن اخترتهم', 'Shared — the people you picked were notified')
          : t('تم حفظ المشاركة', 'Sharing saved'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = recordsErrorText(e);
      });
    }
  }

  Future<void> _stop() async {
    if (!await appConfirm(context,
        message: t('سيتوقف الرابط عن العمل ولن يشاهده أحد غيرك. متابعة؟', 'The link stops working and nobody but you can watch. Continue?'),
        danger: true,
        confirmLabel: t('إيقاف المشاركة', 'Stop sharing'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final s = await widget.api.stopShare(widget.item.id);
      if (!mounted) return;
      setState(() {
        _apply(s);
        _people = const [];
        _busy = false;
      });
      showAppNotice(t('أُوقفت المشاركة', 'Sharing stopped'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = recordsErrorText(e);
      });
    }
  }

  Future<void> _add() async {
    final picked = await showAppSheet<List<RecordSharePerson>>(
        context, (_) => _PeoplePickerSheet(recordId: widget.item.id, api: widget.api, chosen: _people));
    if (picked == null || !mounted) return;
    setState(() => _people = picked);
  }

  Future<void> _copy() async {
    final link = _saved?.link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    showAppNotice(t('تم نسخ الرابط', 'Link copied'));
  }

  Future<void> _systemShare() async {
    final link = _saved?.link;
    if (link == null) return;
    try {
      await SharePlus.instance.share(ShareParams(text: '${widget.item.title}\n$link', subject: widget.item.title));
    } catch (_) {
      await _copy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _saved;
    return AppSheetContent(tone: AppTone.brand, icon: Icons.share_rounded, 
      title: t('مشاركة «${widget.item.title}»', 'Share “${widget.item.title}”'),
      children: [
        if (_loading)
          const AppListSkeleton(items: 3)
        else
          RecordShareLayout(
            mode: _mode,
            people: _people,
            link: s?.active == true ? s!.link : null,
            active: s?.active ?? false,
            views: s?.views ?? 0,
            busy: _busy,
            dirty: _dirty,
            error: _error,
            onMode: (m) => setState(() => _mode = m),
            onAdd: _add,
            onRemove: (p) => setState(() => _people = [for (final x in _people) if (x.id != p.id) x]),
            onCopy: _copy,
            onSystemShare: kIsWeb ? null : _systemShare,
            onSave: _save,
            onStop: _stop,
            guestRows: [
              for (final g in _guests)
                RecordGuestRow(
                  guest: g,
                  busy: _guestBusy,
                  onCopy: () => _copyGuest(g),
                  onResend: () => _guestCall(() => widget.guestsApi.resend(widget.item.id, g.id)),
                  onRevoke: () => _revokeGuest(g),
                ),
            ],
          ),
        if (!_loading) ...[
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),
          ListenableBuilder(
            listenable: _guestEmails,
            builder: (context, _) {
              final typed = _guestEmails.text.trim().isNotEmpty;
              return RecordGuestsInvite(
                emails: TextField(
                  key: const ValueKey('records.share.guests.emails'),
                  controller: _guestEmails,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t('عناوين البريد', 'E-mail addresses'),
                    hintText: 'name@example.com, …',
                    helperText: t('افصل بين العناوين بفاصلة', 'Separate addresses with a comma'),
                  ),
                ),
                message: TextField(
                  key: const ValueKey('records.share.guests.message'),
                  controller: _guestMessage,
                  maxLength: recordGuestMessageMax,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: t('رسالة (اختياري)', 'Message (optional)')),
                ),
                expiresDays: _guestExpiry,
                problem: typed ? guestEmailsProblem(_guestEmails.text) : null,
                busy: _guestBusy,
                mailUnavailable: _mailUnavailable,
                onExpiry: (d) => setState(() => _guestExpiry = d),
                onInvite: typed ? _invite : null,
                hasOpenLink: _guests.any((g) => g.openLink),
                onOpenLink: _openLink,
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Search and pick people (the calendar invitee picker's people half, on the record's own reach: the people I know
/// by name, anyone by their exact @username). Returns the new list.
class _PeoplePickerSheet extends StatefulWidget {
  const _PeoplePickerSheet({required this.recordId, required this.api, required this.chosen});
  final int recordId;
  final RecordShareApi api;
  final List<RecordSharePerson> chosen;

  @override
  State<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends State<_PeoplePickerSheet> {
  late final Map<int, RecordSharePerson> _chosen = {for (final p in widget.chosen) p.id: p};
  final _q = TextEditingController();
  List<RecordSharePerson> _results = const [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await widget.api.people(widget.recordId, q: _q.text);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = recordsErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // the chosen ones first, so they can be taken off without searching for them again
    final ids = {for (final p in _results) p.id};
    final shown = [
      if (_q.text.trim().isEmpty)
        for (final p in _chosen.values)
          if (!ids.contains(p.id)) p,
      ..._results,
    ];
    return AppSheetContent(
      title: t('إضافة أشخاص', 'Add people'),
      children: [
        SharePeopleLayout(
          search: TextField(
            key: const ValueKey('records.share.people.search'),
            controller: _q,
            autofocus: true,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t('ابحث بالاسم أو @اسم المستخدم', 'Search by name or @username'),
            ),
          ),
          results: shown,
          chosen: _chosen.keys.toSet(),
          loading: _loading,
          error: _error,
          query: _q.text,
          onToggle: (p) => setState(() => _chosen.containsKey(p.id) ? _chosen.remove(p.id) : _chosen[p.id] = p),
          onDone: () => Navigator.of(context).pop(_chosen.values.toList()),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A shared record (link / notification / Shared with me)
// ─────────────────────────────────────────────────────────────────────────────

/// Opens [r] in the player (a viewer: no Studio, no Share).
Future<void> openSharedRecord(BuildContext context, SharedRecord r, {RecordShareApi? api}) {
  final a = api ?? RemoteRecordShareApi();
  return Navigator.of(context).push(MaterialPageRoute(
    settings: const RouteSettings(name: '/records/shared'),
    builder: (_) => RecordPlayerPage(
      title: r.title,
      subtitle: r.ownerName.isEmpty ? null : t('شاركه ${r.ownerName}', 'Shared by ${r.ownerName}'),
      play: () => a.playShared(r.token),
    ),
  ));
}

/// `/s/record/<token>` signed in, and the `records_shared` notification: the record's player, or "not available".
class SharedRecordPage extends StatefulWidget {
  const SharedRecordPage({super.key, required this.token, this.api});
  final String token;
  final RecordShareApi? api;

  @override
  State<SharedRecordPage> createState() => _SharedRecordPageState();
}

class _SharedRecordPageState extends State<SharedRecordPage> {
  late final RecordShareApi _api = widget.api ?? RemoteRecordShareApi();
  SharedRecord? _item;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = widget.token.isEmpty ? null : await _api.shared(widget.token);
      if (!mounted) return;
      setState(() {
        _item = r;
        if (r == null) _error = t('هذا التسجيل غير متاح لك', 'This recording is not available to you');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = sharedRecordErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _item;
    if (r != null) {
      return RecordPlayerPage(
        title: r.title,
        subtitle: r.ownerName.isEmpty ? null : t('شاركه ${r.ownerName}', 'Shared by ${r.ownerName}'),
        play: () => _api.playShared(r.token),
      );
    }
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: t('تسجيل', 'Recording'), showBack: Navigator.of(context).canPop()),
      body: _error == null
          ? const AppListSkeleton(items: 2)
          : AppEmpty(
              icon: Icons.lock_outline_rounded,
              title: t('غير متاح', 'Not available'),
              message: _error,
              actionLabel: t('إعادة المحاولة', 'Try again'),
              onAction: _load,
            ),
    );
  }
}

/// A record the person may not watch answers 404: "not available to you" rather than "not there any more".
String sharedRecordErrorText(Object e) {
  final ex = ApiException.from(e);
  if (ex.code == 'record_not_found' || ex.statusCode == 404) {
    return t('هذا التسجيل غير متاح لك — اطلب من صاحبه مشاركته معك', 'This recording is not available to you — ask its owner to share it with you');
  }
  return recordsErrorText(e);
}
