// lib/features/games/learner/games_settings_sheet.dart — the games settings sheet (Games v4 T72): the reciter picker
// (name + a 3 s sample), the age band (editable only while it was asked, never read from the profile), and the About
// credits (Tanzil.net with its link, the hadith dataset, the reciters' sources: CONTRACT §13). Also the once-only age
// ask (`needs_age`). Plain-values widgets (`GamesSettingsBody`, `AgeBandChoices`) + `show…` functions that wire them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';

const kTanzilUrl = 'https://tanzil.net';

/// The four bands of CONTRACT §8 and their labels.
const kAgeBands = ['6-9', '10-13', '14-17', '18+'];

String ageBandLabel(String band) => switch (band) {
      '6-9' => t('٦ – ٩ سنوات', '6 to 9 years'),
      '10-13' => t('١٠ – ١٣ سنة', '10 to 13 years'),
      '14-17' => t('١٤ – ١٧ سنة', '14 to 17 years'),
      _ => t('١٨ سنة فأكثر', '18 and over'),
    };

/// "Quran text: Tanzil.net" with its link: visible under the Quran levels (the licence asks for the source and a link).
class TanzilCredit extends StatelessWidget {
  const TanzilCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      link: true,
      label: t('نص القرآن من Tanzil.net', 'Quran text from Tanzil.net'),
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('games.v4.tanzil'),
        borderRadius: AppRadius.chipAll,
        onTap: () => openExternalLink(kTanzilUrl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Center(
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, children: [
              Icon(Icons.menu_book_rounded, size: AppIconSize.sm, color: c.textLight),
              Text('${t('نص القرآن', 'Quran text')}: ', style: AppType.meta(context)),
              Text('Tanzil.net', style: AppType.meta(context).copyWith(color: c.primary, decoration: TextDecoration.underline)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The age-band choices (the once-only ask and the settings row).
class AgeBandChoices extends StatelessWidget {
  const AgeBandChoices({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final b in kAgeBands)
          AppChoiceChip(key: ValueKey('games.v4.age.$b'), label: ageBandLabel(b), selected: value == b, onTap: () => onChanged?.call(b)),
      ]);
}

/// The sheet's body with plain values.
class GamesSettingsBody extends StatelessWidget {
  const GamesSettingsBody({
    super.key,
    required this.reciters,
    required this.selectedReciter,
    this.onReciter,
    this.onSample,
    this.sampling,
    this.reciterError,
    this.ageBand,
    this.ageEditable = false,
    this.onAge,
  });

  /// Null while loading.
  final List<GameReciter>? reciters;
  final String? selectedReciter, reciterError;
  final ValueChanged<GameReciter>? onReciter, onSample;

  /// The key of the reciter whose sample plays now.
  final String? sampling;
  final String? ageBand;
  final bool ageEditable;
  final ValueChanged<String>? onAge;

  @override
  Widget build(BuildContext context) {
    final list = reciters;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(t('القارئ', 'Reciter'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('بصوته تسمع الآيات في ألعاب القرآن. اضغط زر التشغيل لتسمع ٣ ثوانٍ.', 'You hear the ayat in the Quran games in this voice. Tap play for a 3 second sample.'),
          style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      if (list == null)
        const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
      else if (list.isEmpty)
        Text(reciterError ?? t('لا قرّاء متاحون الآن', 'No reciters available now'), style: AppType.body(context))
      else
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _ReciterRow(
              key: ValueKey('games.v4.reciter.${r.key}'),
              r: r,
              selected: r.key == selectedReciter,
              playing: sampling == r.key,
              onTap: onReciter == null ? null : () => onReciter!(r),
              onSample: r.sample == null || onSample == null ? null : () => onSample!(r),
            ),
          ),
      const SizedBox(height: AppSpace.md),
      Text(t('الفئة العمرية', 'Age group'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      if (ageEditable)
        AgeBandChoices(value: ageBand, onChanged: onAge)
      else
        Text(ageBand == null ? t('غير محددة', 'Not set') : '${ageBandLabel(ageBand!)} · ${t('من بيانات حسابك', 'from your account')}',
            key: const ValueKey('games.v4.age.fixed'), style: AppType.body(context)),
      const SizedBox(height: AppSpace.md),
      Text(t('عن الألعاب', 'About'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      _Credit(
        icon: Icons.menu_book_rounded,
        title: t('نص القرآن: Tanzil.net', 'Quran text: Tanzil.net'),
        body: t('نص المصحف العثماني من tanzil.net (رخصة المشاع الإبداعي 3.0، بلا تعديل).', 'The Uthmani text from tanzil.net (Creative Commons Attribution 3.0, unchanged).'),
        action: const TanzilCredit(),
      ),
      _Credit(
        icon: Icons.format_quote_rounded,
        title: t('الحديث', 'Hadith'),
        body: t('صحيح البخاري وصحيح مسلم من مشروع fawazahmed0/hadith-api (مشاع عام).', 'Sahih al-Bukhari and Sahih Muslim from fawazahmed0/hadith-api (public domain).'),
      ),
      _Credit(
        icon: Icons.record_voice_over_rounded,
        title: t('التلاوات', 'Recitations'),
        body: t('مشاري العفاسي والحصري (المعلّم) من everyayah.com، ومختار الحاج من mp3quran.net. تُبثّ من مصدرها ولا تُعاد استضافتها، وحقوق التلاوة لأصحابها.',
            'Mishary Alafasy and Al-Husary (Muallim) from everyayah.com, Mukhtar Al-Haj from mp3quran.net. Streamed from their source, never re-hosted; the rights stay with the reciters.'),
      ),
    ]);
  }
}

class _Credit extends StatelessWidget {
  const _Credit({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: AppIconSize.md, color: context.colors.textLight),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.row(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(body, style: AppType.meta(context)),
              if (action != null) Align(alignment: AlignmentDirectional.centerStart, child: action!),
            ]),
          ),
        ]),
      );
}

class _ReciterRow extends StatelessWidget {
  const _ReciterRow({super.key, required this.r, required this.selected, required this.playing, this.onTap, this.onSample});

  final GameReciter r;
  final bool selected, playing;
  final VoidCallback? onTap, onSample;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = t(r.nameAr.isEmpty ? r.nameEn : r.nameAr, r.nameEn.isEmpty ? r.nameAr : r.nameEn);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: Material(
        color: selected ? Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
        ),
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.sm),
              child: Row(children: [
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? c.primary : c.textLight, size: AppIconSize.lg),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(name, style: AppType.row(context))),
                if (onSample != null)
                  IconButton(
                    key: ValueKey('games.v4.sample.${r.key}'),
                    tooltip: t('اسمع عيّنة', 'Hear a sample'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    icon: Icon(playing ? Icons.graphic_eq_rounded : Icons.play_circle_rounded, color: c.primary),
                    onPressed: onSample,
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The settings sheet: loads the reciters, saves the picks through [api].
Future<V4Profile?> showGamesSettingsSheet(BuildContext context, {required V4Profile profile, GamesV4Api? api, GameAudio? audio}) {
  return showAppSheet<V4Profile>(context, (ctx) => _SettingsHost(profile: profile, api: api ?? GamesV4Api(), audio: audio ?? GameAudio.instance));
}

class _SettingsHost extends StatefulWidget {
  const _SettingsHost({required this.profile, required this.api, required this.audio});
  final V4Profile profile;
  final GamesV4Api api;
  final GameAudio audio;

  @override
  State<_SettingsHost> createState() => _SettingsHostState();
}

class _SettingsHostState extends State<_SettingsHost> {
  late V4Profile _p = widget.profile;
  List<GameReciter>? _reciters;
  String? _selected, _sampling, _error;

  @override
  void initState() {
    super.initState();
    _selected = _p.reciterKey ?? _p.reciterEffective;
    widget.audio.loadReciters().then((l) {
      if (mounted) setState(() => _reciters = l.items);
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _reciters = const [];
          _error = gamesErrorText(e);
        });
      }
    });
  }

  Future<void> _pick(GameReciter r) async {
    final before = _selected;
    setState(() => _selected = r.key);
    try {
      _p = await widget.api.saveProfile(reciterKey: r.key);
    } catch (e) {
      if (!mounted) return;
      setState(() => _selected = before);
      showAppNotice(gamesErrorText(e), error: true);
    }
  }

  Future<void> _sample(GameReciter r) async {
    setState(() => _sampling = r.key);
    try {
      await widget.audio.playSample(r);
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted && _sampling == r.key) setState(() => _sampling = null);
  }

  Future<void> _age(String b) async {
    try {
      final p = await widget.api.saveProfile(ageBand: b);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) showAppNotice(gamesErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = _p.ageSource == null || _p.ageSource == 'asked';
    return AppSheetContent(
      title: t('إعدادات الألعاب', 'Games settings'),
      headerTrailing: const HelpInfoButton(pageId: 'games.settings'),
      icon: Icons.tune_rounded,
      children: [
        GamesSettingsBody(
        reciters: _reciters,
        reciterError: _error,
        selectedReciter: _selected,
        onReciter: _pick,
        onSample: _sample,
        sampling: _sampling,
        ageBand: _p.ageBand,
        ageEditable: editable,
        onAge: _age,
        ),
      ],
    );
  }
}

/// The once-only age ask (`needs_age`): the band only. Returns the saved profile, or null when dismissed.
Future<V4Profile?> showAgeBandAsk(BuildContext context, {GamesV4Api? api}) {
  final a = api ?? GamesV4Api();
  return showAppSheet<V4Profile>(context, (ctx) {
    return AppSheetContent(
      title: t('كم عمرك؟', 'How old are you?'),
      icon: Icons.cake_rounded,
      children: [Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(t('نختار لك ألعابًا ومظهرًا يناسبان عمرك. نسألك مرة واحدة فقط.', 'We pick games and a look that fit your age. We ask only once.'),
            style: AppType.body(ctx)),
        const SizedBox(height: AppSpace.md),
        AgeBandChoices(
          value: null,
          onChanged: (b) async {
            try {
              final p = await a.saveProfile(ageBand: b);
              if (ctx.mounted) Navigator.of(ctx).pop(p);
            } catch (e) {
              showAppNotice(gamesErrorText(e), error: true);
            }
          },
        ),
      ])],
    );
  });
}
