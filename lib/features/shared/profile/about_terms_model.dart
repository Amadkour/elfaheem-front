// ─────────────────────────────────────────────────────────────────────────────
// features/shared/about/about_terms_model.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── AppInfo ───────────────────────────────────────────────────────────────────

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

// ── AppStat ───────────────────────────────────────────────────────────────────

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

// ── AppFeature ────────────────────────────────────────────────────────────────

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

// ── TeamMember ────────────────────────────────────────────────────────────────

class TeamMemberModel {
  final int id;
  final String name;
  final String role;
  final String? emoji;
  final String? imageUrl;
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

// ── ContactInfo ───────────────────────────────────────────────────────────────

class ContactInfoModel {
  final int id;
  final String type; // email / phone / address / website / whatsapp
  final String value;
  final String? iconName;
  final int order;

  const ContactInfoModel({
    required this.id,
    required this.type,
    required this.value,
    this.iconName,
    required this.order,
  });

  factory ContactInfoModel.fromJson(Map<String, dynamic> j) => ContactInfoModel(
        id: j['id'],
        type: j['type'] ?? 'general',
        value: j['value'] ?? '',
        iconName: j['icon_name'],
        order: j['order'] ?? 0,
      );
}

// ── AboutPage (combined) ──────────────────────────────────────────────────────

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

// ── TermsMeta ─────────────────────────────────────────────────────────────────

class TermsMetaModel {
  final int id;
  final String lastUpdated;
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

// ── TermsSection ──────────────────────────────────────────────────────────────

class TermsSectionModel {
  final int id;
  final String iconName;
  final String title;
  final String body;
  final int order;
  bool isRead;

  TermsSectionModel({
    required this.id,
    required this.iconName,
    required this.title,
    required this.body,
    required this.order,
    this.isRead = false,
  });

  void toggle() {
    isRead = !isRead;
  }

  factory TermsSectionModel.fromJson(Map<String, dynamic> j) =>
      TermsSectionModel(
        id: j['id'],
        iconName: j['icon_name'] ?? 'description',
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        order: j['order'] ?? 0,
      );
}

// ── TermsPage (combined) ──────────────────────────────────────────────────────

class TermsPageModel {
  final TermsMetaModel? meta;
  final List<TermsSectionModel> sections;

  const TermsPageModel({
    this.meta,
    this.sections = const [],
  });

  factory TermsPageModel.fromJson(Map<String, dynamic> j) => TermsPageModel(
        meta: j['meta'] != null
            ? TermsMetaModel.fromJson(j['meta'] as Map<String, dynamic>)
            : null,
        sections: (j['sections'] as List? ?? [])
            .map((e) => TermsSectionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
