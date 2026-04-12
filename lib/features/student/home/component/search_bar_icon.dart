import 'package:flutter/cupertino.dart';
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
        // Tap opens full search screen
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const CoursesListScreen(openSearch: true)),
        ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.search_rounded, color: AppTheme.textLight),
              ),
              Text('search'.tr, style: AppTheme.caption.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
