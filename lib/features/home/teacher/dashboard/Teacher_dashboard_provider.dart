import 'package:flutter_education_app/core/base_provider.dart';

class TeacherDashboardProvider extends BaseProvider{

  int currentTab=0;
  void onChangeTab(int newTab){
     currentTab=newTab;
     notifyListeners();
  }
}