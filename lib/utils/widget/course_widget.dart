
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/course.dart';
import '../helpers.dart';

class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback? onTap;
  final bool showProgress;
  final bool isInstructorView;

  const CourseCard({
    super.key,
    required this.course,
    this.onTap,
    this.showProgress = false,
    this.isInstructorView = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            AspectRatio(
              aspectRatio: 16 / 9,
              child: course.thumbnailUrl != null
                  ? CachedNetworkImage(
                imageUrl: course.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.school, size: 50, color: Colors.grey),
                ),
              )
                  : Container(
                color: Theme.of(context).primaryColor.withValues(alpha:0.1),
                child: Icon(
                  Icons.school,
                  size: 50,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),

            // Course Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    course.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Description
                  if (course.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      course.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Footer row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Price
                      Text(
                        course.isFree ? 'FREE' : Helpers.formatCurrency(course.price),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: course.isFree ? Colors.green : Theme.of(context).primaryColor,
                        ),
                      ),

                      // Status badges
                      Row(
                        children: [
                          if (!course.isPublished)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: const Text('Draft', style: TextStyle(fontSize: 12)),
                                backgroundColor: Colors.orange.shade100,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          if (isInstructorView)
                            const Icon(Icons.edit, size: 20),
                        ],
                      ),
                    ],
                  ),

                  // Progress bar (for enrolled courses)
                  if (showProgress) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: 0.3, // TODO: Get actual progress
                        minHeight: 6,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '30% Complete', // TODO: Get actual progress
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}