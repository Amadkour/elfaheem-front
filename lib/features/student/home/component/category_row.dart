import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/category/categories_screen.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_theme.dart';
import '../../../category/categories_provider.dart';

class CategoriesRow extends StatelessWidget {
  const CategoriesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoriesProvider>(builder: (context, provider, child) {
      if (provider.isLoadingCategory) {
        return const SizedBox(
          height: 218,
          child: Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.primary))),
        );
      }

      if (provider.categories.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64, color: AppTheme.textLight),
              SizedBox(height: 12),
              Text('لا توجد اقسام', style: AppTheme.body),
            ],
          ),
        );
      }
      return SizedBox(
        height: 100,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: provider.categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final cat = provider.categories[i];
            final isSelected = provider.selectedCategoryId == cat.id;

            return GestureDetector(
              onTap: () =>Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CategoriesScreen()),
              ),
                  // context.read<CategoriesProvider>().selectCategory(cat.id),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.12)
                          : AppTheme.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            isSelected ? AppTheme.primary : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? AppTheme.primaryShadow
                          : AppTheme.cardShadow,
                    ),
                    child: Image.network(
                      cat.imageUrl,
                      height: 40,
                      width: 40,
                      color: isSelected ? AppTheme.primary : AppTheme.success,
                      errorBuilder: (i, b, g) =>  const Icon(
                        Icons.category,
                        color: AppTheme.primary,
                        size: 40,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(cat.name,
                        style: AppTheme.caption.copyWith(
                          color:
                              isSelected ? AppTheme.primary : AppTheme.textDark,
                          fontFamily: 'bahji',
                          overflow: TextOverflow.ellipsis,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                        textAlign: TextAlign.center),
                  ),
                ],
              ),
            );
          },
        ),
      );
    });
  }
}
