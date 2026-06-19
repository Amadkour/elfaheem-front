import 'package:flutter/cupertino.dart';

import '../../config/app_config.dart';

class ParentComponent extends StatelessWidget {
  const ParentComponent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (child.key case ValueKey(
      value: final v,
    ) when AppConfig.disableList.contains(v)) {
      return SizedBox.shrink();
    }
    return child;
  }
}
