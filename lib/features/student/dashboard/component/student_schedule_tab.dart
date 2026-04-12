import 'package:flutter/cupertino.dart';

import '../../../teacher/schedules/schedules_provider.dart';
import '../../../teacher/schedules/schedules_screen.dart';

class StudentScheduleTab extends StatefulWidget {
  const StudentScheduleTab({super.key});

  @override
  State<StudentScheduleTab> createState() => StudentScheduleTabState();
}

class StudentScheduleTabState extends State<StudentScheduleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final StudentSchedulesProvider _prov = StudentSchedulesProvider();

  @override
  void dispose() {
    _prov.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await    _prov.fetchOnce();
    });

  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScheduleTabBody(
      provider: _prov,
      getData: () => _prov.data,
      onRefresh: _prov.fetch,
      title: 'جدولي الأسبوعي',
      emptyMessage: 'لا توجد مواعيد مضافة للكورسات بعد',
      getLastFetched:()=> _prov.lastFetched,
    );
  }
}
