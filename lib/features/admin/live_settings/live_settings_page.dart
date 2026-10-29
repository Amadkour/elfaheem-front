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
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin_common.dart' show t;
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
  String? _error;
  bool _missing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      setState(() {
        _missing = ex.statusCode == 404 || ex.statusCode == 405;
        _error = ex.message;
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
      body = ListView(padding: const EdgeInsets.all(16), children: [
        AppBanner(
          icon: Icons.system_update_alt_rounded,
          text: t('هذه الصفحة تحتاج تحديث الخادم.', 'This page needs a server update.'),
        ),
      ]);
    } else if (info == null || draft == null) {
      body = _error != null
          ? AppEmpty(
              icon: Icons.cloud_off_rounded,
              title: _error!,
              actionLabel: t('إعادة المحاولة', 'Try again'),
              onAction: _load,
            )
          : const AppListSkeleton(items: 6, withAvatar: false);
    } else {
      body = LiveSettingsView(
        draft: draft,
        saved: info.settings,
        recommended: info.recommended,
        stored: info.stored,
        envRecordingMode: info.envRecordingMode,
        saving: _saving,
        onChanged: (d) => setState(() => _draft = d),
        onSave: _save,
        onReset: _reset,
        onDiscard: () => setState(() => _draft = info.settings),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 1180,
      enableFooterWidget: false,
      appBar: ScreenAppBar(title: liveSettingsTitle()),
      child: body,
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

  @override
  Widget build(BuildContext context) {
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
        padding: EdgeInsets.fromLTRB(16, 16, 16, wide ? 32 : 24),
        children: [
          if (!wide) ...[preview, const SizedBox(height: 16)],
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            sections[i],
          ],
        ],
      );
      return Column(children: [
        Expanded(
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: list),
                  SizedBox(
                    width: 372,
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(0, 16, 16, 24),
                      child: preview,
                    ),
                  ),
                ])
              : list,
        ),
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
          const SizedBox(height: 4),
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
            padding: const EdgeInsets.only(bottom: 12),
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
            padding: const EdgeInsets.only(top: 4),
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.draft, required this.recommended});

  final LiveSettingsDraft draft;
  final LiveSettingsDraft recommended;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = estimateBandwidth(draft);
    final away = draft.differencesFrom(recommended);
    final parts = <(String, int, Color)>[
      (t('كاميرا المعلم', "Teacher's camera"), b.teacherCameraKbps, c.onHero),
      (t('مشاركة الشاشة', 'Screen share'), b.screenKbps, c.onHero.withValues(alpha: 0.62)),
      (t('كاميرات الطلاب', "Students' cameras"), b.studentTilesKbps, c.onHero.withValues(alpha: 0.38)),
      (t('الصوت', 'Audio'), b.audioKbps, c.onHero.withValues(alpha: 0.22)),
    ];
    final total = b.perViewerWithShareKbps;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.heroEnd(c.primary, 0.45)],
        ),
        boxShadow: c.primaryShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.heroGlass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.heroGlassBorder),
            ),
            child: Icon(Icons.network_check_rounded, color: c.onHero, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('بيانات كل مشاهد', 'Data per viewer'),
                  style: appText(16, w: FontWeight.w800, c: c.onHero), maxLines: 2),
              const SizedBox(height: 6),
              Row(children: [
                _GlassPill(
                  icon: away == 0 ? Icons.verified_rounded : Icons.tune_rounded,
                  label: away == 0
                      ? t('الإعداد المستحسن', 'The recommended setup')
                      : t('$away ${away == 1 ? 'اختلاف' : 'اختلافات'} عن المستحسن',
                          '$away ${away == 1 ? 'difference' : 'differences'} from recommended'),
                ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, runSpacing: 4, children: [
          Text('~${mbps(b.perViewerKbps)}', style: appText(34, w: FontWeight.w800, c: c.onHero, h: 1.0), textDirection: TextDirection.ltr),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Mbit/s', style: appText(14, w: FontWeight.w700, c: c.onHeroMuted)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          t('أثناء مشاركة الشاشة حتى ${mbps(total)} ميجابت/ث', 'Up to ${mbps(total)} Mbit/s while the screen is shared'),
          style: appText(13, w: FontWeight.w600, c: c.onHeroMuted),
        ),
        const SizedBox(height: 16),
        _StackedBar(parts: [for (final p in parts) (p.$2, p.$3)], track: c.heroGlass),
        const SizedBox(height: 12),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                  width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(p.$1, style: appText(12.5, w: FontWeight.w600, c: c.onHeroMuted))),
              Text(p.$2 == 0 ? '—' : '${mbps(p.$2)} Mbit/s', style: appText(12.5, w: FontWeight.w800, c: c.onHero), textDirection: TextDirection.ltr),
            ]),
          ),
        const SizedBox(height: 4),
        Text(
          t('حصة فيها $kPreviewStudents طالباً، ${b.camerasOn} كاميرا مفتوحة، يظهر منها ${b.studentTiles} على الشاشة.',
              'A class of $kPreviewStudents students, ${b.camerasOn} cameras on, ${b.studentTiles} of them on screen.'),
          style: appText(11.5, w: FontWeight.w500, c: c.onHeroFaint, h: 1.35),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _GlassStat(
                  icon: Icons.upload_rounded,
                  value: '${mbps(b.teacherUploadKbps)} Mbit/s',
                  label: t('رفع المعلم مع المشاركة', "Teacher's upload, sharing"))),
          const SizedBox(width: 10),
          Expanded(
              child: _GlassStat(
                  icon: Icons.schedule_rounded,
                  value: '~${hourLabel(b.perViewerHourMb)}',
                  label: t('ساعة لكل مشاهد', 'One hour per viewer'))),
        ]),
        const SizedBox(height: 10),
        _GlassStat(
          icon: draft.weakNetwork == 'audio_first' ? Icons.record_voice_over_rounded : Icons.signal_cellular_alt_2_bar_rounded,
          value: t('تحت ${mbps(b.weakNetworkFloorKbps)} ميجابت/ث', 'Below ${mbps(b.weakNetworkFloorKbps)} Mbit/s'),
          label: draft.weakNetwork == 'audio_first'
              ? t('يبقى الصوت مع زر «إظهار الفيديو»', 'Voice only, with a "Show video" button')
              : t('ينزل الفيديو إلى أدنى طبقة 180p', 'Video steps down to the 180p layer'),
          wide: true,
        ),
      ]),
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.parts, required this.track});

  final List<(int, Color)> parts;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Container(
          color: track,
          child: Row(children: [
            for (final p in parts)
              if (p.$1 > 0)
                Expanded(
                  flex: (p.$1 * 1000 ~/ (total == 0 ? 1 : total)).clamp(1, 1000),
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(end: 2),
                    color: p.$2,
                  ),
                ),
          ]),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.heroGlass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.heroGlassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c.onHero),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: appText(11.5, w: FontWeight.w700, c: c.onHero), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}

class _GlassStat extends StatelessWidget {
  const _GlassStat({required this.icon, required this.value, required this.label, this.wide = false});

  final IconData icon;
  final String value;
  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: appText(14, w: FontWeight.w800, c: c.onHero),
          textDirection: RegExp(r'^[~0-9]').hasMatch(value) ? TextDirection.ltr : null),
      const SizedBox(height: 2),
      Text(label, style: appText(11.5, w: FontWeight.w600, c: c.onHeroMuted, h: 1.3)),
    ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c.onHero),
        const SizedBox(width: 10),
        Expanded(child: text),
      ]),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c.isDark ? c.textDark : c.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(16, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text(subtitle, style: appText(12.5, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
          if (hint != null) _RecommendedPill(text: hint!, subtle: true),
        ]),
        const SizedBox(height: 10),
        child,
        if (help != null) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 15, color: c.textLight),
            const SizedBox(width: 6),
            Expanded(child: Text(help!, style: appText(12, w: FontWeight.w500, c: c.textMedium, h: 1.35))),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: subtle ? c.cardBg2 : c.successTint,
        borderRadius: BorderRadius.circular(999),
        border: subtle ? Border.all(color: c.divider) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: 13, color: c.success),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text ?? t('مستحسن', 'Recommended'),
              style: appText(11, w: FontWeight.w800, c: subtle ? c.textMedium : c.success),
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
      final side = box.maxWidth >= perCard * options.length + 12 * (options.length - 1);
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
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 10), cards[i]],
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: cards[i])],
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
    final r = BorderRadius.circular(16);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? c.primaryTint : c.cardBg2,
        borderRadius: r,
        border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: selected ? c.primary : c.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(option.icon, size: 18, color: selected ? c.onHero : (c.isDark ? c.textDark : c.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(option.title, style: appText(14, w: FontWeight.w800, c: c.textDark)),
            ),
          ),
          const SizedBox(width: 6),
          _Radio(selected: selected),
        ]),
        if (recommended) ...[
          const SizedBox(height: 8),
          const _RecommendedPill(),
        ],
        const SizedBox(height: 8),
        Text(option.body, style: appText(12.5, w: FontWeight.w500, c: c.textMedium, h: 1.4)),
        if (option.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in option.tags) _TagChip(tag: tag)]),
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
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.primary : c.surface,
        border: Border.all(color: selected ? c.primary : c.divider, width: 2),
      ),
      child: selected ? Icon(Icons.check_rounded, size: 14, color: c.onHero) : null,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pro ? Icons.add_circle_rounded : Icons.remove_circle_rounded, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(tag.label, style: appText(11.5, w: FontWeight.w700, c: c.textDark))),
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.cardBg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider),
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
                  borderRadius: BorderRadius.circular(10),
                  onTap: v == value ? null : () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? c.primary : null,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: v == value ? c.primaryShadow : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (v == recommended) ...[
                        Icon(Icons.star_rounded, size: 13, color: v == value ? c.onHero : c.success),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(label,
                            style: appText(13, w: FontWeight.w800, c: v == value ? c.onHero : c.textMedium),
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: c.cardBg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(caption, style: appText(11.5, w: FontWeight.w600, c: c.textLight, h: 1.3), maxLines: 2),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
              child: Text(valueLabel,
                  style: appText(13, w: FontWeight.w800, c: c.onHero), maxLines: 1, textDirection: TextDirection.ltr),
            ),
          ]),
          Row(children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: c.primary,
                  inactiveTrackColor: c.primaryTint,
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
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
            child: Row(children: [
              Icon(Icons.remove_rounded, size: 12, color: c.textLight),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(lowLabel,
                      style: appText(11, w: FontWeight.w600, c: c.textMedium),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(highLabel,
                    textAlign: TextAlign.end,
                    style: appText(11, w: FontWeight.w600, c: c.textMedium),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(Icons.add_rounded, size: 12, color: c.textLight),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: c.cardBg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider),
      ),
      child: AppSwitchTile(
        icon: icon,
        title: title,
        value: value,
        onChanged: onChanged,
        subtitleWidget: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle, style: appText(12, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
          if (value != recommended) ...[
            const SizedBox(height: 6),
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
      icon: const Icon(Icons.restart_alt_rounded, size: 18),
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
        border: Border(top: BorderSide(color: c.divider)),
        boxShadow: c.bottomNavShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 560;
          final statusRow = Row(children: [
            Icon(pending == 0 ? Icons.cloud_done_rounded : Icons.edit_note_rounded,
                size: 18, color: pending == 0 ? c.success : c.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(status,
                  style: appText(13, w: FontWeight.w700, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (narrow && discard != null) discard,
          ]);
          if (narrow) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              statusRow,
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: reset),
                const SizedBox(width: 8),
                SizedBox(width: 132, child: save),
              ]),
            ]);
          }
          return Row(children: [
            Expanded(child: statusRow),
            if (discard != null) ...[discard, const SizedBox(width: 4)],
            Flexible(child: reset),
            const SizedBox(width: 12),
            SizedBox(width: 180, child: save),
          ]);
        }),
      ),
    );
  }
}
