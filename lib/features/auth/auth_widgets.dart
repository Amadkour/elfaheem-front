// auth_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets used across all authentication screens.
// Import this file in every auth screen:
//   import 'auth_widgets.dart';
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../utils/widget/primary_menue.dart' show MyPrimaryMenu;
import 'auth_provider.dart';

// ── Brand colours ─────────────────────────────────────────────────────────────
const _kBrandLight = Color(0xFFEBF1FD);
const _kBorder = Color(0xFFE5E7EB);
const _kText = Color(0xFF16181D);
const _kMuted = Color(0xFF6B7280);

// ── 1. Sidebar (web only) ─────────────────────────────────────────────────────
class AuthSidebar extends StatelessWidget {
  const AuthSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3A8F), Color(0xFF1A56C4), Color(0xFF2563EB)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -80,
            right: -80,
            child: Circle(size: 320, opacity: 0.06),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: Circle(size: 280, opacity: 0.04),
          ),
          Positioned(
            top: 200,
            left: -40,
            child: Circle(size: 160, opacity: 0.05),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.15),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white.withValues(alpha:0.2)),
                        ),
                        child: const Icon(Icons.layers_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'El-faheem',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Bahji',
                            ),
                          ),
                          Text(
                            'Learning Platform',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha:0.5),
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontFamily: 'Bahji',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Headline
                  const Text(
                    'Unlock your\nfull potential\ntoday.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Bahji',
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Join thousands of students and educators in a rich digital learning experience.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.65),
                      fontSize: 14,
                      fontFamily: 'Bahji',
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Feature list
                  _SidebarFeature(
                    icon: Icons.schedule_rounded,
                    text: 'Live sessions & on-demand courses',
                  ),
                  const SizedBox(height: 14),
                  _SidebarFeature(
                    icon: Icons.groups_rounded,
                    text: 'Expert teachers across all specializations',
                  ),
                  const SizedBox(height: 14),
                  _SidebarFeature(
                    icon: Icons.insert_chart_outlined_rounded,
                    text: 'Interactive assessments & progress tracking',
                  ),

                  const Spacer(),

                  // Trust badges
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _TrustBadge(label: '10k+ Students'),
                      _TrustBadge(label: '500+ Teachers'),
                      _TrustBadge(label: 'Secure & Private'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Circle extends StatelessWidget {
  final double size;
  final double opacity;

  const Circle({super.key, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha:opacity),
        ),
      );
}

class _SidebarFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SidebarFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF93C5FD)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.8),
                fontSize: 13,
                fontFamily: 'Bahji',
              ),
            ),
          ),
        ],
      );
}

class _TrustBadge extends StatelessWidget {
  final String label;

  const _TrustBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha:0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.7),
                fontSize: 11,
                fontFamily: 'Bahji',
              ),
            ),
          ],
        ),
      );
}

// ── 2. Screen icon header ─────────────────────────────────────────────────────
class ScreenIcon extends StatelessWidget {
  final IconData icon;

  const ScreenIcon({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _kBrandLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: AppTheme.accent, size: 26),
      );
}

// ── 3. Styled text field with leading icon ────────────────────────────────────
class IconTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;

  const IconTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboard,
          style: const TextStyle(
            fontFamily: 'Bahji',
            fontSize: 14,
            color: _kText,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
            hintText: label,
            hintStyle: const TextStyle(
              fontFamily: 'Bahji',
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
            filled: true,
            fillColor: AppTheme.textFieldBackground,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kBorder, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kBorder, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:  BorderSide(color: AppTheme.textAction.withAlpha(150), width: 1.5),
            ),
          ),
          validator: (v) =>
              (v == null || v.isEmpty) ? '$label is required' : null,
        ),
      ],
    );
  }
}

// ── 4. Password field with toggle ─────────────────────────────────────────────
class IconPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool? obscure;
  final VoidCallback? onToggle;

  const IconPasswordField({
    required this.controller,
    required this.label,
    this.obscure,
    this.onToggle,
  });

  @override
  State<IconPasswordField> createState() => _IconPasswordFieldState();
}

class _IconPasswordFieldState extends State<IconPasswordField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: widget.label),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          style: const TextStyle(
            fontFamily: 'Bahji',
            fontSize: 14,
            color: _kText,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: Color(0xFF9CA3AF),
            ),
            suffixIcon: GestureDetector(
              onTap: () {
                setState(() => _obscure = !_obscure);
                widget.onToggle?.call();
              },
              child: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            hintText: '••••••••',
            hintStyle: const TextStyle(
              fontFamily: 'Bahji',
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
            filled: true,
            fillColor: AppTheme.textFieldBackground,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kBorder, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kBorder, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:  BorderSide(color: AppTheme.textAction.withAlpha(150), width: 1.5),
            ),
          ),
          validator: (v) =>
              (v == null || v.isEmpty) ? '${widget.label} is required' : null,
        ),
      ],
    );
  }
}

// ── 5. Primary button ─────────────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final bool isLoading;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const PrimaryButton({
    required this.isLoading,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          disabledBackgroundColor: AppTheme.accent.withValues(alpha:0.6),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Bahji',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 18),
                ],
              ),
      ),
    );
  }
}

// ── 6. Section label ──────────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Bahji',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _kMuted,
          letterSpacing: 0.8,
        ),
      );
}

// ── 7. Link row ───────────────────────────────────────────────────────────────
class LinkRow extends StatelessWidget {
  final String message;
  final String linkText;
  final VoidCallback onTap;

  const LinkRow({
    required this.message,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Bahji',
              fontSize: 14,
              color: _kMuted,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onTap,
            child: Text(
              linkText,
              style: const TextStyle(
                fontFamily: 'Bahji',
                fontSize: 14,
                color: AppTheme.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
}

// ── 8. Progress bar (step indicator) ─────────────────────────────────────────
class ProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const ProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(totalSteps, (i) {
          final done = i <= currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: done ? AppTheme.accent : _kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      );
}

// ── 9. Role picker card ───────────────────────────────────────────────────────
class RolePicker extends StatelessWidget {
  final AuthProvider provider;
  final ExpansibleController rolController;

  const RolePicker({
    required this.provider,
    required this.rolController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: provider.roles.map<Widget>((role) {
        final isSelected = provider.selectedRole == role;
        return Expanded(
          child: GestureDetector(
            onTap: () => provider.onChangeRole(
                provider.roles.indexOf(role), rolController),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: role == provider.roles.last ? 0 : 10,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? _kBrandLight : AppTheme.textFieldBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppTheme.accent : _kBorder,
                  width: isSelected ? 2 : 1.5,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(alpha:0.15)
                          : const Color(0xFF9CA3AF).withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      role['text'] == 'teacher'
                          ? Icons.cast_for_education_outlined
                          : Icons.school_outlined,
                      color: isSelected ? AppTheme.accent : _kMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    role['text'].toString().tr,
                    style: TextStyle(
                      fontFamily: 'Bahji',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? AppTheme.accent : _kText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── 10. Styled dropdown (wraps MyPrimaryMenu with icon + label) ───────────────
class StyledDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final ExpansibleController controller;
  final dynamic initValue;
  final List<Map<String, dynamic>> options;
  final Function(dynamic) onChange;

  const StyledDropdown({
    required this.icon,
    required this.label,
    required this.controller,
    required this.initValue,
    required this.options,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.textFieldBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          ),
          Expanded(
            child: MyPrimaryMenu(
              label: label,
              controller: controller,
              initValue: initValue,
              options: options,
              haveLogo: false,
              onChange: onChange,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 11. Language switcher row ─────────────────────────────────────────────────
class LangRow extends StatelessWidget {
  const LangRow();

  @override
  Widget build(BuildContext context) {
    LangProvider provider=context.watch<LangProvider>();
    return Row(
      children: provider.languages.map<Widget>((l) {
        final isActive = lang == l;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => provider.changeLang(l),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? _kBrandLight : AppTheme.textFieldBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? AppTheme.primary : _kBorder,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 14,
                    color: isActive ? AppTheme.primary : _kMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l.tr,
                    style: TextStyle(
                      fontFamily: 'Bahji',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isActive ? AppTheme.primary : _kMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
