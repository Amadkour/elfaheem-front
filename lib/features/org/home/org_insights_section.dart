// lib/features/org/home/org_insights_section.dart
//
// The Insights slot of the organization home (D-103, spec §4) — drawn only when the dashboard says `can_insights`,
// placed by `layout` (orgHomeOrder). A placeholder for now: it draws nothing until Stage 4 fills it (GET …/insights,
// the kill switch `org.insights`).
library;

import 'package:flutter/widgets.dart';

/// The section's rough height in rows for the desktop split (orgHomeColumns). 0 while it draws nothing, so the
/// other two sections share the columns; raise it when the section has content.
const int kOrgInsightsWeight = 0;

class OrgInsightsSection extends StatelessWidget {
  const OrgInsightsSection({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
