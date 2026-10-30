import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../shared/category/categories_provider.dart';
import '../../../shared/category/categories_screen.dart';

class CategoriesRow extends StatelessWidget {
  const CategoriesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoriesProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingCategory) {
          return SizedBox(
            height: 112,
            child: Center(
              child: AppLoadingIndicator(),
            ),
          );
        }

        // nothing to show → nothing drawn (the home hides the section title too)
        if (provider.categories.isEmpty) return const SizedBox.shrink();
        final List<CategoryModel> categories = provider.categories
            .take(5)
            .toList();
        return SizedBox(
          // avatar + a two-line name (L7: one line cut most names)
          height: min(context.width / 6, 100) + 8 + 2 * 1.15 * max(11, min(context.width / 6, 100) / 7) * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final cat = categories[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CategoriesScreen(
                      selectedId: cat.id,
                    ),
                  ),
                ),
                child: CategoryAvatar(false,categoryModel: cat, index: i),
              );
            },
          ),
        );
      },
    );
  }
}
