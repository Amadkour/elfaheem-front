// Two `AppNumberField`s on one line when both have room for their two buttons, one above the other when they do not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

class NumberPair extends StatelessWidget {
  const NumberPair({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  /// Below this each field would keep a sliver between its buttons.
  static const double minRow = 420;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < minRow) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            first,
            const SizedBox(height: AppSpace.sm),
            second,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: second),
        ]);
      });
}
