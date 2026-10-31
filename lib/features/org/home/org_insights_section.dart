// lib/features/org/home/org_insights_section.dart
//
// The Insights slot of the organization home (D-103, spec §4) — drawn only when the dashboard says `can_insights`,
// placed by `layout` (orgHomeOrder). The section itself lives in ../insights/org_insights_section.dart (GET …/insights
// after the home's first frame, the kill switch `org.insights`); this file names its weight in the desktop split.
library;

export '../insights/org_insights_section.dart' show OrgInsightsSection, openOrgInsightLink, orgInsightsEnabled;

/// The section's rough height in rows for the desktop split (orgHomeColumns): the period chips, two rows of cards and
/// a few suggestions — about the height of "Needs your attention" with five rows plus the departments.
const int kOrgInsightsWeight = 10;
