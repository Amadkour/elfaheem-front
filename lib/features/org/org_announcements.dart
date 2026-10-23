// lib/features/org/org_announcements.dart
//
// Announcements with engagement tracking (point 17): the member-facing feed (views, like/dislike, deep-link
// click-through) and the per-announcement analytics for org admins / department managers.
//
// Contract used by other screens (keep it stable):
//   OrgAnnouncementFeed(orgId: id, limit: 3, compact: true)   // embeddable feed, e.g. on the member dashboard
library;

import 'package:flutter/material.dart';

/// Embeddable announcement feed of one organization for the signed-in member.
/// [limit] caps the items shown (null = all, with paging); [compact] is the dashboard-card variant.
class OrgAnnouncementFeed extends StatelessWidget {
  const OrgAnnouncementFeed({super.key, required this.orgId, this.limit, this.compact = false, this.deptId});
  final int orgId;
  final int? deptId;
  final int? limit;
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // filled in by the announcements workstream
}
