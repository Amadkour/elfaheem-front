import 'package:flutter/cupertino.dart';

import '../../config/app_config.dart';

/// Hides [child] when its feature id is in `AppConfig.disableList`.
///
/// The id is resolved in this order, so every style keeps working:
///   1. `featureKey: 'profile.logout'`            ← preferred
///   2. `ParentComponent(key: ValueKey('...'))`   ← its own key
///   3. `child.key` as `ValueKey('...')`          ← old convention
class ParentComponent extends StatelessWidget {
  const ParentComponent({super.key, this.featureKey, required this.child});

  final String? featureKey;
  final Widget child;

  static Object? _valueOf(Key? k) => k is ValueKey ? k.value : null;

  @override
  Widget build(BuildContext context) {
    final id = featureKey ?? _valueOf(key) ?? _valueOf(child.key);
    if (id != null && AppConfig.disableList.contains(id)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}