// lib/features/auth/register_levels_step.dart — the registration's "which levels" steps (Learning Hub F3, D-1311):
//
//   RegisterLevelsStep   a student's country, stage and grade (the catalog's ids), plus the hand-off note of a
//                        `contact_only` stage (university: the profile is saved, then WhatsApp is offered)
//   TeachingLevelsStep   a teacher's "stages and years I teach": any number of stages, each the whole stage or
//                        some of its grades
//   TeachingLevelsApi    GET|PUT /me/teaching-levels {levels: [{stage_id, grade_id|null}]}
//   PendingTeachingLevels  a teacher has no session during registration (the route needs a signed-in teacher), so the
//                        choice waits in SharedPreferences and is sent after the first sign-in
//
// Plain values in, callbacks out: the caller loads `EduCatalog` / `EduCountries` and passes the data.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// ── Student ──────────────────────────────────────────────────────────────────

/// The country (hidden with one country), then stage and grade. [onChanged] gets the country, stage id and grade id.
class RegisterLevelsStep extends StatelessWidget {
  const RegisterLevelsStep({
    super.key,
    required this.countries,
    required this.country,
    required this.stages,
    required this.onChanged,
    this.stageId,
    this.gradeId,
    this.trackKey,
    this.onTrack,
    this.errorText,
  });

  final List<EduCountry> countries;
  final String? country;
  final List<EduStage> stages;
  final int? stageId, gradeId;
  final String? trackKey;
  final void Function(String? country, int? stageId, int? gradeId) onChanged;
  final ValueChanged<String?>? onTrack;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    EduStage? stage;
    for (final s in stages) {
      if (s.id == stageId) stage = s;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (countries.length > 1) ...[
          EduCountryPicker(
            countries: {for (final c in countries) c.code: c.name},
            value: country,
            onChanged: (c) => onChanged(c, null, null),
          ),
          AppSpace.gapMd,
        ],
        EduStageGradePicker(
          stages: stages,
          stageId: stageId,
          gradeId: gradeId,
          trackKey: trackKey,
          onChanged: (s, g, tr) {
            onTrack?.call(tr);
            onChanged(country, s, g);
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(errorText!, style: AppType.meta(context).copyWith(color: context.colors.danger)),
          ),
        if (stage != null && stage.contactOnly) ...[
          AppSpace.gapSm,
          const ContactOnlyNote(),
        ],
      ],
    );
  }
}

/// "Your stage is handled by our team": shown under a `contact_only` stage.
class ContactOnlyNote extends StatelessWidget {
  const ContactOnlyNote({super.key});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_outlined, size: AppIconSize.md, color: context.colors.textMedium),
          AppSpace.gapXs,
          Expanded(
            child: Text(
              _t('طلاب هذه المرحلة يتواصلون معنا مباشرة. سنحفظ بياناتك ثم نفتح لك المحادثة.',
                  'Students at this level talk to us directly. We save your details, then open the chat for you.'),
              style: AppType.meta(context),
            ),
          ),
        ],
      );
}

/// After the profile is saved: a `contact_only` stage opens the country's WhatsApp through the one external-link
/// helper. False when the stage is not contact-only or the country has no number.
Future<bool> offerContactWhatsapp(EduCountry? country, EduStage? stage) async {
  if (stage == null || !stage.contactOnly) return false;
  final link = country?.whatsappLink;
  if (link == null) return false;
  return openExternalLink(link);
}

// ── Teacher ──────────────────────────────────────────────────────────────────

/// One taught level: a stage (grade null = the whole stage) or one grade of it.
class TeachingLevel {
  const TeachingLevel(this.stageId, [this.gradeId]);
  factory TeachingLevel.fromJson(Map<String, dynamic> j) {
    int? n(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return TeachingLevel(n(j['stage_id']) ?? 0, n(j['grade_id']));
  }
  final int stageId;
  final int? gradeId;
  Map<String, dynamic> toJson() => {'stage_id': stageId, 'grade_id': gradeId};

  @override
  bool operator ==(Object other) => other is TeachingLevel && other.stageId == stageId && other.gradeId == gradeId;
  @override
  int get hashCode => Object.hash(stageId, gradeId);
}

/// The stages and years a teacher teaches. A stage chip toggles the whole stage; a chosen stage with grades also shows
/// its grade chips (picking a grade drops the whole-stage row, and the other way round).
class TeachingLevelsStep extends StatelessWidget {
  const TeachingLevelsStep({super.key, required this.stages, required this.selected, required this.onChanged, this.errorText});

  final List<EduStage> stages;
  final List<TeachingLevel> selected;
  final ValueChanged<List<TeachingLevel>> onChanged;
  final String? errorText;

  bool _has(int stage, int? grade) => selected.contains(TeachingLevel(stage, grade));
  bool _stageTouched(int stage) => selected.any((l) => l.stageId == stage);

  void _toggleStage(EduStage s) {
    final rest = [for (final l in selected) if (l.stageId != s.id) l];
    onChanged(_stageTouched(s.id) ? rest : [...rest, TeachingLevel(s.id)]);
  }

  void _toggleGrade(EduStage s, EduGrade g) {
    final others = [for (final l in selected) if (!(l.stageId == s.id && (l.gradeId == null || l.gradeId == g.id))) l];
    onChanged(_has(s.id, g.id) ? others : [...others, TeachingLevel(s.id, g.id)]);
  }

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return Text(_t('المراحل الدراسية غير متاحة الآن', 'Study levels are not available right now'),
          style: AppType.meta(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFieldLabel(_t('المراحل والسنوات التي أدرّسها', 'Stages and years I teach')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in stages)
            AppChoiceChip(
              key: ValueKey('teach.stage.${s.id}'),
              label: s.name,
              selected: _stageTouched(s.id),
              onTap: () => _toggleStage(s),
            ),
        ]),
        for (final s in stages)
          if (_stageTouched(s.id) && s.hasGrades && s.grades.isNotEmpty) ...[
            AppSpace.gapMd,
            AppFieldLabel(s.name),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppChoiceChip(
                key: ValueKey('teach.all.${s.id}'),
                label: _t('كل الصفوف', 'All grades'),
                selected: _has(s.id, null),
                onTap: () => onChanged([
                  for (final l in selected)
                    if (l.stageId != s.id) l,
                  TeachingLevel(s.id),
                ]),
              ),
              for (final g in s.grades)
                AppChoiceChip(
                  key: ValueKey('teach.grade.${g.id}'),
                  label: g.name,
                  selected: _has(s.id, g.id),
                  onTap: () => _toggleGrade(s, g),
                ),
            ]),
          ],
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(errorText!, style: AppType.meta(context).copyWith(color: context.colors.danger)),
          ),
      ],
    );
  }
}

class TeachingLevelsApi {
  TeachingLevelsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _path = '/api/v1/me/teaching-levels';

  static List<TeachingLevel> parse(dynamic r) => r is Map && r['levels'] is List
      ? [for (final e in r['levels'] as List) if (e is Map) TeachingLevel.fromJson(Map<String, dynamic>.from(e))]
      : const [];

  Future<List<TeachingLevel>> load() async => parse(await _api.get(_path));

  Future<List<TeachingLevel>> save(List<TeachingLevel> levels) async =>
      parse(await _api.put(_path, body: {'levels': [for (final l in levels) l.toJson()]}));
}

/// The choice made while registering, kept until the teacher first signs in.
class PendingTeachingLevels {
  static const _key = 'pending_teaching_levels';

  static Future<void> store(List<TeachingLevel> levels) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (levels.isEmpty) {
        await p.remove(_key);
      } else {
        await p.setString(_key, jsonEncode([for (final l in levels) l.toJson()]));
      }
    } catch (_) {}
  }

  /// Send the stored choice (no-op without one). Kept when the network failed, dropped on any server answer.
  static Future<void> flush([TeachingLevelsApi? api]) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final levels = [for (final e in jsonDecode(raw) as List) TeachingLevel.fromJson(Map<String, dynamic>.from(e as Map))];
      try {
        await (api ?? TeachingLevelsApi()).save(levels);
      } on ApiException catch (e) {
        if (e.statusCode == 0) return;
      }
      await p.remove(_key);
    } catch (_) {}
  }
}
