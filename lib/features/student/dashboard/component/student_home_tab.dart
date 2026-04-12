import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/features/student/home/home_screen.dart';

import '../../../teacher/schedules/schedules_provider.dart';
import '../../../teacher/schedules/schedules_screen.dart';

class StudentHomeTab extends StatefulWidget {
  const StudentHomeTab({super.key});

  @override
  State<StudentHomeTab> createState() => StudentScheduleTabState();
}

class StudentScheduleTabState extends State<StudentHomeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final HomeProvider _prov = HomeProvider();

  @override
  void dispose() {
    _prov.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _prov.init(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const HomeScreen();
  }
}
