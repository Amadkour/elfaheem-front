// Learning Hub v2 teachers and packages (D-1620 .. D-1639) on a phone and a wide window, ar / en, text 1.3: the
// teacher's status card in every state, the onboarding wizard's frame and steps' plain parts, the package wizard's
// three steps with the live summary, my packages, the review queue and detail, the student's list, a teacher's
// page, a package's page in every join state, my teachers, the filter and reject forms.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teachers/package_wizard.dart';
import 'package:flutter_education_app/features/teachers/teacher_discovery.dart';
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart';
import 'package:flutter_education_app/features/teachers/teacher_review_admin.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';
import 'teachers_models_test.dart' show packageJson, profileJson;

const _longName = 'الشيخة فاطمة عبد الرحمن محمد الأنصاري الحافظة المجازة بالقراءات العشر';

TeacherProfile _profile({String status = 'approved', bool packages = true}) => TeacherProfile.fromJson({
      ...profileJson(status: status),
      'name': _longName,
      'bio': 'معلمة قرآن منذ خمس عشرة سنة، أحفّظ بالتكرار والربط بين الآيات وأتابع كل طالبة أسبوعياً. ' * 4,
      'subjects': ['quran', 'tajweed', 'fiqh', 'nahw'],
      'documents': [
        {'id': 1, 'doc_type': 'ijazah', 'file_name': 'ijazah_hafs_an_asim_with_a_very_long_name_scan_2026.pdf', 'status': 'pending', 'size': 8400000},
        {'id': 2, 'doc_type': 'id', 'file_name': 'id.jpg', 'status': 'rejected', 'rejection_reason': 'الصورة غير واضحة، أرفق نسخة أوضح من الوجهين'},
      ],
      'packages': packages ? [packageJson(), packageJson(seatsTaken: 10, overbook: 'none', price: 12345.5)] : [],
      'reviews': [
        {'name': 'Ahmed Abdelrahman Mohammed', 'rating': 5, 'comment': 'Excellent and patient teacher. ' * 3},
      ],
    });

TeacherPackage _pkg({Map<String, dynamic>? mine, int seatsTaken = 3, String overbook = 'waitlist', String status = 'published'}) =>
    TeacherPackage.fromJson({
      ...packageJson(mine: mine, seatsTaken: seatsTaken, overbook: overbook, status: status, price: 12345.5, discount: 15),
      'title': 'أحكام النون الساكنة والتنوين والميم الساكنة مع التطبيق على جزء عمّ كاملاً',
      'description': 'ثماني جلسات أسبوعية للمبتدئين. ' * 6,
    });

void main() {
  testWidgets('status card: every state', (tester) async {
    for (final s in ['none', 'draft', 'pending', 'rejected', 'approved']) {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: TeacherStatusCard(profile: s == 'none' ? TeacherProfile.empty : _profile(status: s), onStart: () {}, onFix: () {}),
        ),
      );
    }
  });

  testWidgets('onboarding frame, documents and the review summary', (tester) async {
    final p = _profile(status: 'rejected');
    await expectNoLayoutErrors(
      tester,
      () => TeacherWizardBody(
        step: TeacherStep.review,
        onStep: (_) {},
        onBack: () {},
        onNext: () {},
        nextLabel: 'Send for review',
        error: 'Write an introduction of at least 20 characters before you send it',
        child: TeacherReviewSummary(
          draft: TeacherProfileDraft.of(p)..bio = 'short',
          documents: p.documents,
          onEdit: (_) {},
        ),
      ),
    );
    await expectNoLayoutErrors(
      tester,
      () => TeacherWizardBody(
        step: TeacherStep.documents,
        onStep: (_) {},
        onBack: () {},
        onNext: () {},
        nextLabel: 'Next',
        locked: true,
        child: Column(children: [for (final d in p.documents) TeacherDocRow(doc: d, onRemove: () {})]),
      ),
    );
  });

  testWidgets('onboarding wizard steps (plain profile, no calls before an action)', (tester) async {
    for (final step in TeacherStep.values) {
      await expectNoLayoutErrors(tester, () => TeacherOnboardingWizard(initial: _profile(status: 'draft'), startAt: step), scaffold: false);
    }
  });

  testWidgets('package wizard: three steps with the summary', (tester) async {
    for (final step in PackageStep.values) {
      final d = PackageDraft.of(_pkg())
        ..overbook = 'allow'
        ..overbookLimit = 3;
      await expectNoLayoutErrors(
        tester,
        () => PackageWizardForm(draft: d, onSave: ({required bool publish}) {}, initialStep: step, locked: step == PackageStep.schedule, error: step == PackageStep.price ? 'Students run from 1 to 500' : null),
      );
    }
  });

  testWidgets('my packages', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        for (final s in ['draft', 'published', 'paused', 'closed']) MyPackageCard(package: _pkg(status: s), onEdit: () {}, onRoster: () {}),
        const MyPackagesSection(packages: []),
      ]),
    );
  });

  testWidgets('review queue card, detail and reject form', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        TeacherReviewCard(profile: _profile(status: 'pending'), onTap: () {}),
        const TeacherRejectForm(),
      ]),
    );
    await expectNoLayoutErrors(tester, () => TeacherReviewDetail(profile: _profile(status: 'pending'), onApprove: () {}, onReject: () {}, onOpenDoc: (_) {}));
  });

  testWidgets('student list, filters and my teachers', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => TeachersBrowseView(
        filters: const TeacherFilters(subject: 'quran', gender: 'female', available: true),
        onFilters: (_) {},
        items: [for (var i = 0; i < 5; i++) _profile()],
        total: 41,
        loadingMore: true,
      ),
    );
    await expectNoLayoutErrors(tester, () => TeachersBrowseView(filters: const TeacherFilters(q: 'x'), onFilters: (_) {}, items: const []));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: TeacherFiltersForm(initial: TeacherFilters(minRating: 4))));
    await expectNoLayoutErrors(
      tester,
      () => MyTeachersView(items: [
        MyTeacher(teacher: _profile(), activePackages: [_pkg()], nextSession: DateTime.utc(2026, 12, 1, 15)),
        MyTeacher(teacher: _profile()),
      ]),
    );
    await expectNoLayoutErrors(tester, () => const MyTeachersView(items: []));
  });

  testWidgets('a teacher page', (tester) async {
    await expectNoLayoutErrors(tester, () => TeacherProfileView(teacher: _profile(), onPackage: (_) {}));
    await expectNoLayoutErrors(tester, () => TeacherProfileView(teacher: _profile(packages: false)));
  });

  testWidgets('a package page in every join state', (tester) async {
    final soon = DateTime.now().toUtc().add(const Duration(minutes: 25)).toIso8601String().replaceAll('Z', '');
    final cases = <TeacherPackage>[
      _pkg(),
      _pkg(seatsTaken: 10, overbook: 'none'),
      _pkg(seatsTaken: 10),
      _pkg(mine: {'status': 'waitlisted', 'position': 4}),
      _pkg(mine: {'status': 'pending_payment', 'expires_at': soon}),
      _pkg(mine: {'status': 'offered', 'expires_at': soon}),
      _pkg(mine: {'status': 'active'}),
      _pkg(status: 'closed'),
    ];
    for (final p in cases) {
      await expectNoLayoutErrors(tester, () => PackageView(package: p, onJoin: () {}, onLeave: () {}));
    }
    await expectNoLayoutErrors(tester, () => PackageView(package: _pkg(), joinOff: true));
  });
}
