import 'package:flutter/material.dart';
import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../courses/list/courses_list_screen.dart';

class SearchBarIcon extends StatelessWidget {
  const SearchBarIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CoursesListScreen(openSearch: true),
          ),
        ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.search_rounded,
                  color: AppTheme.textLight,
                  size: 22,
                ),
              ),
              Expanded(
                child: Text(
                  'search'.tr,
                  style: AppTheme.caption.copyWith(
                    fontSize: 14,
                    color: AppTheme.textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}