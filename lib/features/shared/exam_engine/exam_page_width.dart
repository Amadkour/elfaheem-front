// exam_page_width.dart — a scrolling exam page on a width role, with the page itself still the scrollable.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';

/// [builder] gets the side padding that centres a page's content on [width]; never less than the phone gutter.
/// The padding goes on the list, so a mouse wheel over the empty sides still scrolls it.
class ExamPageWidth extends StatelessWidget {
  const ExamPageWidth({super.key, required this.width, required this.builder});

  final AppWidth width;
  final Widget Function(double side) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => builder(math.max(AppSpace.md, (box.maxWidth - width.max) / 2)),
      );
}
