import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../teacher/schedules/schedules_provider.dart';
import '../../../teacher/schedules/schedules_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
class StudentScheduleTab extends StatefulWidget {
  const StudentScheduleTab({super.key});

  @override
  State<StudentScheduleTab> createState() => StudentScheduleTabState();
}

class StudentScheduleTabState extends State<StudentScheduleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  StudentSchedulesProvider _prov = StudentSchedulesProvider();

  @override
  void dispose() {
    // _prov.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _prov.fetchOnce();
    });
  }

  @override
  Widget build(BuildContext context) {
    _prov = context.watch<StudentSchedulesProvider>();
    super.build(context);
    return BasePage(
        useWebCard: true,
        child: SafeArea(
            child:_prov.isLoading? Center(child:AppLoadingIndicator(),): ScheduleTabBody(
          provider: _prov,
          getData: () => _prov.data,
          onRefresh: _prov.fetch,
          title: 'my_calender'.tr,
          emptyMessage: 'empty_calender'.tr,
          getLastFetched: () => _prov.lastFetched,
        )));
  }
}
