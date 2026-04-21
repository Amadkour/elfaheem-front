import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/category/categories_screen.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_theme.dart';
import '../../../category/categories_provider.dart';

class CategoriesRow extends StatelessWidget {
  const CategoriesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoriesProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingCategory) {
          return const SizedBox(
            height: 112,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                strokeWidth: 2.5,
              ),
            ),
          );
        }

        if (provider.categories.isEmpty) {
          return const SizedBox(
            height: 112,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined,
                      size: 36, color: AppTheme.textLight),
                  SizedBox(height: 8),
                  Text('لا توجد أقسام', style: AppTheme.caption),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 112,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: provider.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final cat = provider.categories[i];
              final isSelected = provider.selectedCategoryId == cat.id;

              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const CategoriesScreen()),
                ),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryLight
                            : AppTheme.cardBg,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                            color: AppTheme.primary, width: 2)
                            : Border.all(
                            color: Colors.transparent, width: 2),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color:
                            AppTheme.primary.withValues(alpha:0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          )
                        ]
                            : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.07),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: cat.imageUrl.isNotEmpty
                          ? ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Image.network(
                            cat.imageUrl,
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.accent2,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.category_rounded,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textLight,
                              size: 28,
                            ),
                          ),
                        ),
                      )
                          : Icon(
                        Icons.category_rounded,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textLight,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        cat.name,
                        style: AppTheme.caption.copyWith(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textDark,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 11,
                          overflow: TextOverflow.ellipsis,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}