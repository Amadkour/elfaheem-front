// lib/features/teacher/data_lab/data_lab_entry_cards.dart
// Drop-in entry points:
//   • DataLabEntryCard           – put it in the TEACHER's course profile  (opens DataLabScreen)
//   • MyAnalyticsProfileCard     – put it in the STUDENT's course page / profile (opens the student's profile)
// Both hide themselves when the admin switched Data Lab off for that course.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../student/analysis/student_analytics_profile_screen.dart';
import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBlockColors, AppBlockTone, AppIconSize, AppRadius, AppSpace, AppTouch, AppType;

class DataLabEntryCard extends StatefulWidget {
  const DataLabEntryCard({super.key, required this.courseId, required this.courseTitle});

  final int courseId;
  final String courseTitle;

  @override
  State<DataLabEntryCard> createState() => _DataLabEntryCardState();
}

class _DataLabEntryCardState extends State<DataLabEntryCard> {
  late final Future<DlConfig> _cfg = DataLabApi().config(courseId: widget.courseId).catchError((_) => const DlConfig());

  @override
  Widget build(BuildContext context) => FutureBuilder<DlConfig>(
    future: _cfg,
    builder: (context, snap) {
      if (snap.hasData && !snap.data!.enabled) return const SizedBox.shrink();
      return ParentComponent(
        featureKey: 'data_lab.entry',
        child: _EntryTile(
          icon: Icons.science_rounded,
          title: 'dl_title'.tr,
          sub: 'dl_entry_sub'.tr,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => deferredDataLab(courseId: widget.courseId, courseTitle: widget.courseTitle)),
          ),
        ),
      );
    },
  );
}

class MyAnalyticsProfileCard extends StatefulWidget {
  const MyAnalyticsProfileCard({super.key, this.courseId});

  final int? courseId;

  @override
  State<MyAnalyticsProfileCard> createState() => _MyAnalyticsProfileCardState();
}

class _MyAnalyticsProfileCardState extends State<MyAnalyticsProfileCard> {
  late final Future<DlConfig> _cfg = DataLabApi().config(courseId: widget.courseId).catchError((_) => const DlConfig());

  @override
  Widget build(BuildContext context) => FutureBuilder<DlConfig>(
    future: _cfg,
    builder: (context, snap) {
      if (snap.hasData && !snap.data!.studentView) return const SizedBox.shrink();
      return ParentComponent(
        featureKey: 'data_lab.my_profile',
        child: _EntryTile(
          icon: Icons.insights_rounded,
          title: 'dl_my_profile'.tr,
          sub: 'dl_my_profile_sub'.tr,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent(courseId: widget.courseId)),
          ),
        ),
      );
    },
  );
}

/// A paper card with the Data Lab's sky tile (an information surface), the title in the editorial section role.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.title, required this.sub, required this.onTap});

  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DlCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(color: c.blockSky, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Icon(icon, color: AppBlockColors.of(context, AppBlockTone.sky).accentInk(c.primary), size: AppIconSize.lg),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(sub, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
      ]),
    );
  }
}
