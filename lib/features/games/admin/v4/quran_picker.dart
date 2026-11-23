// lib/features/games/admin/v4/quran_picker.dart — the Quran picker (Games v4 T65, CONTRACT §9, §10).
//
//   showQuranPicker(context, api)   a sheet: surah, ayah range, reciter, audio check → QuranPick(ref) or null
//   QuranPickerView                 the body over plain values (test/games/v4_admin_test.dart)
//
// The text is READ-ONLY: it is drawn in the Quran role (`quranTextStyle`) exactly as the server sends it and nothing
// in this file can change it. The result is a reference (`@quran:112:1`, `@quran:112:1-4`), never a copy of the text.
// Routes: GET /api/v1/admin/games/v4/quran/surahs, /quran/ayat?surah&from&to&reciter, /reciters.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart' show quranTextStyle;

/// What the picker hands back: the reference the item stores, plus a one-line label for the editor.
class QuranPick {
  const QuranPick({required this.surah, required this.from, required this.to, required this.label});
  final int surah;
  final int from;
  final int to;
  final String label;

  /// `@quran:112:1` or `@quran:112:1-4` (CONTRACT §3, §9); the source ref is the same without the prefix.
  String get tokens => to == from ? '@quran:$surah:$from' : '@quran:$surah:$from-$to';
  String get sourceRef => to == from ? '$surah:$from' : '$surah:$from-$to';
}

/// Plays one admin audio check; one player for the page. Returns false when the file did not start.
class AdminAudioCheck {
  AdminAudioCheck._();
  static final AdminAudioCheck instance = AdminAudioCheck._();
  AudioPlayer? _p;
  Timer? _stop;

  Future<bool> play(String url, {int startMs = 0, int? endMs, Duration cap = const Duration(seconds: 6)}) async {
    try {
      _stop?.cancel();
      final p = _p ??= AudioPlayer();
      await p.stop();
      await p.play(UrlSource(url), position: Duration(milliseconds: startMs));
      final len = endMs == null ? cap : Duration(milliseconds: (endMs - startMs).clamp(300, cap.inMilliseconds));
      _stop = Timer(len, () => p.stop());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _stop?.cancel();
    await _p?.stop();
  }
}

Future<QuranPick?> showQuranPicker(BuildContext context, {ItemsV4Api? api, QuranPick? initial}) =>
    showAppSheet<QuranPick>(context, (_) => _QuranPickerSheet(api: api ?? ItemsV4Api(), initial: initial));

class _QuranPickerSheet extends StatefulWidget {
  const _QuranPickerSheet({required this.api, this.initial});
  final ItemsV4Api api;
  final QuranPick? initial;

  @override
  State<_QuranPickerSheet> createState() => _QuranPickerSheetState();
}

class _QuranPickerSheetState extends State<_QuranPickerSheet> {
  List<Json> _surahs = [];
  List<Json> _reciters = [];
  List<Json> _ayat = [];
  int _surah = 1;
  int _from = 1;
  int _to = 1;
  String? _reciter;
  bool _loading = true;
  bool _loadingAyat = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _surah = i.surah;
      _from = i.from;
      _to = i.to;
    }
    _boot();
  }

  @override
  void dispose() {
    AdminAudioCheck.instance.stop();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final r = await Future.wait([widget.api.surahs(), widget.api.reciters()]);
      if (!mounted) return;
      _surahs = r[0];
      _reciters = r[1].where((x) => x['enabled'] != false).toList();
      _reciter = _reciters.cast<Json?>().firstWhere((x) => x!['is_default'] == true, orElse: () => null)?['key'] as String? ??
          (_reciters.isEmpty ? null : '${_reciters.first['key']}');
      _loading = false;
      setState(() {});
      await _loadAyat();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = itemErrorText(e); });
    }
  }

  int get _ayatCount {
    final s = _surahs.cast<Json?>().firstWhere((x) => x!['number'] == _surah, orElse: () => null);
    return jint(s?['ayat'], 7);
  }

  Future<void> _loadAyat() async {
    setState(() {
      _loadingAyat = true;
      _error = null;
    });
    try {
      final a = await widget.api.ayat(_surah, _from, _to, reciter: _reciter);
      if (mounted) setState(() { _ayat = a; _loadingAyat = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingAyat = false; _error = itemErrorText(e); });
    }
  }

  void _clamp() {
    final n = _ayatCount;
    _from = _from.clamp(1, n);
    _to = _to.clamp(_from, (_from + 7).clamp(1, n));
  }

  String _label() {
    final s = _surahs.cast<Json?>().firstWhere((x) => x!['number'] == _surah, orElse: () => null);
    final name = s == null ? '$_surah' : '${AppConfig.lang == 'ar' ? s['name_ar'] : s['name_en']}';
    return _to == _from ? '$name $_from' : '$name $_from-$_to';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(AppSpace.lg), child: AppListSkeleton(items: 3));
    return QuranPickerView(
      surahs: _surahs,
      reciters: _reciters,
      surah: _surah,
      from: _from,
      to: _to,
      reciter: _reciter,
      ayat: _ayat,
      loading: _loadingAyat,
      error: _error,
      onSurah: (v) {
        _surah = v;
        _from = 1;
        _to = 1;
        _clamp();
        _loadAyat();
      },
      onFrom: (v) {
        _from = v;
        if (_to < _from) _to = _from;
        _clamp();
        _loadAyat();
      },
      onTo: (v) {
        _to = v.clamp(_from, (_from + 7).clamp(1, _ayatCount));
        _loadAyat();
      },
      onReciter: (v) {
        _reciter = v;
        _loadAyat();
      },
      onPlay: (a) async {
        final au = jmap(a['audio']);
        final url = '${au['url'] ?? ''}';
        if (url.isEmpty) {
          showAppNotice(t('لا يوجد صوت لهذه الآية مع هذا القارئ', 'No audio for this ayah with this reciter'), error: true);
          return;
        }
        final ok = await AdminAudioCheck.instance.play(url, startMs: jint(au['start_ms']), endMs: au['end_ms'] == null ? null : jint(au['end_ms']));
        if (!ok) showAppNotice(t('تعذّر تشغيل الصوت', 'The audio did not play'), error: true);
      },
      onUse: () => Navigator.of(context).pop(QuranPick(surah: _surah, from: _from, to: _to, label: _label())),
    );
  }
}

class QuranPickerView extends StatelessWidget {
  const QuranPickerView({
    super.key,
    required this.surahs,
    required this.reciters,
    required this.surah,
    required this.from,
    required this.to,
    required this.reciter,
    required this.ayat,
    required this.onSurah,
    required this.onFrom,
    required this.onTo,
    required this.onReciter,
    required this.onPlay,
    required this.onUse,
    this.loading = false,
    this.error,
  });

  final List<Json> surahs;
  final List<Json> reciters;
  final int surah;
  final int from;
  final int to;
  final String? reciter;
  final List<Json> ayat;
  final bool loading;
  final String? error;
  final ValueChanged<int> onSurah;
  final ValueChanged<int> onFrom;
  final ValueChanged<int> onTo;
  final ValueChanged<String> onReciter;
  final ValueChanged<Json> onPlay;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final s = surahs.cast<Json?>().firstWhere((x) => x!['number'] == surah, orElse: () => null);
    final count = jint(s?['ayat'], 7);
    return AppSheetContent(
      title: t('اختيار من القرآن', 'Pick from the Quran'),
      children: [
        Row(children: [
          Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Text(t('النص للقراءة فقط ولا يُعدَّل.', 'The text is read-only and cannot be changed.'), style: AppType.meta(context))),
        ]),
        AppSpace.gapSm,
        EdSelect<int>(
          label: t('السورة', 'Surah'),
          value: surah,
          options: [for (final x in surahs) (jint(x['number']), '${x['number']} · ${ar ? x['name_ar'] : x['name_en']}')],
          onChanged: onSurah,
        ),
        AppSpace.gapSm,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AppNumberField(key: ValueKey('from$surah'), label: t('من الآية', 'From ayah'), initialValue: from, min: 1, max: count, onChanged: (v) => onFrom(v?.toInt() ?? 1))),
          AppSpace.gapSm,
          Expanded(child: AppNumberField(key: ValueKey('to$surah-$from'), label: t('إلى الآية', 'To ayah'), initialValue: to, min: from, max: (from + 7).clamp(1, count), onChanged: (v) => onTo(v?.toInt() ?? from))),
        ]),
        Text(t('حتى 8 آيات في الاختيار الواحد.', 'Up to 8 ayat in one pick.'), style: AppType.meta(context)),
        AppSpace.gapSm,
        if (reciters.isNotEmpty)
          EdSelect<String>(
            label: t('القارئ', 'Reciter'),
            value: reciter,
            options: [for (final r in reciters) ('${r['key']}', '${ar ? r['name_ar'] : r['name_en']}')],
            onChanged: onReciter,
          ),
        AppSpace.gapSm,
        if (error != null) AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger),
        if (loading)
          const AppListSkeleton(items: 2)
        else
          for (final a in ayat)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('${a['text'] ?? ''}  ﴿${a['ayah']}﴾',
                        textDirection: TextDirection.rtl, style: quranTextStyle(18, color: c.textDark)),
                  ),
                  AppSpace.gapXs,
                  Column(children: [
                    if (a['audio'] is Map)
                      AppIconButton(icon: Icons.play_arrow_rounded, tooltip: t('تجربة الصوت', 'Try the audio'), onPressed: () => onPlay(a))
                    else
                      Tooltip(
                        message: t('لا صوت لهذا القارئ', 'No audio for this reciter'),
                        child: Padding(padding: const EdgeInsets.all(AppSpace.sm), child: Icon(Icons.volume_off_rounded, size: AppIconSize.md, color: c.warning)),
                      ),
                  ]),
                ]),
              ),
            ),
        AppSpace.gapSm,
        AppButton.primary(label: t('استخدام هذا المقطع', 'Use this passage'), expand: true, onPressed: ayat.isEmpty ? null : onUse),
      ],
    );
  }
}
