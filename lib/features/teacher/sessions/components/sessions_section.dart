// components/sessions_section.dart
//
// Renders the sessions header + list (or loading / empty states).
// Consumes [TeacherCourseScreenProvider] via context — but only the sessions
// slice, so rebuilds are isolated to this widget tree.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/session_form_sheet.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_theme.dart';
import '../../../../config/app_config.dart';
import '../../../shared/session/material/session_material_widget.dart';
import '../../../student/models.dart';
import '../../home/teacher_models.dart';
import '../sessions_provider.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// [SliverList] + header that lives inside the parent [CustomScrollView].
/// Returns a list of slivers so the parent can simply spread them.
List<Widget> buildSessionsSlivers(BuildContext context,
    {required TeacherCourse course,
    required VoidCallback onAdd,
    required TeacherCourseScreenProvider provider}) {
  if (provider.loadingAllPage) {
    return [
      SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 28.0),
            child: Center(
                    child: CircularProgressIndicator(
            strokeWidth: min( context.width / 120,20),
                    ),
                  ),
          ))
    ];
  }

  return [
    SliverToBoxAdapter(
      child: _SectionHeader(onAdd: onAdd,sessionCount: provider.sessionCount,),
    ),
    if (provider.sessions.isEmpty)
      SliverToBoxAdapter(
        child: provider.isLoading
            ? const _LoadingState()
            : _EmptyState(
                onAdd: () => Helpers.showAddSessionSheet(context, course),
              ),
      ),
    if (provider.sessions.isNotEmpty)
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        sliver: SliverList.builder(
          itemCount: provider.sessions.length,
          itemBuilder: (_, i) => SessionMaterialCard(
            session: provider.sessions[i],
            course: course,
            isTeacher: true,
          ),
        ),
      ),
  ];
}


// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final VoidCallback onAdd;
  final int sessionCount;
  const _SectionHeader({required this.onAdd, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: context.colors.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'sessions'.tr,
            style: context.colors.h3.copyWith(fontSize: 15),
          ),
          if(sessionCount>0)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$sessionCount',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ),
          Spacer(),
          _AddButton(onTap: onAdd),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add button
// ─────────────────────────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: context.colors.accentGradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: context.colors.primaryShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            'add_session_btn'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontFamily: 'Tajawal',
              fontSize: 12,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading state
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary),
              strokeWidth: 3,
              backgroundColor: context.colors.primaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Text('loading_sessions'.tr, style: context.colors.body),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: context.colors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: context.colors.primaryShadow,
            ),
            child: const Icon(
              Icons.video_library_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'no_sessions_yet'.tr,
            style: context.colors.h3.copyWith(color: context.colors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            'add_first_session_hint'.tr,
            style: context.colors.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: context.colors.accentGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: context.colors.primaryShadow,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'add_first_session_btn'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
