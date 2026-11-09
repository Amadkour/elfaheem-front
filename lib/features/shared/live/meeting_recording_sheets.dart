// lib/features/shared/live/meeting_recording_sheets.dart — the screens of meeting recordings → cloud drives
// (docs/backend/live-rooms-spec.md §5 / §6). Pure parts: meeting_recording.dart.
//
//   showRecordSetupSheet(context, api:, kind:, id:)   the Record button of a meeting room: destination tiles
//                                                     (Google Drive / OneDrive, connect in place), quality,
//                                                     Start → RecordingStart (chunk_path for the recorder)
//   MeetingRecordingStatus(api:, meetingId:, …)       the meeting detail: the latest recording, polled while it
//                                                     is recording / assembling / uploading; Open in drive · Retry
//   CloudDrivesPage / CloudDrivesSettingsEntry        Settings → Connected drives (feature key profile.cloud_drives)
//
// Presentational widgets take plain values ([RecordSetupLayout], [RecordingStatusCard], [CloudDrivesLayout],
// [CloudDestinationTile]) — test/ui/meeting_recording_layout_test.dart pumps them with the layout harness.
// A provider the server has not set up (`configured: false`) is shown greyed with the "ask the platform admin" line
// and no Connect; a connect that still meets 503 `cloud_provider_unconfigured` shows that line as a notice and never
// opens a browser page (the consent page of an unconfigured client is the provider's own 400).
// Strings use t(ar, en).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../admin/admin_common.dart' show t;
import 'meeting_recording.dart';

/// Opens a link outside the app (the drive file, the OAuth page). False when nothing could open it.
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// How often GET /me/cloud is asked after the browser opened the auth page.
const cloudConnectPoll = Duration(seconds: 3);

/// The same wait while the live stream is connected (`job_updated{kind: cloud, id: provider}` ends it at once).
const cloudConnectPollLive = Duration(seconds: 20);

/// The poll gives up after this (the person closed the browser without finishing).
const cloudConnectTimeout = Duration(minutes: 5);

IconData cloudProviderIcon(CloudProvider p) => switch (p) {
      CloudProvider.googleDrive => Icons.add_to_drive_rounded,
      CloudProvider.onedrive => Icons.cloud_rounded,
    };

/// The second line of a provider tile.
String cloudAccountSubtitle(CloudAccount a) {
  if (!a.configured) return cloudUnconfiguredText(a.provider);
  if (!a.connected) return t('غير مرتبط', 'Not connected');
  return a.email ?? t('مرتبط', 'Connected');
}

// ─────────────────────────────────────────────────────────────────────────────
// Destination tile (plain values)
// ─────────────────────────────────────────────────────────────────────────────

class CloudDestinationTile extends StatelessWidget {
  const CloudDestinationTile({
    super.key,
    required this.account,
    this.selected = false,
    this.connecting = false,
    this.onTap,
    this.onConnect,
    this.onDisconnect,
  });

  final CloudAccount account;
  final bool selected;

  /// The auth page is open and GET /me/cloud is being polled.
  final bool connecting;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = account;
    final usable = a.usable;
    final tint = !a.configured ? c.textLight : (a.connected ? c.success : c.primary);
    // A small glyph sits in the row; a pill (Connect / Disconnect) moves under the text on a narrow phone,
    // where it would otherwise squeeze the name out of the row.
    Widget? glyph, pill;
    if (connecting) {
      glyph = SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary));
    } else if (a.configured && !a.connected && onConnect != null) {
      pill = AppPill(icon: Icons.link_rounded, label: t('ربط', 'Connect'), onTap: onConnect);
    } else if (a.connected && onDisconnect != null) {
      pill = AppPill(icon: Icons.link_off_rounded, label: t('فصل', 'Disconnect'), color: c.danger, onTap: onDisconnect);
    } else if (selected) {
      glyph = Icon(Icons.check_circle_rounded, color: c.primary);
    }
    return Semantics(
      selected: selected,
      child: InkWell(
        key: ValueKey('cloud.${a.provider.wire}'),
        borderRadius: BorderRadius.circular(16),
        onTap: usable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.07) : c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.5 : 1),
          ),
          child: LayoutBuilder(builder: (context, bc) {
            final pillBelow = pill != null && bc.maxWidth < 360;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(cloudProviderIcon(a.provider), color: tint, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(a.provider.label, style: appText(14, w: FontWeight.w700, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(cloudAccountSubtitle(a),
                        key: ValueKey('cloud.${a.provider.wire}.subtitle'),
                        style: appText(12, c: c.textMedium, h: 1.4),
                        maxLines: a.configured ? 2 : 3,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (glyph != null) ...[const SizedBox(width: 8), glyph],
                if (pill != null && !pillBelow) ...[const SizedBox(width: 8), pill],
              ]),
              if (pillBelow) ...[
                const SizedBox(height: 10),
                Align(alignment: AlignmentDirectional.centerEnd, child: pill),
              ],
            ]);
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record setup (sheet)
// ─────────────────────────────────────────────────────────────────────────────

/// The setup sheet's body from plain values.
class RecordSetupLayout extends StatelessWidget {
  const RecordSetupLayout({
    super.key,
    required this.accounts,
    required this.quality,
    this.selected,
    this.connecting,
    this.busy = false,
    this.error,
    this.onPick,
    this.onConnect,
    this.onQuality,
    this.onStart,
  });

  /// Null while GET /me/cloud loads.
  final List<CloudAccount>? accounts;
  final CloudProvider? selected;
  final CloudProvider? connecting;
  final RecordingQuality quality;
  final bool busy;
  final String? error;
  final ValueChanged<CloudProvider>? onPick;
  final ValueChanged<CloudProvider>? onConnect;
  final ValueChanged<RecordingQuality>? onQuality;
  final VoidCallback? onStart;

  bool get canStart {
    final list = accounts;
    if (list == null || selected == null || busy) return false;
    return list.any((a) => a.provider == selected && a.usable);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = accounts;
    final none = list != null && !list.any((a) => a.configured);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      // D-306: the choices scroll when the sheet is short (a phone held sideways); Start stays in view under them.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(t('تسجيل الاجتماع', 'Record the meeting')),
        Text(t('يُحفظ التسجيل في سحابتك أنت، لا على خوادم المنصة.', 'The recording is saved to your own drive, not on the platform.'),
            style: appText(12.5, c: c.textMedium, h: 1.5)),
        const SizedBox(height: 14),
        AppSectionTitle(t('الحفظ في', 'Save to')),
        const SizedBox(height: 8),
        if (list == null)
          const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
        else ...[
          for (final a in list) ...[
            CloudDestinationTile(
              account: a,
              selected: a.provider == selected,
              connecting: a.provider == connecting,
              onTap: onPick == null ? null : () => onPick!(a.provider),
              onConnect: onConnect == null || connecting != null ? null : () => onConnect!(a.provider),
            ),
            const SizedBox(height: 8),
          ],
          if (none)
            AppBanner(
              icon: Icons.cloud_off_rounded,
              color: c.warning,
              text: t('لم يُهيَّأ أي مزوّد سحابي على الخادم بعد. اطلب من مدير المنصة إعداد Google Drive أو OneDrive.',
                  'No cloud provider is set up on the server yet. Ask the platform admin to configure Google Drive or OneDrive.'),
            ),
          if (connecting != null)
            AppBanner(
              icon: Icons.open_in_browser_rounded,
              color: c.primary,
              text: t('أكمل تسجيل الدخول في المتصفح، وسنتابع هنا تلقائياً.', 'Finish signing in in the browser — this sheet follows automatically.'),
            ),
        ],
        const SizedBox(height: 10),
        RecordingQualityField(value: quality, onChanged: onQuality),
        const SizedBox(height: 12),
        RecordingIncludes(audioOnly: quality.audioOnly),
        if (error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          key: const ValueKey('record_setup.start'),
          label: t('ابدأ التسجيل', 'Start recording'),
          icon: Icons.fiber_manual_record_rounded,
          busy: busy,
          onPressed: canStart ? onStart : null,
        ),
      ]),
    );
  }
}

/// The recording quality, audio only to 2160p (D-319): the Record sheet and the new-meeting form.
class RecordingQualityField extends StatelessWidget {
  const RecordingQualityField({super.key, required this.value, this.onChanged, this.label});

  final RecordingQuality value;
  final ValueChanged<RecordingQuality>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<RecordingQuality>(
        value: value,
        decoration: InputDecoration(labelText: label ?? t('الجودة', 'Quality')),
        items: [for (final q in RecordingQuality.values) DropdownMenuItem(value: q, child: Text(q.label))],
        onChanged: onChanged == null ? null : (q) => onChanged!(q ?? RecordingQuality.p720),
      ),
      if (value.demanding) ...[
        const SizedBox(height: 6),
        Text(
          t('تحتاج جهازاً قوياً واتصالاً سريعاً، والملف كبير. لن تكون الصورة أوضح من الكاميرا أو الشاشة المعروضة.',
              'Needs a powerful device and a fast connection, and the file is large. The picture is only as sharp as the camera or screen being shown.'),
          style: appText(12, c: c.textMedium),
        ),
      ],
    ]);
  }
}

/// D-306: what the recording will hold, under the quality — the cameras that are on, every voice, the whiteboard and
/// shared screens composed into one video (live_recording_layout.dart); an audio-only recording holds the voices
/// alone. Plain values (test/ui/meeting_recording_layout_test.dart).
class RecordingIncludes extends StatelessWidget {
  const RecordingIncludes({super.key, this.audioOnly = false});

  final bool audioOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = <(IconData, String)>[
      if (!audioOnly) (Icons.videocam_rounded, t('الكاميرات المفتوحة', 'Cameras that are on')),
      (Icons.graphic_eq_rounded, t('كل الأصوات', 'Every voice')),
      if (!audioOnly) (Icons.draw_rounded, t('السبورة', 'The whiteboard')),
      if (!audioOnly) (Icons.screen_share_rounded, t('الشاشات المشاركة', 'Shared screens')),
    ];
    return Container(
      key: const ValueKey('record_setup.includes'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.primary.withValues(alpha: 0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('ما يتضمّنه التسجيل', 'What the recording holds'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final (icon, label) in items)
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.divider)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: c.primary),
                const SizedBox(width: 6),
                Flexible(child: Text(label, style: appText(12.5, w: FontWeight.w600, c: c.textDark))),
              ]),
            ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(
          audioOnly
              ? t('صوت فقط: ملف أصغر، بلا صورة.', 'Audio only: a smaller file, no picture.')
              : t('في فيديو واحد: ما يُعرض يملأ الإطار والكاميرات بجانبه، والكاميرات وحدها في شبكة.',
                  'One video: what is shown fills the frame with the cameras beside it; cameras alone sit in a grid.'),
          style: appText(12, c: c.textMedium, h: 1.45),
        ),
      ]),
    );
  }
}

/// Opens the setup sheet; resolves with the started recording, or null when the person backed out.
Future<RecordingStart?> showRecordSetupSheet(BuildContext context,
        {required String kind, required int id, MeetingRecordingApi? api, Future<RecordingQuality?> Function()? preferredQuality}) =>
    showAppSheet<RecordingStart>(context, (ctx) => RecordSetupSheet(kind: kind, id: id, api: api, preferredQuality: preferredQuality));

class RecordSetupSheet extends StatefulWidget {
  const RecordSetupSheet({super.key, required this.kind, required this.id, this.api, this.initialAccounts, this.preferredQuality});

  /// What the meeting's creator picked (D-319): the sheet opens on it unless the person has already chosen.
  final Future<RecordingQuality?> Function()? preferredQuality;

  final String kind;
  final int id;
  final MeetingRecordingApi? api;

  /// Skips the first GET /me/cloud (tests).
  final List<CloudAccount>? initialAccounts;

  @override
  State<RecordSetupSheet> createState() => _RecordSetupSheetState();
}

class _RecordSetupSheetState extends State<RecordSetupSheet> {
  late final MeetingRecordingApi _api = widget.api ?? RemoteMeetingRecordingApi();
  List<CloudAccount>? _accounts;
  CloudProvider? _selected, _connecting;
  RecordingQuality _quality = RecordingQuality.p720;
  bool _qualityTouched = false;
  bool _busy = false;
  String? _error;
  EventOrPoll? _poll;
  DateTime? _pollStarted;

  @override
  void initState() {
    super.initState();
    _loadPreferred();
    final initial = widget.initialAccounts;
    if (initial != null) {
      _accounts = initial;
      _selected = _firstUsable(initial);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  Future<void> _loadPreferred() async {
    try {
      final q = await widget.preferredQuality?.call();
      if (q != null && mounted && !_qualityTouched) setState(() => _quality = q);
    } catch (_) {
      // the default stays: the creator's choice is a convenience, never a reason not to record
    }
  }

  CloudProvider? _firstUsable(List<CloudAccount> list) {
    for (final a in list) {
      if (a.usable) return a.provider;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final list = await _api.cloud();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _selected ??= _firstUsable(list);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = meetingRecordingErrorText(e));
    }
  }

  Future<void> _connect(CloudProvider p) async {
    setState(() {
      _error = null;
      _connecting = p;
    });
    try {
      final url = await _api.connect(p);
      if (url.isEmpty || !await openExternalUrl(url)) {
        throw const ApiException(statusCode: 0, message: '', code: 'cloud_auth_failed');
      }
      _pollStarted = DateTime.now();
      _poll?.dispose();
      _poll = EventOrPoll(kind: 'cloud', id: p.wire, every: cloudConnectPoll, fallbackEvery: cloudConnectPollLive, poll: () => _tick(p))..start();
    } catch (e) {
      if (!mounted) return;
      if (isCloudUnconfigured(e)) {
        // older app state or a race (the keys were removed): say so, grey the tile, open nothing
        appToast(cloudUnconfiguredText(cloudProviderOfError(e) ?? p), error: true);
        setState(() {
          _connecting = null;
          _accounts = markCloudUnconfigured(_accounts, p);
          if (_selected == p) _selected = null;
        });
        return;
      }
      setState(() {
        _connecting = null;
        _error = meetingRecordingErrorText(e);
      });
    }
  }

  Future<void> _tick(CloudProvider p) async {
    if (!mounted) return _poll?.stop();
    final started = _pollStarted;
    if (started != null && DateTime.now().difference(started) > cloudConnectTimeout) {
      _poll?.stop();
      setState(() {
        _connecting = null;
        _error = t('انتهى وقت الربط، حاول مرة أخرى', 'Connecting timed out, try again');
      });
      return;
    }
    try {
      final list = await _api.cloud();
      if (!mounted) return;
      final done = list.any((a) => a.provider == p && a.usable);
      setState(() {
        _accounts = list;
        if (done) {
          _connecting = null;
          _selected = p;
        }
      });
      if (done) {
        _poll?.stop();
        appToast(t('تم ربط ${p.label}', '${p.label} connected'));
      }
    } catch (_) {
      // a failed poll is retried on the next tick
    }
  }

  Future<void> _start() async {
    final dest = _selected;
    if (dest == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.start(widget.kind, widget.id, quality: _quality, destination: dest);
      if (mounted) Navigator.pop(context, r.copyWith(quality: _quality, destination: dest));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = meetingRecordingErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => RecordSetupLayout(
        accounts: _accounts,
        selected: _selected,
        connecting: _connecting,
        quality: _quality,
        busy: _busy,
        error: _error,
        onPick: (p) => setState(() => _selected = p),
        onConnect: _connect,
        onQuality: (q) => setState(() {
          _quality = q;
          _qualityTouched = true;
        }),
        onStart: _start,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recording status (card)
// ─────────────────────────────────────────────────────────────────────────────

/// One recording's state from plain values: a dot / spinner, the status, its facts, Open in drive or Retry.
class RecordingStatusCard extends StatelessWidget {
  const RecordingStatusCard({super.key, required this.recording, this.onOpen, this.onRetry, this.busy = false});

  final MeetingRecording recording;
  final VoidCallback? onOpen;
  final VoidCallback? onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = recording;
    final color = r.isDone ? c.success : (r.isFailed ? c.danger : (r.isRecording ? c.danger : c.warning));
    final icon = r.isDone
        ? Icons.cloud_done_rounded
        : r.isFailed
            ? Icons.cloud_off_rounded
            : r.isRecording
                ? Icons.fiber_manual_record_rounded
                : Icons.cloud_upload_rounded;
    final facts = <String>[
      if (r.destination != null) r.destination!.label,
      r.quality.label.split(' — ').first,
      if (r.durationSeconds > 0) recordingDurationLabel(r.durationSeconds),
      if (r.size > 0) recordingSizeLabel(r.size),
      if (r.finishedAt != null)
        AppTime.dateTime(r.finishedAt!)
      else if (r.createdAt != null)
        AppTime.dateTime(r.createdAt!),
    ];
    return AppCard(
      key: ValueKey('recording.${r.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (r.inProgress && !r.isRecording)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t('تسجيل الاجتماع', 'Meeting recording'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 2),
              Text(facts.join(' · '), style: appText(12, c: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: AppBadgePill(recordingStatusLabel(r.status), color: color, icon: icon),
          ),
        ]),
        if (r.isFailed && (r.error ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r.error!, style: appText(12, c: c.danger, h: 1.4)),
        ],
        if (r.inProgress) ...[
          const SizedBox(height: 8),
          Text(
            r.isRecording
                ? t('يُرفع التسجيل أثناء الاجتماع، ويُجمَّع بعد انتهائه.', 'Uploads during the meeting and is assembled once it ends.')
                : t('سيصلك إشعار عندما يصبح الملف جاهزاً في سحابتك.', 'You get a notification once the file is in your drive.'),
            style: appText(12, c: c.textMedium, h: 1.4),
          ),
        ],
        if (r.canOpen && onOpen != null || r.isFailed && onRetry != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r.canOpen && onOpen != null)
              AppPill(key: const ValueKey('recording.open'), icon: Icons.open_in_new_rounded, label: t('فتح في السحابة', 'Open in drive'), onTap: busy ? null : onOpen),
            if (r.isFailed && onRetry != null)
              AppPill(key: const ValueKey('recording.retry'), icon: Icons.refresh_rounded, label: t('إعادة الرفع', 'Retry'), color: c.warning, onTap: busy ? null : onRetry),
          ]),
        ],
      ]),
    );
  }
}

/// How often an in-progress recording is re-read in the meeting detail (while the live stream is connected
/// [recordingStatusPollLive]: `job_updated{kind: recording, id}` re-reads at once then).
const recordingStatusPoll = Duration(seconds: 5);
const recordingStatusPollLive = Duration(seconds: 20);

/// The latest recording of a meeting, kept fresh: starts from [initial] (the detail's `recording`) or
/// GET /live/meeting/{id}/recordings, polls while in progress, Retry → POST …/retry, Open → the drive link.
/// Shows nothing when there is no recording. Bump [refreshKey] to reload (after the room closes).
class MeetingRecordingStatus extends StatefulWidget {
  const MeetingRecordingStatus({super.key, required this.meetingId, this.initial, this.api, this.refreshKey = 0, this.gap = 12});

  final int meetingId;
  final MeetingRecording? initial;
  final MeetingRecordingApi? api;
  final int refreshKey;
  final double gap;

  @override
  State<MeetingRecordingStatus> createState() => _MeetingRecordingStatusState();
}

class _MeetingRecordingStatusState extends State<MeetingRecordingStatus> {
  late final MeetingRecordingApi _api = widget.api ?? RemoteMeetingRecordingApi();
  MeetingRecording? _r;
  bool _busy = false;
  EventOrPoll? _poll;

  @override
  void initState() {
    super.initState();
    _r = widget.initial;
    if (_r == null) {
      _reload();
    } else {
      _schedule();
    }
  }

  @override
  void didUpdateWidget(covariant MeetingRecordingStatus old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _reload();
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  void _schedule() {
    final r = _r;
    if (r == null || !r.inProgress) {
      _poll?.stop();
      return;
    }
    if (_poll?.id != '${r.id}') {
      _poll?.dispose();
      _poll = EventOrPoll(kind: 'recording', id: '${r.id}', every: recordingStatusPoll, fallbackEvery: recordingStatusPollLive, poll: _refreshOne);
    }
    _poll!.start();
  }

  Future<void> _reload() async {
    try {
      final list = await _api.list('meeting', widget.meetingId);
      if (!mounted) return;
      setState(() => _r = list.isEmpty ? null : list.first);
      _schedule();
    } catch (_) {
      // optional card: a server without the route shows nothing
    }
  }

  Future<void> _refreshOne() async {
    final r = _r;
    if (r == null || !mounted) return;
    try {
      final n = await _api.get(r.id);
      if (!mounted) return;
      if (n != null) setState(() => _r = n);
    } catch (_) {
      // retried on the next tick
    }
    _schedule();
  }

  Future<void> _retry() async {
    final r = _r;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      final n = await _api.retry(r.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (n != null) _r = n;
      });
      _schedule();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      appToast(meetingRecordingErrorText(e), error: true);
    }
  }

  Future<void> _open() async {
    final url = _r?.remoteUrl;
    if (url == null) return;
    if (!await openExternalUrl(url)) appToast(t('تعذّر فتح الرابط', 'Could not open the link'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: widget.gap),
      child: RecordingStatusCard(recording: r, busy: _busy, onOpen: r.canOpen ? _open : null, onRetry: r.isFailed ? _retry : null),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings → Connected drives
// ─────────────────────────────────────────────────────────────────────────────

/// The page body from plain values.
class CloudDrivesLayout extends StatelessWidget {
  const CloudDrivesLayout({
    super.key,
    required this.accounts,
    this.loading = false,
    this.error,
    this.connecting,
    this.onConnect,
    this.onDisconnect,
    this.onRetry,
  });

  final List<CloudAccount> accounts;
  final bool loading;
  final String? error;
  final CloudProvider? connecting;
  final ValueChanged<CloudProvider>? onConnect;
  final ValueChanged<CloudProvider>? onDisconnect;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final none = !loading && accounts.isNotEmpty && !accounts.any((a) => a.configured);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      AppHero(
        title: t('السحابات المتصلة', 'Connected drives'),
        subtitle: t('تُحفظ تسجيلات اجتماعاتك في سحابتك أنت — في مجلد "NextBrain recordings".',
            'Your meeting recordings are saved to your own drive, in a "NextBrain recordings" folder.'),
        icon: Icons.cloud_sync_rounded,
      ),
      const SizedBox(height: 16),
      if (error != null) ...[
        AppBanner(
          icon: Icons.error_outline_rounded,
          color: c.danger,
          text: error!,
          action: onRetry == null ? null : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
        ),
        const SizedBox(height: 12),
      ],
      if (loading && accounts.isEmpty)
        const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
      else ...[
        for (final a in accounts) ...[
          CloudDestinationTile(
            account: a,
            connecting: a.provider == connecting,
            onConnect: onConnect == null || connecting != null ? null : () => onConnect!(a.provider),
            onDisconnect: onDisconnect == null ? null : () => onDisconnect!(a.provider),
          ),
          const SizedBox(height: 10),
        ],
        if (none)
          AppEmpty(
            icon: Icons.cloud_off_rounded,
            title: t('لا يوجد مزوّد مهيأ', 'No provider is set up'),
            message: t('لم يُضف مدير المنصة مفاتيح Google Drive أو OneDrive بعد.', 'The platform admin has not added Google Drive or OneDrive keys yet.'),
          ),
        if (connecting != null)
          AppBanner(
            icon: Icons.open_in_browser_rounded,
            color: c.primary,
            text: t('أكمل تسجيل الدخول في المتصفح، وسنتابع هنا تلقائياً.', 'Finish signing in in the browser — this page follows automatically.'),
          ),
      ],
      const SizedBox(height: 16),
      Text(
        t('المنصة تطلب صلاحية الملفات التي تنشئها هي فقط، ويمكنك فصل الحساب في أي وقت.',
            'The platform asks only for the files it creates itself; you can disconnect at any time.'),
        style: appText(12, c: c.textMedium, h: 1.5),
      ),
    ]);
  }
}

/// Settings → Connected drives. Feature key `profile.cloud_drives` (a "coming soon" page when off).
class CloudDrivesPage extends StatefulWidget {
  const CloudDrivesPage({super.key, this.api});
  final MeetingRecordingApi? api;

  @override
  State<CloudDrivesPage> createState() => _CloudDrivesPageState();
}

class _CloudDrivesPageState extends State<CloudDrivesPage> {
  late final MeetingRecordingApi _api = widget.api ?? RemoteMeetingRecordingApi();
  List<CloudAccount> _accounts = const [];
  bool _loading = true;
  String? _error;
  CloudProvider? _connecting;
  EventOrPoll? _poll;
  DateTime? _pollStarted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.cloud();
      if (mounted) {
        setState(() {
          _accounts = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = meetingRecordingErrorText(e);
        });
      }
    }
  }

  Future<void> _connect(CloudProvider p) async {
    setState(() {
      _error = null;
      _connecting = p;
    });
    try {
      final url = await _api.connect(p);
      if (url.isEmpty || !await openExternalUrl(url)) {
        throw const ApiException(statusCode: 0, message: '', code: 'cloud_auth_failed');
      }
      _pollStarted = DateTime.now();
      _poll?.dispose();
      _poll = EventOrPoll(kind: 'cloud', id: p.wire, every: cloudConnectPoll, fallbackEvery: cloudConnectPollLive, poll: () => _tick(p))..start();
    } catch (e) {
      if (!mounted) return;
      if (isCloudUnconfigured(e)) {
        appToast(cloudUnconfiguredText(cloudProviderOfError(e) ?? p), error: true);
        setState(() {
          _connecting = null;
          _accounts = markCloudUnconfigured(_accounts, p) ?? _accounts;
        });
        return;
      }
      setState(() {
        _connecting = null;
        _error = meetingRecordingErrorText(e);
      });
    }
  }

  Future<void> _tick(CloudProvider p) async {
    if (!mounted) return _poll?.stop();
    final started = _pollStarted;
    if (started != null && DateTime.now().difference(started) > cloudConnectTimeout) {
      _poll?.stop();
      setState(() {
        _connecting = null;
        _error = t('انتهى وقت الربط، حاول مرة أخرى', 'Connecting timed out, try again');
      });
      return;
    }
    try {
      final list = await _api.cloud();
      if (!mounted) return;
      final done = list.any((a) => a.provider == p && a.usable);
      setState(() {
        _accounts = list;
        if (done) _connecting = null;
      });
      if (done) {
        _poll?.stop();
        appToast(t('تم ربط ${p.label}', '${p.label} connected'));
      }
    } catch (_) {
      // retried on the next tick
    }
  }

  Future<void> _disconnect(CloudProvider p) async {
    final ok = await appConfirm(context,
        message: t('فصل ${p.label}؟ التسجيلات المحفوظة تبقى في سحابتك.', 'Disconnect ${p.label}? Saved recordings stay in your drive.'),
        danger: true,
        confirmLabel: t('فصل', 'Disconnect'));
    if (!ok || !mounted) return;
    try {
      await _api.disconnect(p);
      if (!mounted) return;
      setState(() => _accounts = [for (final a in _accounts) a.provider == p ? a.copyWith(connected: false, email: '') : a]);
      appToast(t('تم الفصل', 'Disconnected'));
    } catch (e) {
      appToast(meetingRecordingErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey('profile.cloud_drives'),
        useWebCard: true,
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: t('السحابات المتصلة', 'Connected drives'), actions: [
          IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ]),
        child: CloudDrivesLayout(
          accounts: _accounts,
          loading: _loading,
          error: _error,
          connecting: _connecting,
          onConnect: _connect,
          onDisconnect: _disconnect,
          onRetry: _load,
        ),
      );
}

/// "Connected drives" group for the settings screen, next to the MFA entry. Hidden by the `profile.cloud_drives`
/// kill switch, and never for a guest or while a super admin views as someone else (the drive is the caller's).
class CloudDrivesSettingsEntry extends StatelessWidget {
  const CloudDrivesSettingsEntry({super.key, this.gap = 20, this.padding = EdgeInsets.zero, this.api});

  final double gap;
  final EdgeInsetsGeometry padding;
  final MeetingRecordingApi? api;

  @override
  Widget build(BuildContext context) {
    if (GuestState.active || ViewAsState.active) return const SizedBox.shrink();
    return ParentComponent(
      featureKey: 'profile.cloud_drives',
      child: Padding(
        padding: padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CloudDrivesGroup(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CloudDrivesPage(api: api)))),
          SizedBox(height: gap),
        ]),
      ),
    );
  }
}

/// The plain group: one row that opens [CloudDrivesPage].
class CloudDrivesGroup extends StatelessWidget {
  const CloudDrivesGroup({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsGroup(title: t('السحابة', 'Cloud'), icon: Icons.cloud_rounded, children: [
      SettingsTile(
        key: const ValueKey('cloud_drives.entry'),
        icon: Icons.cloud_sync_rounded,
        iconBg: c.primaryTint,
        iconColor: c.primary,
        label: t('السحابات المتصلة', 'Connected drives'),
        onTap: onTap,
      ),
    ]);
  }
}
