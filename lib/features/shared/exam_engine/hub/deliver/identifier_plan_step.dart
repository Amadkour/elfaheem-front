import 'package:flutter/material.dart';

// Stub: replaced by its pack (back docs/exam_hub/CONTRACT.md, "Front wiring").
class IdentifierPlanStep extends StatelessWidget {
  const IdentifierPlanStep({super.key, required this.examId, required this.courseId, required this.onValid});

  final int examId;
  final int? courseId;
  final ValueChanged<bool> onValid;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
