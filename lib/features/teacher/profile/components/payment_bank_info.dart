import 'package:flutter/material.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/primary_button.dart';

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'طرق الدفع'),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.colors.cardBg,
                    borderRadius: BorderRadius.circular(context.colors.radiusMedium),
                    boxShadow: context.colors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('معلومات الحساب البنكي', style: context.colors.h3),
                      const SizedBox(height: 16),
                      _Row('اسم البنك', '—'),
                      _Row('رقم الآيبان', '—'),
                      _Row('اسم الحساب', '—'),
                      const SizedBox(height: 20),
                      MyPrimaryButton(
                        label: 'تعديل معلومات الدفع',
                        isLoading: false,
                        onPressed: ()async {},
                      ),
                    ],
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

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.colors.label),
        Text(value,
            style: context.colors.label.copyWith(color: context.colors.textDark)),
      ],
    ),
  );
}
