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

              // Filter button with gradient
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(left: 8, right: 8),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha:0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}