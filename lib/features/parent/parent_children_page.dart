// lib/features/parent/parent_children_page.dart — the linked children of the parent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';

class ParentChildrenPage extends StatefulWidget {
  const ParentChildrenPage({super.key, required this.onOpenLinkTab});

  final VoidCallback onOpenLinkTab;

  @override
  State<ParentChildrenPage> createState() => _ParentChildrenPageState();
}

class _ParentChildrenPageState extends State<ParentChildrenPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ParentLinkProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentLinkProvider>();
    final c = context.colors;

    if (p.hasError && p.children.isEmpty) {
      return PlError(p.errorMessage ?? '', onRetry: p.loadAll);
    }
    if (p.children.isEmpty) {
      return PlEmpty(
        p.isLoading ? 'pl_loading'.tr : 'pl_no_children'.tr,
        icon: Icons.family_restroom_rounded,
        action: p.isLoading
            ? null
            : FilledButton.icon(
                onPressed: widget.onOpenLinkTab,
                icon: const Icon(Icons.link_rounded),
                label: Text('pl_link_child'.tr)),
      );
    }

    return RefreshIndicator(
      onRefresh: p.loadAll,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final ch in p.children)
            PlCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ParentChildReportScreen(
                      studentId: ch['id'] as int, studentName: '${ch['name']}'))),
              child: Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.primary.withAlpha(25),
                      border: Border.all(color: c.primary, width: 1.5)),
                  child: '${ch['image_url'] ?? ''}'.isNotEmpty
                      ? ClipOval(child: AppNetworkImage(url: '${ch['image_url']}', heroTag: 'child-${ch['id']}'))
                      : Icon(Icons.person_rounded, color: c.primary, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${ch['name']}', style: c.h2.copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('${'pl_linked_at'.tr} ${plDateTime(ch['linked_at'])}', style: c.caption),
                  ]),
                ),
                Icon(Icons.query_stats_rounded, color: c.primary),
              ]),
            ),
        ],
      ),
    );
  }
}
