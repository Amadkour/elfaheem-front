// In-app Help (workstream f3): the shapes of GET /api/v1/help/pages and /flows. Pure Dart, no widgets.
// A text on the wire is {"ar": "...", "en": "..."}; [HelpText] reads the one for the app language and falls back
// to the other one when it is empty.
library;

/// One bilingual text.
class HelpText {
  const HelpText(this.ar, this.en);
  final String ar, en;

  static const empty = HelpText('', '');

  factory HelpText.from(Object? v) {
    if (v is Map) return HelpText('${v['ar'] ?? ''}'.trim(), '${v['en'] ?? ''}'.trim());
    if (v is String) return HelpText(v, v);
    return empty;
  }

  /// The text in [lang] ('ar' | 'en'), the other language when this one is empty.
  String of(String lang) {
    final first = lang == 'ar' ? ar : en;
    return first.isNotEmpty ? first : (lang == 'ar' ? en : ar);
  }

  bool get isEmpty => ar.isEmpty && en.isEmpty;

  Map<String, String> toJson() => {'ar': ar, 'en': en};

  @override
  bool operator ==(Object other) => other is HelpText && other.ar == ar && other.en == en;

  @override
  int get hashCode => Object.hash(ar, en);
}

class HelpItem {
  const HelpItem({required this.label, required this.text});
  final HelpText label, text;

  factory HelpItem.fromJson(Map j) => HelpItem(label: HelpText.from(j['label']), text: HelpText.from(j['text']));
  Map<String, dynamic> toJson() => {'label': label.toJson(), 'text': text.toJson()};
}

class HelpSection {
  const HelpSection({required this.key, required this.title, this.body = HelpText.empty, this.items = const []});
  final String key;
  final HelpText title, body;
  final List<HelpItem> items;

  factory HelpSection.fromJson(Map j) => HelpSection(
        key: '${j['key'] ?? ''}',
        title: HelpText.from(j['title']),
        body: HelpText.from(j['body']),
        items: [for (final i in (j['items'] as List? ?? const [])) if (i is Map) HelpItem.fromJson(i)],
      );

  Map<String, dynamic> toJson() =>
      {'key': key, 'title': title.toJson(), 'body': body.toJson(), 'items': [for (final i in items) i.toJson()]};
}

class HelpTourStep {
  const HelpTourStep({required this.target, required this.text});
  final String target;
  final HelpText text;

  factory HelpTourStep.fromJson(Map j) => HelpTourStep(target: '${j['target'] ?? ''}', text: HelpText.from(j['text']));
  Map<String, dynamic> toJson() => {'target': target, 'text': text.toJson()};
}

/// One page's entry for the caller's role.
class HelpEntry {
  const HelpEntry({
    required this.pageId,
    required this.role,
    required this.title,
    required this.summary,
    this.sections = const [],
    this.tour = const [],
    this.version = 0,
  });

  final String pageId, role;
  final int version;
  final HelpText title, summary;
  final List<HelpSection> sections;
  final List<HelpTourStep> tour;

  bool get hasTour => tour.isNotEmpty;

  /// Whether there is anything to show (an entry with no text at all hides the button).
  bool get hasContent => !title.isEmpty || !summary.isEmpty || sections.isNotEmpty;

  factory HelpEntry.fromJson(Map j) => HelpEntry(
        pageId: '${j['page_id'] ?? ''}',
        role: '${j['role'] ?? ''}',
        version: (j['version'] as num?)?.toInt() ?? 0,
        title: HelpText.from(j['title']),
        summary: HelpText.from(j['summary']),
        sections: [for (final s in (j['sections'] as List? ?? const [])) if (s is Map) HelpSection.fromJson(s)],
        tour: [for (final s in (j['tour'] as List? ?? const [])) if (s is Map) HelpTourStep.fromJson(s)],
      );

  /// The body the admin PUTs: the full entry, both languages.
  Map<String, dynamic> toBody() => {
        'title': title.toJson(),
        'summary': summary.toJson(),
        'sections': [for (final s in sections) s.toJson()],
        'tour': [for (final s in tour) s.toJson()],
      };

  Map<String, dynamic> toJson() => {'page_id': pageId, 'role': role, 'version': version, ...toBody()};
}

class HelpFlowStep {
  const HelpFlowStep({required this.pageId, required this.action, required this.narration, this.durationS = 5});
  final String pageId;
  final HelpText action, narration;
  final int durationS;

  factory HelpFlowStep.fromJson(Map j) => HelpFlowStep(
        pageId: '${j['page_id'] ?? ''}',
        action: HelpText.from(j['action']),
        narration: HelpText.from(j['narration']),
        durationS: (j['duration_s'] as num?)?.toInt() ?? 5,
      );

  Map<String, dynamic> toJson() =>
      {'page_id': pageId, 'action': action.toJson(), 'narration': narration.toJson(), 'duration_s': durationS};
}

class HelpFlow {
  const HelpFlow({required this.key, required this.role, required this.title, this.steps = const []});
  final String key, role;
  final HelpText title;
  final List<HelpFlowStep> steps;

  factory HelpFlow.fromJson(Map j) => HelpFlow(
        key: '${j['key'] ?? ''}',
        role: '${j['role'] ?? ''}',
        title: HelpText.from(j['title']),
        steps: [for (final s in (j['steps'] as List? ?? const [])) if (s is Map) HelpFlowStep.fromJson(s)],
      );

  Map<String, dynamic> toBody() => {'title': title.toJson(), 'steps': [for (final s in steps) s.toJson()]};
}

/// The roles of the help catalogue (the server's `ROLES`).
const helpRoles = ['super_admin', 'org_admin', 'org_member', 'teacher', 'student', 'parent'];

/// The id of a role home's tab: the first tab is the home itself (`home.student`), the others `home.student/my_courses`.
String helpHomePageId(String homeId, String tabKey, {bool first = false}) =>
    first || tabKey.isEmpty ? homeId : '$homeId/$tabKey';
