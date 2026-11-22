// lib/features/admin/live_settings/live_settings_page.dart
//
// Admin › App configuration › "Live performance" (D-089, super admin only, kill switch `admin.live_settings`).
//
//   LiveSettingsPage   loads GET /api/v1/admin/live-settings, keeps the edited draft, saves only the changed fields,
//                      "Reset to recommended" ({reset: true}); skeleton while loading, retry on an error, a "needs a
//                      server update" banner on a bare 404 / 405
//   LiveSettingsView   plain values → the page body (what the layout harness and the visual renders pump):
//                        · the preview card: what one viewer downloads with these settings (teacher camera, screen
//                          share, students' tiles, audio — a stacked bar), the teacher's upload, an hour per viewer,
//                          where the weak-network fallback starts, how far the draft is from the recommended set
//                        · Video (codec · weak network), Cameras, Screen share, Audio, Recording (where · engine ·
//                          streams): every two- or three-way choice is a row of cards with a trade-off line, small
//                          "less CPU / less data / better quality" tags and a "Recommended" badge
//                        · the action bar: n unsaved changes · Discard · Reset to recommended · Save
//
// Model, estimates and API: live_settings_draft.dart. Tests: test/org/live_settings_test.dart,
// test/ui/live_settings_layout_test.dart; renders test/visual/live_settings_golden_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppEase, AppReveal;

import '../admin_common.dart' show t;
import '../admin_page.dart';
import '../cfg_common.dart';
import 'live_settings_draft.dart';

export 'live_settings_draft.dart' show kLiveSettingsFeatureKey;

// ── Page ─────────────────────────────────────────────────────────────────────

class LiveSettingsPage extends StatefulWidget {
  const LiveSettingsPage({super.key, this.api = const LiveSettingsApi()});

  final LiveSettingsApi api;

  @override
  State<LiveSettingsPage> createState() => _LiveSettingsPageState();
}

class _LiveSettingsPageState extends State<LiveSettingsPage> {
  LiveSettingsInfo? _info;
  LiveSettingsDraft? _draft;
  Object? _error;
  bool _missing = false;
  bool _saving = false;

  int get _pending {
    final info = _info, draft = _draft;
    return info == null || draft == null ? 0 : draft.differencesFrom(info.settings);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_info != null && _pending > 0) {
      final ok = await appConfirm(context,
          message: t('لديك تغييرات لم تُحفظ. التحديث سيتجاهلها. متابعة؟', 'You have unsaved changes. Refreshing discards them. Continue?'));
      if (!ok || !mounted) return;
    }
    setState(() => _error = null);
    try {
      final info = await widget.api.load();
      if (!mounted) return;
      setState(() {
        _info = info;
        _draft = info.settings;
        _missing = false;
      });
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      // a failed refresh keeps the form that is on screen
      if (_info != null) {
        showAppNotice(ex.message, error: true);
        return;
      }
      setState(() {
        _missing = ex.statusCode == 404 || ex.statusCode == 405;
        _error = ex;
      });
    }
  }

  Future<void> _apply(Future<LiveSettingsInfo> Function() call, String done) async {
    setState(() => _saving = true);
    try {
      final info = await call();
      if (!mounted) return;
      setState(() {
        _info = info;
        _draft = info.settings;
      });
      showAppNotice(done);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final info = _info, draft = _draft;
    if (info == null || draft == null) return;
    final changes = draft.changesFrom(info.settings);
    if (changes.isEmpty) return;
    await _apply(() => widget.api.save(changes),
        t('حُفظت الإعدادات — تطبَّق على الدخول التالي', 'Saved — applies to the next join'));
  }

  Future<void> _reset() async {
    final ok = await appConfirm(
      context,
      message: t(
          'إعادة كل الإعدادات إلى القيم المستحسنة؟ مكان التسجيل يعود إلى الإعداد الافتراضي للخادم. الحصص الجارية تكمل كما بدأت.',
          'Put every setting back to the recommended value? Where classes are recorded goes back to the server\'s '
              'default. Classes already running finish the way they started.'),
      confirmLabel: t('الرجوع إلى المستحسن', 'Reset to recommended'),
    );
    if (!ok || !mounted) return;
    await _apply(widget.api.reset, t('عادت الإعدادات إلى المستحسن', 'Back to the recommended settings'));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info, draft = _draft;
    Widget body;
    if (_missing) {
      body = cfgErrorState(_error, onRetry: _load);
    } else if (info == null || draft == null) {
      body = _error != null ? cfgErrorState(_error, onRetry: _load) : const AppListSkeleton(items: 6, withAvatar: false);
    } else {
      body = LiveSettingsView(
        draft: draft,
        saved: info.settings,
        recommended: info.recommended,
        stored: info.stored,
        envRecordingMode: info.envRecordingMode,
        saving: _saving,
        showActionBar: false,
        onChanged: (d) => setState(() => _draft = d),
        onSave: _save,
        onReset: _reset,
        onDiscard: () => setState(() => _draft = info.settings),
      );
    }
    final pending = _pending;
    return AdminPage(
      title: liveSettingsTitle(),
      subtitle: t('الترميز، ضعف الشبكة، جودة الكاميرات والشاشة، ومكان التسجيل — لكل الأجهزة دون تحديث',
          'Codec, weak networks, camera and screen quality, and where classes are recorded — no app update'),
      icon: Icons.speed_rounded,
      width: AppWidth.content,
      onRefresh: _load,
      dirty: pending > 0,
      primaryAction: info == null
          ? null
          : cfgSaveButton(dirty: pending > 0, busy: _saving, onSave: _save),
      actions: [
        if (info != null && pending > 0)
          AppIconButton(
              icon: Icons.undo_rounded,
              tooltip: t('تراجع عن التغييرات', 'Discard changes'),
              onPressed: _saving ? null : () => setState(() => _draft = info.settings)),
        if (info != null)
          AppIconButton(
              icon: Icons.restart_alt_rounded,
              tooltip: t('الرجوع إلى المستحسن', 'Reset to recommended'),
              onPressed: _saving || draft?.differencesFrom(info.recommended) == 0 ? null : _reset),
      ],
      body: body,
    );
  }
}

String liveSettingsTitle() => t('أداء البث المباشر', 'Live performance');

// ── View (plain values) ──────────────────────────────────────────────────────

class LiveSettingsView extends StatelessWidget {
  const LiveSettingsView({
    super.key,
    required this.draft,
    required this.saved,
    required this.onChanged,
    required this.onSave,
    required this.onReset,
    this.recommended = LiveSettingsDraft.recommended,
    this.stored = const {},
    this.envRecordingMode,
    this.saving = false,
    this.onDiscard,
    this.showActionBar = true,
  });

  final LiveSettingsDraft draft;
  final LiveSettingsDraft saved;
  final LiveSettingsDraft recommended;
  final Set<String> stored;
  final String? envRecordingMode;
  final bool saving;
  final ValueChanged<LiveSettingsDraft> onChanged;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final VoidCallback? onDiscard;

  /// The Save / Reset / Discard bar under the page. The page (AdminPage) puts them in its header instead.
  final bool showActionBar;

  /// The jump list: section order matches [build]'s `sections`.
  static List<String> get sectionNames => [
        t('الفيديو', 'Video'),
        t('الكاميرات', 'Cameras'),
        t('مشاركة الشاشة', 'Screen share'),
        t('الصوت', 'Audio'),
        t('التسجيل', 'Recording'),
      ];

  @override
  Widget build(BuildContext context) => _JumpScope(
        count: sectionNames.length,
        builder: (context, keys, jump) => _build(context, keys, jump),
      );

  Widget _build(BuildContext context, List<GlobalKey> keys, void Function(int) jump) {
    final pending = draft.differencesFrom(saved);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 980;
      final preview = _PreviewCard(draft: draft, recommended: recommended);
      final sections = <Widget>[
        _videoSection(),
        _camerasSection(),
        _screenSection(),
        _audioSection(),
        _recordingSection(context),
      ];
      final list = ListView(
        // every section stays built, so the jump list can scroll to any of them
        scrollCacheExtent: const ScrollCacheExtent.pixels(100000),
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, wide ? AppSpace.xl : AppSpace.lg),
        children: [
          if (!wide) ...[AppReveal(index: 0, group: 'live_settings', child: preview), AppSpace.gapMd],
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) AppSpace.gapMd,
            KeyedSubtree(
                key: keys[i],
                child: AppReveal(index: i + (wide ? 0 : 1), group: 'live_settings', cap: 3, child: sections[i])),
          ],
        ],
      );
      final names = sectionNames;
      return Column(children: [
        // the jump list: one chip per section
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
          child: Row(children: [
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: AppChoiceChip(label: names[i], selected: false, onTap: () => jump(i)),
              ),
          ]),
        ),
        Expanded(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: list),
                  SizedBox(
                    width: 372,
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, AppSpace.md, AppSpace.md, AppSpace.lg),
                      child: AppReveal(index: 0, group: 'live_settings.preview', child: preview),
                    ),
                  ),
                ])
              : list,
        ),
        if (showActionBar)
          _ActionBar(
            pending: pending,
            atRecommended: draft.differencesFrom(recommended) == 0,
            saving: saving,
            onSave: pending > 0 ? onSave : null,
            onReset: onReset,
            onDiscard: pending > 0 ? onDiscard : null,
          ),
      ]);
    });
  }

  // ── sections ──

  Widget _videoSection() => _Section(
        icon: Icons.videocam_rounded,
        title: t('الفيديو', 'Video'),
        subtitle: t('كيف يُضغط الفيديو وماذا يحدث عندما تضعف الشبكة',
            'How video is compressed, and what happens when a network gets weak'),
        children: [
          _Field(
            label: t('ترميز الفيديو المفضل', 'Preferred video codec'),
            help: t('الأجهزة التي لا تدعمه تستخدم VP8 تلقائياً.', 'Devices that cannot use it fall back to VP8.'),
            child: _ChoiceRow<String>(
              value: draft.videoCodec,
              recommended: recommended.videoCodec,
              onChanged: (v) => onChanged(draft.copyWith(videoCodec: v)),
              options: [
                _Option('vp8', 'VP8', t('يعمل على كل جهاز ومتصفح، والطبقات المتعددة مستقرة في كل مكان.',
                    'Plays on every device and browser; simulcast is solid everywhere.'),
                    icon: Icons.devices_rounded,
                    tags: [_Pro(t('يعمل في كل مكان', 'Works everywhere')), _Pro(t('خفيف في العرض', 'Light to play'))]),
                _Option('h264', 'H.264', t('الهواتف تضغطه بالعتاد: بطارية ومعالج أقل لمن يبث.',
                    'Phones encode it in hardware: less battery and CPU for whoever broadcasts.'),
                    icon: Icons.memory_rounded,
                    tags: [_Pro(t('معالج أقل على الهاتف', 'Less CPU on phones')), _Con(t('بيانات أكثر بنحو 10%', '~10 % more data'))]),
                _Option('vp9', 'VP9', t('نفس الصورة ببيانات أقل بنحو 30%، لكن ضغطه أثقل.',
                    'The same picture with about 30 % less data, but heavier to encode.'),
                    icon: Icons.compress_rounded,
                    tags: [_Pro(t('بيانات أقل', 'Less data')), _Con(t('معالج أكثر', 'More CPU'))]),
              ],
            ),
          ),
          _Field(
            label: t('عند ضعف الشبكة', 'On a weak network'),
            child: _ChoiceRow<String>(
              value: draft.weakNetwork,
              recommended: recommended.weakNetwork,
              onChanged: (v) => onChanged(draft.copyWith(weakNetwork: v)),
              options: [
                _Option('adaptive', t('خفض الجودة تدريجياً', 'Step the video down'),
                    t('ينزل الفيديو إلى 360p ثم 180p ولا يتوقف، والصوت يبقى واضحاً.',
                        'Video drops to 360p, then 180p, and never stops; the voice stays clear.'),
                    icon: Icons.stacked_line_chart_rounded,
                    tags: [_Pro(t('الفيديو يستمر', 'Video keeps going')), _Con(t('صورة أقل وضوحاً', 'Softer picture'))]),
                _Option('audio_first', t('الصوت أولاً', 'Audio first'),
                    t('تحت نحو 0.35 ميجابت يبقى الصوت فقط مع زر «إظهار الفيديو».',
                        'Below ~0.35 Mbit/s viewers keep the voice, with a "Show video" button.'),
                    icon: Icons.record_voice_over_rounded,
                    tags: [_Pro(t('أقل بيانات', 'Least data')), _Pro(t('الصوت لا ينقطع', 'Voice never breaks')),
                      _Con(t('لا فيديو حتى يُطلب', 'No video until asked'))]),
              ],
            ),
          ),
        ],
      );

  Widget _camerasSection() => _Section(
        icon: Icons.photo_camera_front_rounded,
        title: t('الكاميرات', 'Cameras'),
        subtitle: t('أقصى جودة يرسلها كل جهاز — المشاهد يأخذ الطبقة التي تناسب شاشته',
            'The most each device sends — every viewer takes the layer that fits their screen'),
        children: [
          _Field(
            label: t('كاميرا المعلم بحد أقصى', "Teacher's camera, at most"),
            hint: _recHint(draft.cameraMaxHost, recommended.cameraMaxHost),
            child: _Segmented<String>(
              value: draft.cameraMaxHost,
              recommended: recommended.cameraMaxHost,
              items: [for (final v in kHostCameraCaps) (v, v)],
              onChanged: (v) => onChanged(draft.copyWith(cameraMaxHost: v)),
            ),
          ),
          _Field(
            label: t('كاميرات الحاضرين بحد أقصى', "Attendees' cameras, at most"),
            hint: _recHint(draft.cameraMaxParticipant, recommended.cameraMaxParticipant),
            child: _Segmented<String>(
              value: draft.cameraMaxParticipant,
              recommended: recommended.cameraMaxParticipant,
              items: [for (final v in kParticipantCameraCaps) (v, v)],
              onChanged: (v) => onChanged(draft.copyWith(cameraMaxParticipant: v)),
            ),
          ),
          _Field(
            label: t('عدد الإطارات في الثانية', 'Frames per second'),
            hint: _recHint('${draft.cameraFps}', '${recommended.cameraFps}'),
            child: _Segmented<int>(
              value: draft.cameraFps,
              recommended: recommended.cameraFps,
              items: [for (final v in kCameraFps) (v, '$v fps')],
              onChanged: (v) => onChanged(draft.copyWith(cameraFps: v)),
            ),
          ),
          // the host's own rate (D-1643): Automatic follows the line above; once a rate is saved only Reset brings
          // Automatic back (the server keeps a stored value until a reset)
          _Field(
            label: t('إطارات كاميرا المعلم', "Teacher's camera frame rate"),
            hint: draft.cameraFpsHost == null
                ? t('تلقائي: ${_ltr('${draft.effectiveHostFps} fps')} حسب الإطارات أعلاه',
                    'Automatic: ${draft.effectiveHostFps} fps, from the rate above')
                : (saved.cameraFpsHost != null && recommended.cameraFpsHost == null
                    ? t('«الرجوع إلى المستحسن» يعيده تلقائياً', '"Reset to recommended" makes it automatic again')
                    : null),
            child: _Segmented<int?>(
              value: draft.cameraFpsHost,
              recommended: recommended.cameraFpsHost,
              items: [
                if (saved.cameraFpsHost == null) (null, t('تلقائي', 'Auto')),
                for (final v in kHostCameraFps) (v, '$v fps'),
              ],
              onChanged: (v) => onChanged(v == null ? draft.copyWith(autoHostFps: true) : draft.copyWith(cameraFpsHost: v)),
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          _SwitchRow(
            icon: Icons.videocam_off_rounded,
            title: t('كاميرات الحاضرين مغلقة عند الدخول', 'Attendees join with the camera off'),
            subtitle: t('كل كاميرا مفتوحة = رفع وضغط على جهاز الطالب وتحميل عند الجميع. يفتحها من يريد.',
                'Every open camera is an upload and an encoder on the student\'s device and a download for everyone. '
                    'Anyone can turn theirs on.'),
            value: draft.participantsCameraDefaultOff,
            recommended: recommended.participantsCameraDefaultOff,
            onChanged: (v) => onChanged(draft.copyWith(participantsCameraDefaultOff: v)),
          ),
          _SwitchRow(
            icon: Icons.visibility_off_rounded,
            title: t('إيقاف الفيديو غير الظاهر', 'Pause video nobody sees'),
            subtitle: t('مربع خارج الشاشة أو بث مصغّر لا يُحمَّل فيديوه.',
                'A tile scrolled out of view or a minimized room stops downloading its video.'),
            value: draft.pauseHiddenVideo,
            recommended: recommended.pauseHiddenVideo,
            onChanged: (v) => onChanged(draft.copyWith(pauseHiddenVideo: v)),
          ),
        ],
      );

  Widget _screenSection() => _Section(
        icon: Icons.screen_share_rounded,
        title: t('مشاركة الشاشة', 'Screen share'),
        subtitle: t('الشرائح والنصوص تحتاج وضوحاً أكثر من الحركة', 'Slides and text need sharpness more than motion'),
        children: [
          _SliderField(
            label: t('الإطارات في الثانية بحد أقصى', 'Frames per second, at most'),
            valueLabel: '${draft.screenFpsMax} fps',
            hint: _recHint('${draft.screenFpsMax}', '${recommended.screenFpsMax}', unit: ' fps'),
            value: draft.screenFpsMax.toDouble(),
            min: kScreenFpsMin.toDouble(),
            max: kScreenFpsMax.toDouble(),
            divisions: kScreenFpsMax - kScreenFpsMin,
            lowLabel: t('بيانات أقل', 'Less data'),
            highLabel: t('حركة أنعم', 'Smoother motion'),
            caption: t('الشرائح تكفيها 5–15؛ الفيديو والتمرير يحتاجان أكثر.',
                'Slides need 5–15; video and scrolling need more.'),
            onChanged: (v) => onChanged(draft.copyWith(screenFpsMax: v.round())),
          ),
          _SliderField(
            label: t('معدل البيانات بحد أقصى', 'Bitrate, at most'),
            valueLabel: '${mbps(draft.screenBitrateKbps)} Mbit/s',
            hint: _recHint(mbps(draft.screenBitrateKbps), mbps(recommended.screenBitrateKbps), unit: ' Mbit/s'),
            value: draft.screenBitrateKbps.toDouble(),
            min: kScreenBitrateMin.toDouble(),
            max: kScreenBitrateMax.toDouble(),
            divisions: (kScreenBitrateMax - kScreenBitrateMin) ~/ kScreenBitrateStep,
            lowLabel: t('للشبكات الضعيفة', 'For weak networks'),
            highLabel: t('نص أوضح', 'Crisper text'),
            caption: t('حد أعلى: الشرائح الثابتة تستهلك أقل منه بكثير.',
                'A ceiling: still slides use far less than this.'),
            onChanged: (v) => onChanged(draft.copyWith(
                screenBitrateKbps: ((v / kScreenBitrateStep).round() * kScreenBitrateStep)
                    .clamp(kScreenBitrateMin, kScreenBitrateMax))),
          ),
        ],
      );

  Widget _audioSection() => _Section(
        icon: Icons.graphic_eq_rounded,
        title: t('الصوت', 'Audio'),
        subtitle: t('الصوت أهم ما في الحصة: يُحمى قبل الفيديو', 'The voice matters most in a class: it is protected first'),
        children: [
          _SwitchRow(
            icon: Icons.volume_mute_rounded,
            title: t('لا إرسال أثناء الصمت (DTX)', 'Send nothing during silence (DTX)'),
            subtitle: t('الميكروفون المفتوح في الصمت لا يرسل تقريباً شيئاً.', 'An open microphone in silence sends almost nothing.'),
            value: draft.audioDtx,
            recommended: recommended.audioDtx,
            onChanged: (v) => onChanged(draft.copyWith(audioDtx: v)),
          ),
          _SwitchRow(
            icon: Icons.shield_rounded,
            title: t('صوت احتياطي (RED)', 'Redundant audio (RED)'),
            subtitle: t('كل حزمة تحمل نسخة من السابقة: يخفي فقد 5–10% مقابل نحو 30 كيلوبت.',
                'Each packet carries a copy of the last one: hides 5–10 % loss for ~30 kbit/s.'),
            value: draft.audioRed,
            recommended: recommended.audioRed,
            onChanged: (v) => onChanged(draft.copyWith(audioRed: v)),
          ),
        ],
      );

  Widget _recordingSection(BuildContext context) {
    final server = draft.recordingMode == 'server';
    final unset = !stored.contains('recording_mode') && draft.recordingMode == saved.recordingMode;
    return _Section(
      icon: Icons.fiber_manual_record_rounded,
      title: t('التسجيل', 'Recording'),
      subtitle: t('يطبَّق على الحصص التي تبدأ بعد الحفظ؛ الحصة الجارية تكمل بطريقتها',
          'Applies to classes that start after you save; a running class finishes its own way'),
      children: [
        _Field(
          label: t('أين تُسجَّل الحصص', 'Where classes are recorded'),
          help: unset && envRecordingMode != null
              ? t('لم يُختر بعد: يطبَّق الإعداد الافتراضي للخادم (${envRecordingMode == 'client' ? 'جهاز المعلم' : 'الخادم'}).',
                  'Not chosen yet: the server\'s default applies (${envRecordingMode == 'client' ? "the teacher's device" : 'the server'}).')
              : null,
          child: _ChoiceRow<String>(
            value: draft.recordingMode,
            recommended: recommended.recordingMode,
            onChanged: (v) => onChanged(draft.copyWith(recordingMode: v)),
            options: [
              _Option('server', t('على الخادم', 'On the server'),
                  t('تسجيل واحد يصنعه الخادم؛ جهاز المعلم لا يفعل شيئاً إضافياً.',
                      "One recording made by the server; the teacher's device does nothing extra."),
                  icon: Icons.dns_rounded,
                  tags: [_Pro(t('لا حمل على جهاز المعلم', "No load on the teacher's device")),
                    _Con(t('معالج الخادم', 'Server CPU'))]),
              _Option('client', t('على جهاز المعلم', "On the teacher's device"),
                  t('الجهاز يسجّل ويرفع مقاطع كل 5 ثوانٍ، والخادم يجمعها.',
                      'The device records and uploads 5-second pieces; the server joins them.'),
                  icon: Icons.phone_iphone_rounded,
                  tags: [_Pro(t('لا معالج على الخادم', 'No server CPU')),
                    _Con(t('بطارية ورفع من جهاز المعلم', "Battery and upload on the teacher's device"))]),
            ],
          ),
        ),
        if (!server)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppBanner(
              icon: Icons.dns_outlined,
              text: t('محرّك تسجيل الخادم وعدد النسخ يظهران عند اختيار التسجيل على الخادم.',
                  "The server's recording engine and copies appear when classes are recorded on the server."),
            ),
          ),
        if (server)
        _Field(
          label: t('محرّك تسجيل الخادم', "Server's recording engine"),
          child: _ChoiceRow<String>(
            value: draft.serverRecordingEngine,
            recommended: recommended.serverRecordingEngine,
            enabled: server,
            onChanged: (v) => onChanged(draft.copyWith(serverRecordingEngine: v)),
            options: [
              _Option('composite', t('تسجيل الغرفة كاملة', 'The whole room'),
                  t('الشاشة المشتركة، أو الكاميرات حين لا يشارك أحد، وكل الأصوات.',
                      'The shared screen, or the cameras when nothing is shared, and every voice.'),
                  icon: Icons.dashboard_rounded,
                  tags: [_Pro(t('الكاميرات بلا مشاركة', 'Cameras when nothing is shared')),
                    _Con(t('معالج أكثر', 'More CPU'))]),
              _Option('media', t('شاشة المعلم فقط', "The teacher's screen only"),
                  t('الشاشة المشتركة بدقتها الكاملة بنحو نصف المعالج. الفيديو أسود حين لا يشارك المعلم شيئاً (الأصوات تُسجَّل).',
                      "The shared screen pixel-sharp at about half the CPU. The video is black while the teacher shares "
                          'nothing (the voices still record).'),
                  icon: Icons.slideshow_rounded,
                  tags: [_Pro(t('أوضح شرائح', 'Sharpest slides')), _Pro(t('معالج أقل', 'Less CPU')),
                    _Con(t('أسود بلا مشاركة', 'Black without a share'))]),
            ],
          ),
        ),
        if (server)
        _Field(
          label: t('نسخ التسجيل', 'Recorded copies'),
          child: _ChoiceRow<String>(
            value: draft.serverRecordingTiers,
            recommended: recommended.serverRecordingTiers,
            enabled: server,
            onChanged: (v) => onChanged(draft.copyWith(serverRecordingTiers: v)),
            options: [
              _Option('single', t('نسخة واحدة 1080p', 'One 1080p copy'),
                  t('مهمة تسجيل واحدة لكل حصة، بكل الأصوات.', 'One recording job per class, every voice in it.'),
                  icon: Icons.looks_one_rounded,
                  tags: [_Pro(t('معالج أقل حتى 6 مرات', 'Up to 6× less CPU'))]),
              _Option('all', t('كل الجودات', 'Every quality'),
                  t('عالية ومتوسطة ومنخفضة وصوت فقط، كما ضُبط الخادم.',
                      'High, medium, low and audio-only, as the server is configured.'),
                  icon: Icons.layers_rounded,
                  tags: [_Pro(t('جودات جاهزة', 'Ready-made qualities')), _Con(t('حتى 6 مهام لكل حصة', 'Up to 6 jobs per class'))]),
            ],
          ),
        ),
        if (server)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: AppBanner(
              icon: Icons.speed_rounded,
              text: t(
                  'معالج الخادم لكل حصة مسجّلة: تسجيل الغرفة بمتصفح Chrome نحو 1.5 نواة (ذروة 3)، وبالمركّب الجديد نحو 0.5، وشاشة المعلم فقط نحو 0.8. حاوية التسجيل تحتاج 3 أنوية على الأقل لتسجيل Chrome واحد.',
                  'Server CPU per recorded class: the whole room with Chrome about 1.5 cores (peak 3), with the new compositor about 0.5, '
                      "the teacher's screen only about 0.8. The recording container needs at least 3 cores per Chrome job."),
            ),
          ),
      ],
    );
  }
}

/// "1.5 GB" from a thousand MB up, else "640 MB".
String hourLabel(int mb) => mb >= 1000 ? '${(mb / 1000).toStringAsFixed(1)} GB' : '$mb MB';

String? _recHint(String value, String rec, {String unit = ''}) =>
    value == rec ? null : t('المستحسن: ${_ltr('$rec$unit')}', 'Recommended: $rec$unit');

/// A number with its unit kept in reading order inside Arabic text (LRI … PDI).
String _ltr(String s) => '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}';

// ── Preview card ─────────────────────────────────────────────────────────────

/// The page's one memorable element: a sky (information) block whose figure — what one viewer downloads — glides to
/// its new value as a setting changes. Ink on the block, paper tiles for the secondary figures, no gradient.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.draft, required this.recommended});

  final LiveSettingsDraft draft;
  final LiveSettingsDraft recommended;

  @override
  Widget build(BuildContext context) => AppBlock(
        tone: AppBlockTone.sky,
        hero: true,
        child: _PreviewBody(draft: draft, recommended: recommended),
      );
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.draft, required this.recommended});

  final LiveSettingsDraft draft;
  final LiveSettingsDraft recommended;

  @override
  Widget build(BuildContext context) {
    final ink = AppBlock.colorsOf(context);
    final b = estimateBandwidth(draft);
    final away = draft.differencesFrom(recommended);
    final palette = appChartPalette(context);
    // the sky slot (index 2) would vanish on the sky block: emerald · peach · gold · purple
    final parts = <(String, int, Color)>[
      (t('كاميرا المعلم', "Teacher's camera"), b.teacherCameraKbps, palette[0]),
      (t('مشاركة الشاشة', 'Screen share'), b.screenKbps, palette[1]),
      (t('كاميرات الطلاب', "Students' cameras"), b.studentTilesKbps, palette[3]),
      (t('الصوت', 'Audio'), b.audioKbps, palette[4]),
    ];
    final total = b.perViewerWithShareKbps;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.network_check_rounded, color: ink.ink, size: AppIconSize.lg),
        AppSpace.gapSm,
        Expanded(
          child: Text(t('بيانات كل مشاهد', 'Data per viewer'),
              style: AppType.section(context).copyWith(color: ink.ink), maxLines: 2),
        ),
      ]),
      AppSpace.gapXs,
      _StatusChip(
        icon: away == 0 ? Icons.verified_rounded : Icons.tune_rounded,
        label: away == 0
            ? t('الإعداد المستحسن', 'The recommended setup')
            : t('$away ${away == 1 ? 'اختلاف' : 'اختلافات'} عن المستحسن',
                '$away ${away == 1 ? 'difference' : 'differences'} from recommended'),
      ),
      AppSpace.gapLg,
      Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
        AppCountUp('~${mbps(b.perViewerKbps)}',
            memoryKey: 'live_settings.per_viewer',
            style: AppType.figureLarge(context).copyWith(color: ink.ink),
            textDirection: TextDirection.ltr),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Text('Mbit/s', style: AppType.label(context).copyWith(color: ink.muted)),
        ),
      ]),
      const SizedBox(height: AppSpace.xxs),
      Text(
        t('أثناء مشاركة الشاشة حتى ${mbps(total)} ميجابت/ث', 'Up to ${mbps(total)} Mbit/s while the screen is shared'),
        style: AppType.label(context).copyWith(color: ink.muted),
      ),
      AppSpace.gapMd,
      _StackedBar(parts: [for (final p in parts) (p.$2, p.$3)], edge: ink.faint),
      AppSpace.gapSm,
      for (final p in parts)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Row(children: [
            Container(
                width: AppSpace.sm,
                height: AppSpace.sm,
                decoration: BoxDecoration(color: p.$3, borderRadius: AppRadius.chipAll)),
            AppSpace.gapXs,
            Expanded(child: Text(p.$1, style: AppType.meta(context).copyWith(color: ink.muted))),
            Text(p.$2 == 0 ? '—' : '${mbps(p.$2)} Mbit/s',
                style: AppType.meta(context).copyWith(color: ink.ink, fontWeight: FontWeight.w600),
                textDirection: TextDirection.ltr),
          ]),
        ),
      const SizedBox(height: AppSpace.xxs),
      Text(
        t('حصة فيها $kPreviewStudents طالباً، ${b.camerasOn} كاميرا مفتوحة، يظهر منها ${b.studentTiles} على الشاشة.',
            'A class of $kPreviewStudents students, ${b.camerasOn} cameras on, ${b.studentTiles} of them on screen.'),
        style: AppType.meta(context).copyWith(color: ink.faint),
      ),
      AppSpace.gapMd,
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _PaperStat(
                icon: Icons.upload_rounded,
                value: '${mbps(b.teacherUploadKbps)} Mbit/s',
                label: t('رفع المعلم مع المشاركة', "Teacher's upload, sharing"))),
        AppSpace.gapXs,
        Expanded(
            child: _PaperStat(
                icon: Icons.schedule_rounded,
                value: '~${hourLabel(b.perViewerHourMb)}',
                label: t('ساعة لكل مشاهد', 'One hour per viewer'))),
      ]),
      AppSpace.gapXs,
      _PaperStat(
        icon: draft.weakNetwork == 'audio_first' ? Icons.record_voice_over_rounded : Icons.signal_cellular_alt_2_bar_rounded,
        value: t('تحت ${mbps(b.weakNetworkFloorKbps)} ميجابت/ث', 'Below ${mbps(b.weakNetworkFloorKbps)} Mbit/s'),
        label: draft.weakNetwork == 'audio_first'
            ? t('يبقى الصوت مع زر «إظهار الفيديو»', 'Voice only, with a "Show video" button')
            : t('ينزل الفيديو إلى أدنى طبقة 180p', 'Video steps down to the 180p layer'),
      ),
    ]);
  }
}

/// A share of one viewer's download, part by part, on a paper track; the parts glide when a setting moves them.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.parts, required this.edge});

  final List<(int, Color)> parts;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    final motion = AppMotion.of(context);
    return Container(
      height: AppSpace.sm,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
        border: Border.all(color: edge.withValues(alpha: 0.35), width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        return Row(children: [
          for (final p in parts)
            if (p.$1 > 0)
              AnimatedContainer(
                duration: motion.base,
                curve: AppEase.out,
                width: box.maxWidth * p.$1 / (total == 0 ? 1 : total),
                color: p.$2,
              ),
        ]);
      }),
    );
  }
}

/// The block's status line: how far the draft is from the recommended set (paper chip, ink label).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: ink.ink),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(label,
              style: AppType.label(context).copyWith(color: ink.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// A secondary figure on the preview block: paper on the sky, a hairline, ink.
class _PaperStat extends StatelessWidget {
  const _PaperStat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.sm, color: c.textMedium),
        AppSpace.gapXs,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: AppType.bodyStrong(context),
                textDirection: RegExp(r'^[~0-9]').hasMatch(value) ? TextDirection.ltr : null),
            const SizedBox(height: AppSpace.xxs),
            Text(label, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

/// Owns the section keys of the jump list and scrolls a section into view.
class _JumpScope extends StatefulWidget {
  const _JumpScope({required this.count, required this.builder});

  final int count;
  final Widget Function(BuildContext, List<GlobalKey>, void Function(int)) builder;

  @override
  State<_JumpScope> createState() => _JumpScopeState();
}

class _JumpScopeState extends State<_JumpScope> {
  late final List<GlobalKey> _keys = List.generate(widget.count, (_) => GlobalKey());

  void _jump(int i) {
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).base, curve: Curves.easeOutCubic, alignment: 0.02);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _keys, _jump);
}

// ── Sections, fields ─────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.subtitle, required this.children});

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppTouch.min - AppSpace.xs,
            height: AppTouch.min - AppSpace.xs,
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll),
            child: Icon(icon, color: c.textDark, size: AppIconSize.md),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(subtitle, style: AppType.meta(context)),
            ]),
          ),
        ]),
        AppSpace.gapLg,
        ...children,
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.help, this.hint});

  final String label;
  final Widget child;

  /// A line under the control (a fallback, a caveat).
  final String? help;

  /// Shown at the end of the label row: "Recommended: 720p" while the value is not the recommended one.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: AppType.bodyStrong(context)),
          if (hint != null) _RecommendedPill(text: hint!, subtle: true),
        ]),
        AppSpace.gapSm,
        child,
        if (help != null) ...[
          AppSpace.gapXs,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xxs),
            Expanded(child: Text(help!, style: AppType.meta(context))),
          ]),
        ],
      ]),
    );
  }
}

class _RecommendedPill extends StatelessWidget {
  const _RecommendedPill({this.text, this.subtle = false});

  final String? text;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppBorder.focus),
      decoration: BoxDecoration(
        color: subtle ? c.inputBg : appTintOn(context, c.success),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: AppIconSize.xs, color: appInkOn(context, c.success, subtle ? c.inputBg : appTintOn(context, c.success))),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(text ?? t('مستحسن', 'Recommended'),
              style: AppType.overline(context).copyWith(
                  letterSpacing: 0,
                  color: subtle ? c.textMedium : appInkOn(context, c.success, appTintOn(context, c.success))),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ── Choice cards ─────────────────────────────────────────────────────────────

sealed class _Tag {
  const _Tag(this.label);
  final String label;
}

class _Pro extends _Tag {
  const _Pro(super.label);
}

class _Con extends _Tag {
  const _Con(super.label);
}

class _Option<T> {
  const _Option(this.value, this.title, this.body, {required this.icon, this.tags = const []});

  final T value;
  final String title;
  final String body;
  final IconData icon;
  final List<_Tag> tags;
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.value,
    required this.recommended,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final T recommended;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final perCard = options.length == 3 ? 200.0 : 250.0;
      final side = box.maxWidth >= perCard * options.length + AppSpace.sm * (options.length - 1);
      final cards = [
        for (final o in options)
          _ChoiceCard(
            option: o,
            selected: o.value == value,
            recommended: o.value == recommended,
            enabled: enabled,
            onTap: () => onChanged(o.value),
          ),
      ];
      if (!side) {
        return Column(children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) AppSpace.gapSm, cards[i]],
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) AppSpace.gapSm, Expanded(child: cards[i])],
        ]),
      );
    });
  }
}

class _ChoiceCard<T> extends StatelessWidget {
  const _ChoiceCard({
    required this.option,
    required this.selected,
    required this.recommended,
    required this.enabled,
    required this.onTap,
  });

  final _Option<T> option;
  final bool selected;
  final bool recommended;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    final card = AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppEase.out,
      decoration: BoxDecoration(
        color: selected ? c.primaryTint : c.cardBg,
        borderRadius: r,
        border: Border.all(
            color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppEase.out,
            width: AppIconSize.hero,
            height: AppIconSize.hero,
            decoration: BoxDecoration(
              color: selected ? c.primary : c.inputBg,
              borderRadius: AppRadius.controlAll,
            ),
            child: Icon(option.icon, size: AppIconSize.md, color: selected ? c.onHero : c.textDark),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(option.title, style: AppType.bodyStrong(context)),
            ),
          ),
          AppSpace.gapXs,
          _Radio(selected: selected),
        ]),
        if (recommended) ...[
          AppSpace.gapXs,
          const _RecommendedPill(),
        ],
        AppSpace.gapXs,
        Text(option.body, style: AppType.meta(context)),
        if (option.tags.isNotEmpty) ...[
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [for (final tag in option.tags) _TagChip(tag: tag)]),
        ],
      ]),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: option.title,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: r, onTap: enabled && !selected ? onTap : null, child: card),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppEase.out,
      width: AppIconSize.lg,
      height: AppIconSize.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.primary : c.cardBg,
        border: Border.all(color: selected ? c.primary : c.textLight, width: AppBorder.strong),
      ),
      child: selected ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero) : null,
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final _Tag tag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pro = tag is _Pro;
    final color = pro ? c.success : c.warning;
    final tint = appTintOn(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pro ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
            size: AppIconSize.xs, color: appInkOn(context, color, tint)),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(tag.label, style: AppType.meta(context).copyWith(color: c.textDark))),
      ]),
    );
  }
}

// ── Segmented control ────────────────────────────────────────────────────────

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.recommended, required this.items, required this.onChanged});

  final T value;
  final T recommended;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: AppRadius.controlAll,
      ),
      child: Row(children: [
        for (final (v, label) in items)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              label: label,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: AppRadius.chipAll,
                  onTap: v == value ? null : () => onChanged(v),
                  child: AnimatedContainer(
                    duration: AppMotion.of(context).fast,
                    curve: AppEase.out,
                    constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? c.primary : null,
                      borderRadius: AppRadius.chipAll,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xs),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (v == recommended) ...[
                        Icon(Icons.star_rounded,
                            size: AppIconSize.xs, color: v == value ? c.onHero : appInkOn(context, c.success, c.inputBg)),
                        const SizedBox(width: AppSpace.xxs),
                      ],
                      Flexible(
                        child: Text(label,
                            style: AppType.label(context).copyWith(
                                fontWeight: FontWeight.w600, color: v == value ? c.onHero : c.textMedium),
                            textDirection: TextDirection.ltr, // "24 fps", "720p"
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Slider, switch rows ──────────────────────────────────────────────────────

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
    required this.caption,
    this.hint,
  });

  final String label;
  final String valueLabel;

  /// One line next to the value: what the number means for a viewer.
  final String caption;
  final String? hint;
  final double value, min, max;
  final int divisions;
  final String lowLabel, highLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Field(
      label: label,
      hint: hint,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xs),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: AppRadius.controlAll,
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(caption, style: AppType.meta(context), maxLines: 2),
            ),
            AppSpace.gapXs,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll),
              child: AppCountUp(valueLabel,
                  style: AppType.figure(context), textDirection: TextDirection.ltr),
            ),
          ]),
          Row(children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: AppSpace.xxs + AppBorder.focus,
                  activeTrackColor: c.primary,
                  inactiveTrackColor: c.divider,
                  thumbColor: c.primary,
                  overlayColor: c.primary.withValues(alpha: 0.12),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: valueLabel,
                  onChanged: onChanged,
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xs),
            child: Row(children: [
              Icon(Icons.remove_rounded, size: AppIconSize.xs, color: c.textLight),
              const SizedBox(width: AppSpace.xxs),
              Expanded(
                  child: Text(lowLabel,
                      style: AppType.meta(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              AppSpace.gapXs,
              Flexible(
                child: Text(highLabel,
                    textAlign: TextAlign.end,
                    style: AppType.meta(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSpace.xxs),
              Icon(Icons.add_rounded, size: AppIconSize.xs, color: c.textLight),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.recommended,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool recommended;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: AppRadius.controlAll,
      ),
      child: AppSwitchTile(
        icon: icon,
        title: title,
        value: value,
        onChanged: onChanged,
        subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle, style: AppType.meta(context)),
          if (value != recommended) ...[
            AppSpace.gapXs,
            _RecommendedPill(
                text: recommended ? t('المستحسن: مفعّل', 'Recommended: on') : t('المستحسن: متوقف', 'Recommended: off'),
                subtle: true),
          ],
        ]),
      ),
    );
  }
}

// ── Action bar ───────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.pending,
    required this.atRecommended,
    required this.saving,
    required this.onSave,
    required this.onReset,
    required this.onDiscard,
  });

  final int pending;
  final bool atRecommended;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback onReset;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = pending == 0
        ? t('كل التغييرات محفوظة', 'Everything is saved')
        : t('$pending ${pending == 1 ? 'تغيير غير محفوظ' : 'تغييرات غير محفوظة'}',
            '$pending unsaved ${pending == 1 ? 'change' : 'changes'}');
    final reset = TextButton.icon(
      onPressed: saving || atRecommended ? null : onReset,
      icon: const Icon(Icons.restart_alt_rounded, size: AppIconSize.md),
      label: Text(t('الرجوع إلى المستحسن', 'Reset to recommended'), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final discard = onDiscard == null
        ? null
        : TextButton(onPressed: saving ? null : onDiscard, child: Text(t('تراجع', 'Discard')));
    final save = AppPrimaryButton(
      label: t('حفظ', 'Save'),
      icon: Icons.check_rounded,
      busy: saving,
      onPressed: saving ? null : onSave,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 560;
          final statusRow = Row(children: [
            Icon(pending == 0 ? Icons.cloud_done_rounded : Icons.edit_note_rounded,
                size: AppIconSize.md, color: pending == 0 ? c.success : c.warning),
            AppSpace.gapXs,
            Expanded(
              child: Text(status,
                  style: AppType.bodyStrong(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (narrow && discard != null) discard,
          ]);
          if (narrow) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              statusRow,
              AppSpace.gapXs,
              Row(children: [
                Expanded(child: reset),
                AppSpace.gapXs,
                SizedBox(width: 132, child: save),
              ]),
            ]);
          }
          return Row(children: [
            Expanded(child: statusRow),
            if (discard != null) ...[discard, const SizedBox(width: AppSpace.xxs)],
            Flexible(child: reset),
            AppSpace.gapSm,
            SizedBox(width: 180, child: save),
          ]);
        }),
      ),
    );
  }
}
