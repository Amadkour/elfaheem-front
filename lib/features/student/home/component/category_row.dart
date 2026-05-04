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
          return  SizedBox(
            height: 112,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.colors.primary),
                strokeWidth: 2.5,
              ),
            ),
          );
        }

        if (provider.categories.isEmpty) {
          return  SizedBox(
            height: 112,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined,
                      size: 36, color: context.colors.textLight),
                  SizedBox(height: 8),
                  Text('لا توجد أقسام', style: context.colors.caption),
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
                            ? context.colors.primaryLight
                            : context.colors.cardBg,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                            color: context.colors.primary, width: 2)
                            : Border.all(
                            color: Colors.transparent, width: 2),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color:
                            context.colors.primary.withValues(alpha:0.28),
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
                                ? context.colors.primary
                                : context.colors.accent2,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.category_rounded,
                              color: isSelected
                                  ? context.colors.primary
                                  : context.colors.textLight,
                              size: 28,
                            ),
                          ),
                        ),
                      )
                          : Icon(
                        Icons.category_rounded,
                        color: isSelected
                            ? context.colors.primary
                            : context.colors.textLight,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 70,
                      child: Text(
                        cat.name,
                        style: context.colors.caption.copyWith(
                          color: isSelected
                              ? context.colors.primary
                              : context.colors.textDark,
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