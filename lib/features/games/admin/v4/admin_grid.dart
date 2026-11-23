// lib/features/games/admin/v4/admin_grid.dart — the Games admin pages' card grid (G3 visual pass): one column on a
// phone or a narrow window, two side by side once the body is as wide as a reading page, so a desktop window shows
// cards in columns instead of one stretched phone column. Each row is as tall as its tallest card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';

class GamesCardGrid extends StatelessWidget {
  const GamesCardGrid({super.key, required this.children, this.gap = AppSpace.sm});

  final List<Widget> children;
  final double gap;

  static int columnsFor(double width) => width >= AppWidth.reading.max ? 2 : 1;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = columnsFor(box.maxWidth);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          if (cols == 1) {
            rows.add(children[i]);
            continue;
          }
          final cells = <Widget>[];
          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(SizedBox(width: gap));
            cells.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()));
          }
          rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      });
}
