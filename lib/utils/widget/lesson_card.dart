/// Reusable lesson card widget.

import 'package:flutter/material.dart';
import '../../models/lesson.dart';

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final VoidCallback? onTap;
  final bool isLocked;

  const LessonCard({
    Key? key,
    required this.lesson,
    this.onTap,
    this.isLocked = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isLocked
              ? Colors.grey.shade300
              : Theme.of(context).primaryColor,
          child: Icon(
            isLocked ? Icons.lock : Icons.play_arrow,
            color: Colors.white,
          ),
        ),
        title: Text(
          lesson.title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isLocked ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lesson.description != null)
              Text(
                lesson.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(lesson.formattedDuration),
          ],
        ),
        trailing: isLocked ? null : const Icon(Icons.chevron_right),
        onTap: isLocked ? null : onTap,
      ),
    );
  }
}