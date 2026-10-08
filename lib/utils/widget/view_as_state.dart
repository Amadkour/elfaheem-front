// lib/core/view_as_state.dart
//
// Super-admin "view as" mode. While [targetId] is set, ApiClient adds `X-View-As: <id>` to every
// request (read-only on the server) and main.dart draws a banner with an exit button.
import 'package:flutter/foundation.dart';

class ViewAsState extends ChangeNotifier {
  ViewAsState._();
  static final ViewAsState instance = ViewAsState._();

  int? _id;
  String _name = '';
  String _role = '';

  /// Read by ApiClient on every request.
  static int? get targetId => instance._id;
  static bool get active => instance._id != null;

  String get name => _name;
  String get role => _role;

  void start({required int id, required String name, required String role}) {
    _id = id;
    _name = name;
    _role = role;
    notifyListeners();
  }

  void stop() {
    _id = null;
    notifyListeners();
  }
}
