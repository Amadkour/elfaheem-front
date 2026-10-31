// lib/features/org/home/org_dept_courses.dart
//
// The "Courses" tab of a department page (D-103 `departments[].tabs` key `courses`): the organization's courses that
// belong to this department — GET …/courses?dept_id= (the server checks `courses.view` in that department). A calm
// list: name · teacher · students; tap → the course profile. Read-only here (adding a course stays on the Academics
// page, which knows programs and terms).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppEmpty, AppListSkeleton, AppRefresh, appInk;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show ErrorRetry, asInt, asMap, asMapList, t;
import '../../shared/course_profile/course_profile_screen.dart' show openCourseProfile;
import '../org_providers.dart';
import 'org_home_tasks.dart' show OrgRowsCard;

class OrgDeptCoursesTab extends StatefulWidget {
  const OrgDeptCoursesTab({super.key, required this.deptId});
  final int deptId;

  @override
  State<OrgDeptCoursesTab> createState() => _OrgDeptCoursesTabState();
}

class _OrgDeptCoursesTabState extends State<OrgDeptCoursesTab> {
  List<Map<String, dynamic>>? _rows;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    try {
      final r = await ApiClient().get('${s.base}/courses', queryParams: {'dept_id': widget.deptId, 'size': 100});
      if (!mounted) return;
      final m = asMap(r);
      setState(() {
        _rows = asMapList(m['items']);
        _total = asInt(m['total'], _rows!.length);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiException.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      return _error != null ? ErrorRetry(message: _error!, onRetry: _load) : const AppListSkeleton(items: 4);
    }
    return OrgDeptCoursesList(rows: rows, total: _total, onRefresh: _load, onOpen: (row) => openCourseProfile(context, asInt(row['id'])));
  }
}

/// Plain values (the layout harness pumps it).
class OrgDeptCoursesList extends StatelessWidget {
  const OrgDeptCoursesList({super.key, required this.rows, required this.total, required this.onRefresh, this.onOpen});
  final List<Map<String, dynamic>> rows;
  final int total;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic> row)? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppRefresh(
      onRefresh: onRefresh,
      child: ListView(padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xxl), children: [
        if (rows.isEmpty)
          AppEmpty(
            icon: Icons.menu_book_outlined,
            title: t('لا مقررات في هذا القسم بعد', 'No courses in this department yet'),
            message: t('تظهر هنا المقررات المرتبطة بالقسم.', 'Courses linked to this department show up here.'),
          )
        else ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
            child: Text(total == 1 ? t('مقرر واحد', '1 course') : t('$total مقرر', '$total courses'), style: AppType.meta(context)),
          ),
          OrgRowsCard(children: [
            for (final r in rows)
              InkWell(
                onTap: onOpen == null ? null : () => onOpen!(r),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
                        child: Icon(Icons.menu_book_rounded, size: 20, color: appInk(context, c.primary)),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(t('${r['name_ar'] ?? r['name_en'] ?? ''}', '${r['name_en'] ?? r['name_ar'] ?? ''}'),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                          const SizedBox(height: AppSpace.xxs / 2),
                          Text(_meta(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.textLight, size: 22),
                    ]),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  static String _meta(Map<String, dynamic> r) {
    final teacher = '${asMap(r['teacher'])['name'] ?? ''}'.trim();
    final n = asInt(r['students']);
    return [
      teacher.isEmpty ? t('بلا مدرس بعد', 'No teacher yet') : teacher,
      n == 1 ? t('طالب واحد', '1 student') : t('$n طالب', '$n students'),
      if (r['is_published'] != true) t('مسودة', 'Draft'),
    ].join(' · ');
  }
}
