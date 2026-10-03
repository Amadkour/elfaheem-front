// lib/features/admin/admin_courses_page.dart — all courses: status, income, full control,
// per-course payment provider / allowed methods / platform fee.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

class AdminCoursesPage extends StatelessWidget {
  const AdminCoursesPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminCoursesProvider()..refresh(),
        child: _CoursesView(embedded: embedded),
      );
}

class _CoursesView extends StatelessWidget {
  const _CoursesView({required this.embedded});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminCoursesProvider>();
    final c = context.colors;

    final header = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: SearchBox(hint: t('بحث باسم الكورس', 'Search course name'), onChanged: p.setSearch),
      ),
      FilterChips<String>(
        value: p.published == null ? 'all' : (p.published! ? 'pub' : 'draft'),
        options: {
          'all': t('الكل', 'All'),
          'pub': t('منشور', 'Published'),
          'draft': t('مسودة', 'Draft'),
        },
        onChanged: (v) => p.setPublished(v == 'all' ? null : v == 'pub'),
      ),
      const SizedBox(height: 6),
      FilterChips<String>(
        value: p.status ?? 'any',
        options: {
          'any': t('كل الحالات', 'Any status'),
          'in_progress': t('جارٍ', 'In progress'),
          'completed': t('مكتمل', 'Completed'),
        },
        onChanged: (v) => p.setStatus(v == 'any' ? null : v),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.payments_rounded, color: c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t('إجمالي دخل الكورسات', 'Total course income'),
                  style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
            ),
            Text(money(p.totalIncome),
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, color: c.primary, fontSize: 16)),
          ]),
        ),
      ),
    ]);

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: embedded ? null : AppBar(title: Text(t('الكورسات', 'Courses'), style: const TextStyle(fontFamily: 'tajawal'))),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.primary,
          onPressed: () => _openCourseForm(context, p),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(t('إضافة كورس', 'Add course'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
        ),
        body: PagedList<AdminCoursesProvider>(
          header: header,
          emptyText: t('لا توجد كورسات', 'No courses found'),
          itemBuilder: (ctx, row) => _CourseTile(AdminCourse(row)),
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile(this.course);
  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCoursesProvider>();
    final ps = course.paymentSettings;

    return RowCard(
      onTap: () => _openCourseDetail(context, p, course.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(course.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 15, color: c.textDark)),
          ),
          StatusChip(course.isPublished ? t('منشور', 'Published') : t('مسودة', 'Draft'),
              course.isPublished ? c.success : c.warning),
        ]),
        const SizedBox(height: 2),
        Text(course.teacherName, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
        const SizedBox(height: 10),
        Row(children: [
          _Stat(Icons.group_rounded, '${course.studentsCount}', t('طالب', 'students')),
          _Stat(Icons.account_balance_wallet_rounded, money(course.income, course.currency), t('الدخل', 'income')),
          _Stat(Icons.sell_rounded, money(course.fees, course.currency), t('السعر', 'price')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          StatusChip(course.status == 'completed' ? t('مكتمل', 'Completed') : t('جارٍ', 'In progress'), c.primary),
          StatusChip(ps.provider ?? t('البوابة الافتراضية', 'Default gateway'), c.charcoal),
          if (course.pendingPayments > 0)
            StatusChip('${course.pendingPayments} ${t('دفعة معلّقة', 'pending')}', c.warning),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Row(children: [
        Icon(icon, size: 16, color: c.primary),
        const SizedBox(width: 5),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 12.5, color: c.textDark)),
            Text(label, style: TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: c.textLight)),
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Detail + payment settings
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openCourseDetail(BuildContext context, AdminCoursesProvider p, int id) {
  return showAdminSheet(
    context,
    (ctx) => ChangeNotifierProvider.value(value: p, child: _CourseDetail(id: id)),
  );
}

class _CourseDetail extends StatefulWidget {
  const _CourseDetail({required this.id});
  final int id;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  AdminCourse? course;
  bool loading = true;

  // payment-settings form
  String? provider; // null = default
  bool restrictMethods = false;
  final Set<String> methods = {'card', 'bank_transfer', 'instapay'};
  final _fee = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await context.read<AdminCoursesProvider>().detail(widget.id);
    if (!mounted) return;
    setState(() {
      course = r;
      loading = false;
      if (r != null) {
        provider = r.paymentSettings.provider;
        final allowed = r.paymentSettings.allowedMethods;
        restrictMethods = allowed != null;
        methods
          ..clear()
          ..addAll(allowed ?? const ['card', 'bank_transfer', 'instapay']);
        _fee.text = r.paymentSettings.feePercent?.toString() ?? '';
      }
    });
  }

  Future<void> _savePayment() async {
    final feeText = _fee.text.trim();
    double? fee;
    if (feeText.isNotEmpty) {
      fee = double.tryParse(feeText);
      if (fee == null || fee < 0 || fee > 100) {
        toast(t('النسبة يجب أن تكون بين 0 و 100', 'Fee must be between 0 and 100'), error: true);
        return;
      }
    }
    if (restrictMethods && methods.isEmpty) {
      toast(t('اختر طريقة دفع واحدة على الأقل', 'Pick at least one payment method'), error: true);
      return;
    }
    setState(() => saving = true);
    // Every key is sent on purpose: null RESETS the field to the system default.
    final ok = await context.read<AdminCoursesProvider>().savePaymentSettings(widget.id, {
      'payment_provider': provider,
      'allowed_methods': restrictMethods ? (methods.toList()..sort()) : null,
      'platform_fee_percent': fee,
    });
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCoursesProvider>();
    if (loading) return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
    final co = course;
    if (co == null) {
      return SizedBox(height: 260, child: ErrorRetry(message: t('تعذر تحميل البيانات', 'Could not load data'), onRetry: _load));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(co.name),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Section(
              title: t('نظرة عامة', 'Overview'),
              child: Column(children: [
                KeyValue(t('المعلم', 'Teacher'), co.teacherName),
                KeyValue(t('السعر', 'Price'), money(co.fees, co.currency)),
                KeyValue(t('الطلاب', 'Students'), '${co.studentsCount}'),
                KeyValue(t('مدفوعات ناجحة', 'Paid'), '${co.paidCount}'),
                KeyValue(t('الدخل', 'Income'), money(co.income, co.currency)),
                KeyValue(t('نسبة المنصة الفعلية', 'Effective platform fee'), '${co.paymentSettings.effectiveFeePercent}%'),
              ]),
            ),
            Section(
              title: t('إعدادات الدفع', 'Payment settings'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ChoiceRow<String?>(
                  label: t('بوابة الدفع بالبطاقة', 'Card gateway'),
                  options: {
                    null: t('الافتراضية', 'System default'),
                    'moyasar': 'Moyasar',
                    'paymob': 'Paymob',
                  },
                  value: provider,
                  onChanged: (v) => setState(() => provider = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('تحديد طرق الدفع المتاحة', 'Restrict payment methods'),
                      style: const TextStyle(fontFamily: 'tajawal', fontSize: 14)),
                  value: restrictMethods,
                  activeTrackColor: c.primary,
                  onChanged: (v) => setState(() => restrictMethods = v),
                ),
                if (restrictMethods)
                  Wrap(spacing: 8, children: [
                    for (final m in const {
                      'card': 'Moyasar / Paymob',
                      'bank_transfer': 'تحويل بنكي',
                      'instapay': 'InstaPay',
                    }.entries)
                      FilterChip(
                        label: Text(m.value, style: const TextStyle(fontFamily: 'tajawal')),
                        selected: methods.contains(m.key),
                        selectedColor: c.primary.withValues(alpha: 0.25),
                        onSelected: (s) => setState(() => s ? methods.add(m.key) : methods.remove(m.key)),
                      ),
                  ]),
                const SizedBox(height: 12),
                Field(
                  controller: _fee,
                  label: t('نسبة المنصة % (فارغ = الافتراضي)', 'Platform fee % (empty = default)'),
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                ),
                Text(
                  t('InstaPay يظهر فقط للكورسات بعملة الجنيه المصري.', 'InstaPay is only shown for EGP courses.'),
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textLight),
                ),
                const SizedBox(height: 10),
                PrimaryButton(label: t('حفظ إعدادات الدفع', 'Save payment settings'), busy: saving, onPressed: _savePayment),
              ]),
            ),
            if (co.recentPayments.isNotEmpty)
              Section(
                title: t('آخر المدفوعات', 'Recent payments'),
                child: Column(children: [
                  for (final pay in co.recentPayments.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                          child: Text('#${pay['id']} • ${asStr(pay['method'], '—')} • ${shortDate(asStrOrNull(pay['created_at']))}',
                              style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textMedium)),
                        ),
                        Text(money(asDouble(pay['amount'])),
                            style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
                        const SizedBox(width: 8),
                        StatusChip(
                            asStr(pay['status']),
                            asStr(pay['status']) == 'completed'
                                ? c.success
                                : (asStr(pay['status']) == 'pending' ? c.warning : c.danger)),
                      ]),
                    ),
                ]),
              ),
            Section(
              title: t('التحكم', 'Controls'),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(co.isPublished ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      label: Text(co.isPublished ? t('إخفاء', 'Unpublish') : t('نشر', 'Publish')),
                      onPressed: () async {
                        if (await p.update(co.id, {'is_published': !co.isPublished})) await _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(t('تعديل', 'Edit')),
                      onPressed: () async {
                        await _openCourseForm(context, p, existing: co);
                        await _load();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(co.status == 'completed' ? Icons.replay_rounded : Icons.flag_rounded),
                      label: Text(co.status == 'completed' ? t('إعادة فتح', 'Reopen') : t('تحديد كمكتمل', 'Mark completed')),
                      onPressed: () async {
                        final next = co.status == 'completed' ? 'in_progress' : 'completed';
                        if (await p.update(co.id, {'status': next})) await _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(t('حذف', 'Delete')),
                      onPressed: () async {
                        final ok = await confirm(context,
                            message: t('حذف الكورس نهائياً؟ سيُحذف كل محتواه إن وُجد طلاب مسجلون.',
                                'Delete this course permanently? All content is removed.'),
                            danger: true);
                        if (!ok) return;
                        if (await p.remove(co.id, force: true) && context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit course
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openCourseForm(BuildContext context, AdminCoursesProvider p, {AdminCourse? existing}) {
  return showAdminSheet(context, (ctx) => _CourseForm(provider: p, existing: existing));
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({required this.provider, this.existing});
  final AdminCoursesProvider provider;
  final AdminCourse? existing;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _fees = TextEditingController(text: widget.existing == null ? '0' : widget.existing!.fees.toString());
  late final _max = TextEditingController(text: widget.existing?.maxStudents?.toString() ?? '');

  late String currency = widget.existing?.currency ?? 'EGP';
  late String type = (widget.existing?.type ?? 'recorded').toLowerCase();
  int? teacherId;
  int? categoryId;
  bool published = false;

  List<AdminUser> teachers = [];
  List<AdminCategory> categories = [];
  bool busy = false;
  bool ready = false;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    teacherId = widget.existing?.teacherId;
    categoryId = widget.existing?.categoryId;
    published = widget.existing?.isPublished ?? false;
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    final tch = await widget.provider.teacherChoices();
    final cat = await widget.provider.categoryChoices();
    if (!mounted) return;
    setState(() {
      teachers = tch;
      categories = cat;
      ready = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _fees, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (teacherId == null) {
      toast(t('اختر المعلم', 'Choose a teacher'), error: true);
      return;
    }
    setState(() => busy = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'fees': double.tryParse(_fees.text.trim()) ?? 0,
      'currency': currency,
      'type': type,
      'teacher_id': teacherId,
      'category_id': categoryId,
      'max_students': int.tryParse(_max.text.trim()),
      'is_published': published,
    };
    final ok = editing
        ? await widget.provider.update(widget.existing!.id, body)
        : await widget.provider.create(body);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _pickTeacher() async {
    final r = await showDialog<AdminUser>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: SimpleDialog(
          title: Text(t('اختر المعلم', 'Choose teacher'), style: const TextStyle(fontFamily: 'tajawal')),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 340,
              child: ListView(children: [
                for (final u in teachers)
                  ListTile(
                    title: Text(u.name, style: const TextStyle(fontFamily: 'tajawal')),
                    subtitle: Text(u.gmail, style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, u),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
    if (r != null) setState(() => teacherId = r.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final teacherName = teachers.where((u) => u.id == teacherId).map((u) => u.name).firstOrNull ??
        (editing ? widget.existing!.teacherName : null);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(editing ? t('تعديل الكورس', 'Edit course') : t('إضافة كورس', 'Add course')),
      Flexible(
        child: !ready
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Field(
                      controller: _name,
                      label: t('اسم الكورس', 'Course name'),
                      validator: (v) => (v == null || v.trim().length < 2) ? t('الاسم مطلوب', 'Name is required') : null,
                    ),
                    Field(controller: _desc, label: t('الوصف', 'Description'), maxLines: 3),
                    Row(children: [
                      Expanded(
                        child: Field(
                          controller: _fees,
                          label: t('السعر', 'Price'),
                          keyboard: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            return (n == null || n < 0) ? t('سعر غير صحيح', 'Invalid price') : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(controller: _max, label: t('الحد الأقصى للطلاب', 'Max students'), keyboard: TextInputType.number),
                      ),
                    ]),
                    ChoiceRow<String>(
                      label: t('العملة', 'Currency'),
                      options: const {'EGP': 'EGP', 'SAR': 'SAR', 'USD': 'USD'},
                      value: currency,
                      onChanged: (v) => setState(() => currency = v),
                    ),
                    ChoiceRow<String>(
                      label: t('النوع', 'Type'),
                      options: {'recorded': t('مسجّل', 'Recorded'), 'live': t('مباشر', 'Live')},
                      value: type,
                      onChanged: (v) => setState(() => type = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: _pickTeacher,
                        icon: const Icon(Icons.school_rounded),
                        label: Text(teacherName ?? t('اختر المعلم', 'Choose teacher')),
                      ),
                    ),
                    if (categories.isNotEmpty)
                      ChoiceRow<int?>(
                        label: t('التصنيف', 'Category'),
                        options: {null: t('بدون', 'None'), for (final cat in categories) cat.id: cat.display},
                        value: categoryId,
                        onChanged: (v) => setState(() => categoryId = v),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('منشور', 'Published'), style: const TextStyle(fontFamily: 'tajawal')),
                      value: published,
                      activeTrackColor: c.primary,
                      onChanged: (v) => setState(() => published = v),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(label: t('حفظ', 'Save'), busy: busy, onPressed: _submit),
                  ]),
                ),
              ),
      ),
    ]);
  }
}
