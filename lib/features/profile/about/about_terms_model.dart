class AppInfoModel {
  final int id;
  final String name;
  final String? tagline;
  final String? mission;
  final String? logoUrl;

  const AppInfoModel({
    required this.id,
    required this.name,
    this.tagline,
    this.mission,
    this.logoUrl,
  });

  factory AppInfoModel.fromJson(Map<String, dynamic> j) => AppInfoModel(
    id: j['id'],
    name: j['name'] ?? '',
    tagline: j['tagline'],
    mission: j['mission'],
    logoUrl: j['logo_url'],
  );
}

class AppStatModel {
  final int id;
  final String value;
  final String label;
  final int order;

  const AppStatModel({
    required this.id,
    required this.value,
    required this.label,
    required this.order,
  });

  factory AppStatModel.fromJson(Map<String, dynamic> j) => AppStatModel(
    id: j['id'],
    value: j['value'] ?? '',
    label: j['label'] ?? '',
    order: j['order'] ?? 0,
  );
}

class AppFeatureModel {
  final int id;
  final String iconName;
  final String title;
  final String? description;
  final int order;

  const AppFeatureModel({
    required this.id,
    required this.iconName,
    required this.title,
    this.description,
    required this.order,
  });

  factory AppFeatureModel.fromJson(Map<String, dynamic> j) => AppFeatureModel(
    id: j['id'],
    iconName: j['icon_name'] ?? 'star',
    title: j['title'] ?? '',
    description: j['description'],
    order: j['order'] ?? 0,
  );
}

class TeamMemberModel {
  final int id;
  final String name;
  final String role;
  final String? emoji;
  final String? imageUrl;   // MinIO public URL
  final int order;

  const TeamMemberModel({
    required this.id,
    required this.name,
    required this.role,
    this.emoji,
    this.imageUrl,
    required this.order,
  });

  factory TeamMemberModel.fromJson(Map<String, dynamic> j) => TeamMemberModel(
    id: j['id'],
    name: j['name'] ?? '',
    role: j['role'] ?? '',
    emoji: j['emoji'],
    imageUrl: j['image_url'],
    order: j['order'] ?? 0,
  );
}

class ContactInfoModel {
  final int id;
  final String type;     // email / phone / address / website / whatsapp
  final String value;
  final String? label;   // resolved from label_ar / label_en on the server
  final String? iconName;
  final int order;

  const ContactInfoModel({
    required this.id,
    required this.type,
    required this.value,
    this.label,
    this.iconName,
    required this.order,
  });

  factory ContactInfoModel.fromJson(Map<String, dynamic> j) => ContactInfoModel(
    id: j['id'],
    type: j['type'] ?? 'general',
    value: j['value'] ?? '',
    label: j['label'],
    iconName: j['icon_name'],
    order: j['order'] ?? 0,
  );
}

class AboutPageModel {
  final AppInfoModel? info;
  final List<AppStatModel> stats;
  final List<AppFeatureModel> features;
  final List<TeamMemberModel> team;
  final List<ContactInfoModel> contacts;

  const AboutPageModel({
    this.info,
    this.stats = const [],
    this.features = const [],
    this.team = const [],
    this.contacts = const [],
  });

  factory AboutPageModel.fromJson(Map<String, dynamic> j) => AboutPageModel(
    info: j['info'] != null
        ? AppInfoModel.fromJson(j['info'] as Map<String, dynamic>)
        : null,
    stats: (j['stats'] as List? ?? [])
        .map((e) => AppStatModel.fromJson(e as Map<String, dynamic>))
        .toList(),
    features: (j['features'] as List? ?? [])
        .map((e) => AppFeatureModel.fromJson(e as Map<String, dynamic>))
        .toList(),
    team: (j['team'] as List? ?? [])
        .map((e) => TeamMemberModel.fromJson(e as Map<String, dynamic>))
        .toList(),
    contacts: (j['contacts'] as List? ?? [])
        .map((e) => ContactInfoModel.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ── Terms ─────────────────────────────────────────────────────────────────────

class TermsMetaModel {
  final int id;
  final String lastUpdated;   // already resolved to the correct language
  final String? version;

  const TermsMetaModel({
    required this.id,
    required this.lastUpdated,
    this.version,
  });

  factory TermsMetaModel.fromJson(Map<String, dynamic> j) => TermsMetaModel(
    id: j['id'],
    lastUpdated: j['last_updated'] ?? '',
    version: j['version'],
  );
}

class TermsSectionModel {
  final int id;
  final String iconName;
  final String title;   // already resolved to the correct language
  final String body;    // already resolved to the correct language
  final int order;
  bool accept=false;
  void toggle(){
    accept=!accept;
  }
   TermsSectionModel({
    required this.id,
    required this.iconName,
    required this.title,
    required this.body,
    required this.order,
  });

  factory TermsSectionModel.fromJson(Map<String, dynamic> j) =>
      TermsSectionModel(
        id: j['id'],
        iconName: j['icon_name'] ?? 'description',
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        order: j['order'] ?? 0,
      );
}

class TermsPageModel {
  final TermsMetaModel? meta;
  final List<TermsSectionModel> sections;

  /// The legal documents (D-308, GET /api/v1/app-content/legal/{doc}) also carry these; the older /terms does not.
  final String title;
  final String intro;
  final List<String> highlights;
  final String url;
  final String contactEmail;

  const TermsPageModel({
    this.meta,
    this.sections = const [],
    this.title = '',
    this.intro = '',
    this.highlights = const [],
    this.url = '',
    this.contactEmail = '',
  });

  /// A legal document in one language: `{doc, version, effective_label, title, intro, highlights, sections: [{id,
  /// icon_name, title, body, order}], url, contact_email}` (string section ids become their position).
  factory TermsPageModel.fromLegal(Map<String, dynamic> j) {
    final raw = j['sections'] is List ? j['sections'] as List : const [];
    final sections = <TermsSectionModel>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final title = '${e['title'] ?? ''}'.trim();
      final body = '${e['body'] ?? ''}'.trim();
      if (title.isEmpty && body.isEmpty) continue;
      sections.add(TermsSectionModel(
        id: sections.length + 1,
        iconName: '${e['icon_name'] ?? 'description'}',
        title: title,
        body: body,
        order: sections.length + 1,
      ));
    }
    final label = '${j['effective_label'] ?? j['effective_date'] ?? ''}';
    final version = '${j['version'] ?? ''}';
    return TermsPageModel(
      meta: label.isEmpty && version.isEmpty
          ? null
          : TermsMetaModel(id: 0, lastUpdated: label, version: version.isEmpty ? null : version),
      sections: sections,
      title: '${j['title'] ?? ''}',
      intro: '${j['intro'] ?? ''}',
      highlights: [
        for (final h in (j['highlights'] is List ? j['highlights'] as List : const []))
          if ('$h'.trim().isNotEmpty) '$h'.trim(),
      ],
      url: '${j['url'] ?? ''}',
      contactEmail: '${j['contact_email'] ?? ''}',
    );
  }

  factory TermsPageModel.fromJson(Map<String, dynamic> j) => TermsPageModel(
    meta: j['meta'] != null
        ? TermsMetaModel.fromJson(j['meta'] as Map<String, dynamic>)
        : null,
    sections: (j['sections'] as List? ?? [])
        .map((e) =>
        TermsSectionModel.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}