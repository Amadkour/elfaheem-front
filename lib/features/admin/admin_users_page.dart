// lib/features/admin/admin_users_page.dart — students & teachers (list, detail, control).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key, required this.role, this.embedded = false});

  /// 'student' | 'teacher'
  final String role;

  /// true when shown as a tab inside the dashboard shell (no AppBar).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminUsersProvider(role)..refresh(),
      child: _UsersView(role: role, embedded: embedded),
    );
  }
}

class _UsersView extends StatelessWidget {
  const _UsersView({required this.role, required this.embedded});
  final String role;
  final bool embedded;

  bool get isStudent => role == 'student';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminUsersProvider>();
    final c = context.colors;

    final header = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: SearchBox(
          hint: t('بحث بالاسم أو البريد أو الهاتف', 'Search name, email or phone'),
          onChanged: p.setSearch,
        ),
      ),
      FilterChips<String>(
        value: p.status ?? 'all',
        options: {
          'all': t('الكل', 'All'),
          'active': t('نشط', 'Active'),
          'inactive': t('معطّل', 'Inactive'),
          'pending_deletion': t('بانتظار الحذف', 'Pending deletion'),
        },
        onChanged: (v) => p.setStatus(v == 'all' ? null : v),
      ),
      if (isStudent)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: FilterChips<String>(
            value: p.subscribed == null ? 'any' : (p.subscribed! ? 'yes' : 'no'),
            options: {
              'any': t('كل الاشتراكات', 'Any subscription'),
              'yes': t('مشترك', 'Subscribed'),
              'no': t('غير مشترك', 'Not subscribed'),
            },
            onChanged: (v) => p.setSubscribed(v == 'any' ? null : v == 'yes'),
          ),
        ),
      const SizedBox(height: 6),
    ]);

    final list = PagedList<AdminUsersProvider>(
      header: header,
      emptyText: isStudent
          ? t('لا يوجد طلاب', 'No students found')
          : t('لا يوجد معلمون', 'No teachers found'),
      itemBuilder: (ctx, row) => _UserTile(AdminUser(row), isStudent: isStudent),
    );

    final fab = FloatingActionButton.extended(
      backgroundColor: c.primary,
      onPressed: () => _openForm(context, p),
      icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
      label: Text(isStudent ? t('إضافة طالب', 'Add student') : t('إضافة معلم', 'Add teacher'),
          style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
    );

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: embedded
            ? null
            : AppBar(
                title: Text(isStudent ? t('الطلاب', 'Students') : t('المعلمون', 'Teachers'),
                    style: const TextStyle(fontFamily: 'tajawal')),
              ),
        floatingActionButton: fab,
        body: list,
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile(this.u, {required this.isStudent});
  final AdminUser u;
  final bool isStudent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminUsersProvider>();
    final sub = u.subscription;

    return RowCard(
      onTap: () => _openDetail(context, p, u.id),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: c.primary.withValues(alpha: 0.15),
          child: Text(u.name.isEmpty ? '?' : u.name.characters.first.toUpperCase(),
              style: TextStyle(color: c.primary, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark)),
            Text(u.gmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (u.pendingDeletion)
                StatusChip(t('بانتظار الحذف', 'Pending deletion'), c.danger)
              else
                StatusChip(u.isActive ? t('نشط', 'Active') : t('معطّل', 'Inactive'),
                    u.isActive ? c.success : c.warning),
              if (isStudent)
                StatusChip(
                  u.hasActiveSubscription
                      ? t('مشترك', 'Subscribed')
                      : (sub?.status == 'pending'
                          ? t('اشتراك معلّق', 'Sub pending')
                          : t('غير مشترك', 'No sub')),
                  u.hasActiveSubscription
                      ? c.success
                      : (sub?.status == 'pending' ? c.warning : c.textLight),
                ),
              if (isStudent)
                StatusChip('${u.enrolledCourses.length} ${t('كورس', 'courses')}', c.primary)
              else
                StatusChip('${u.coursesCount} ${t('كورس', 'courses')}', c.primary),
            ]),
          ]),
        ),
        Icon(Icons.chevron_left_rounded, color: c.textLight),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Detail / control sheet
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openDetail(BuildContext context, AdminUsersProvider p, int id) async {
  await showAdminSheet(
    context,
    (ctx) => ChangeNotifierProvider.value(
      value: p,
      child: _UserDetailSheet(userId: id),
    ),
  );
}

class _UserDetailSheet extends StatefulWidget {
  const _UserDetailSheet({required this.userId});
  final int userId;

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  UserDetail? d;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<AdminUsersProvider>().detail(widget.userId);
    if (!mounted) return;
    setState(() {
      d = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminUsersProvider>();

    if (loading) {
      return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
    }
    if (d == null) {
      return SizedBox(
          height: 260,
          child: ErrorRetry(
              message: t('تعذر تحميل البيانات', 'Could not load data'), onRetry: _load));
    }
    final u = d!.user;
    final isStudent = u.role == 'student';

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(u.name),
      Flexible(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shrinkWrap: true,
          children: [
            Section(
              title: t('البيانات', 'Profile'),
              child: Column(children: [
                KeyValue(t('البريد', 'Email'), u.gmail),
                KeyValue(t('الهاتف', 'Phone'), u.phone),
                KeyValue(t('الدولة', 'Country'), u.country),
                KeyValue(t('الميلاد', 'Birth date'), shortDate(u.dob)),
                KeyValue(t('الحالة', 'Status'),
                    u.pendingDeletion ? t('بانتظار الحذف', 'Pending deletion') : (u.isActive ? t('نشط', 'Active') : t('معطّل', 'Inactive'))),
                KeyValue(t('تسجيل', 'Joined'), shortDate(u.createdAt)),
                KeyValue(t('آخر دخول', 'Last login'), shortDateTime(u.lastLogin)),
                KeyValue(t('مرات الدخول', 'Logins'), '${u.loginTimes}'),
              ]),
            ),
            if (isStudent) ..._studentSections(context, p, u),
            if (!isStudent && d!.j['teacher_profile'] is Map)
              Section(
                title: t('ملف المعلم', 'Teacher profile'),
                child: Column(children: [
                  KeyValue(t('الخبرة', 'Experience'), '${asMap(d!.j['teacher_profile'])['experience_years']}'),
                  KeyValue(t('نوع التدريس', 'Teaching'), asStr(asMap(d!.j['teacher_profile'])['teaching_type'])),
                  KeyValue(t('نوع الدفع', 'Payment'), asStr(asMap(d!.j['teacher_profile'])['payment_type'])),
                ]),
              ),
            Section(
              title: t('التحكم', 'Controls'),
              child: Column(children: [
                PrimaryButton(
                  label: u.isActive ? t('تعطيل الحساب', 'Deactivate account') : t('تفعيل الحساب', 'Activate account'),
                  danger: u.isActive,
                  icon: u.isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                  onPressed: () async {
                    final ok = await confirm(context,
                        message: u.isActive
                            ? t('تعطيل هذا الحساب؟', 'Deactivate this account?')
                            : t('تفعيل هذا الحساب؟', 'Activate this account?'),
                        danger: u.isActive);
                    if (!ok) return;
                    if (await p.setActive(u.id, !u.isActive)) await _load();
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(t('تعديل', 'Edit')),
                      onPressed: () async {
                        await _openForm(context, p, existing: u);
                        await _load();
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
                            message: t('حذف هذا المستخدم نهائياً؟ لا يمكن التراجع.',
                                'Permanently delete this user? This cannot be undone.'),
                            danger: true);
                        if (!ok) return;
                        if (await p.remove(u.id) && context.mounted) Navigator.pop(context);
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

  List<Widget> _studentSections(BuildContext context, AdminUsersProvider p, AdminUser u) {
    final c = context.colors;
    final sub = d!.subscriptions.isEmpty ? null : d!.subscriptions.first;

    return [
      Section(
        title: t('الاشتراك', 'Subscription'),
        trailing: TextButton.icon(
          onPressed: () async {
            await _grantDialog(context, p, u.id);
            await _load();
          },
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: Text(t('منح', 'Grant')),
        ),
        child: sub == null
            ? Text(t('لا يوجد اشتراك', 'No subscription'),
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight))
            : Column(children: [
                KeyValue(t('الحالة', 'Status'), sub.status),
                KeyValue(t('الخطة', 'Plan'), sub.planCode),
                KeyValue(t('من', 'From'), shortDate(sub.startsAt)),
                KeyValue(t('إلى', 'Until'), shortDate(sub.endsAt)),
                KeyValue(t('المبلغ', 'Amount'), money(sub.amount, sub.currency)),
              ]),
      ),
      Section(
        title: t('الكورسات المشترك بها', 'Subscribed courses'),
        trailing: TextButton.icon(
          onPressed: () async {
            await _enrollDialog(context, p, u.id);
            await _load();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(t('تسجيل', 'Enrol')),
        ),
        child: d!.enrollments.isEmpty
            ? Text(t('لا توجد كورسات', 'No courses'),
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight))
            : Column(children: [
                for (final e in d!.enrollments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(asStr(e['course_name']),
                            style: TextStyle(fontFamily: 'tajawal', color: c.textDark)),
                      ),
                      StatusChip(
                          asStr(e['status']),
                          asStr(e['status']) == 'active'
                              ? c.success
                              : (asStr(e['status']) == 'dropped' ? c.danger : c.warning)),
                      if (asStr(e['status']) != 'dropped')
                        IconButton(
                          tooltip: t('إلغاء التسجيل', 'Remove'),
                          icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger, size: 20),
                          onPressed: () async {
                            final ok = await confirm(context,
                                message: t('إلغاء تسجيل الطالب من الكورس؟', 'Remove the student from this course?'),
                                danger: true);
                            if (!ok) return;
                            if (await p.unenroll(u.id, asInt(e['course_id']))) await _load();
                          },
                        ),
                    ]),
                  ),
              ]),
      ),
      Section(
        title: t('الأجهزة', 'Devices'),
        trailing: d!.devices.isEmpty
            ? null
            : TextButton(
                onPressed: () async {
                  final ok = await confirm(context,
                      message: t('إزالة كل الأجهزة وإعادة ضبط حد التبديل؟',
                          'Remove all devices and reset the switch limit?'),
                      danger: true);
                  if (!ok) return;
                  if (await p.resetDevices(u.id)) await _load();
                },
                child: Text(t('إعادة ضبط', 'Reset all'), style: TextStyle(color: c.danger)),
              ),
        child: d!.devices.isEmpty
            ? Text(t('لا توجد أجهزة مسجّلة', 'No registered devices'),
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight))
            : Column(children: [
                for (final dev in d!.devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.phone_android_rounded, color: c.primary),
                    title: Text(dev.deviceName, style: const TextStyle(fontFamily: 'tajawal')),
                    subtitle: Text(
                        '${t('منذ', 'Since')} ${shortDate(dev.boundAt)}',
                        style: const TextStyle(fontFamily: 'tajawal', fontSize: 11.5)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: c.danger, size: 20),
                      onPressed: () async {
                        if (await p.removeDevice(u.id, dev.id)) await _load();
                      },
                    ),
                  ),
                if (d!.lastDeviceSwitchAt != null)
                  KeyValue(t('آخر تبديل', 'Last switch'), shortDate(d!.lastDeviceSwitchAt)),
              ]),
      ),
      if (d!.payments.isNotEmpty)
        Section(
          title: t('المدفوعات', 'Payments'),
          child: Column(children: [
            for (final pay in d!.payments.take(8))
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
    ];
  }
}

Future<void> _grantDialog(BuildContext context, AdminUsersProvider p, int userId) async {
  final daysCtrl = TextEditingController();
  String plan = 'monthly';
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Directionality(
        textDirection: dir,
        child: AlertDialog(
          title: Text(t('منح اشتراك', 'Grant subscription'), style: const TextStyle(fontFamily: 'tajawal')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ChoiceRow<String>(
              options: {'monthly': t('شهري', 'Monthly'), 'yearly': t('سنوي', 'Yearly'), 'custom': t('أيام مخصصة', 'Custom days')},
              value: plan,
              onChanged: (v) => setS(() => plan = v),
            ),
            if (plan == 'custom')
              Field(controller: daysCtrl, label: t('عدد الأيام', 'Days'), keyboard: TextInputType.number),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('إلغاء', 'Cancel'))),
            TextButton(
              onPressed: () async {
                final days = int.tryParse(daysCtrl.text.trim());
                if (plan == 'custom' && (days == null || days < 1)) {
                  toast(t('أدخل عدد أيام صحيح', 'Enter a valid number of days'), error: true);
                  return;
                }
                Navigator.pop(ctx);
                await p.grant(userId, planCode: plan == 'custom' ? null : plan, days: plan == 'custom' ? days : null);
              },
              child: Text(t('منح', 'Grant')),
            ),
          ],
        ),
      ),
    ),
  );
  daysCtrl.dispose();
}

Future<void> _enrollDialog(BuildContext context, AdminUsersProvider p, int userId) async {
  final courses = await p.courseChoices();
  if (!context.mounted) return;
  if (courses.isEmpty) {
    toast(t('لا توجد كورسات', 'No courses'), error: true);
    return;
  }
  final picked = await showDialog<AdminCourse>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: SimpleDialog(
        title: Text(t('اختر الكورس', 'Choose a course'), style: const TextStyle(fontFamily: 'tajawal')),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(children: [
              for (final c in courses)
                ListTile(
                  title: Text(c.name, style: const TextStyle(fontFamily: 'tajawal')),
                  subtitle: Text(c.teacherName, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ]),
          ),
        ],
      ),
    ),
  );
  if (picked != null) await p.enroll(userId, picked.id);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit form
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openForm(BuildContext context, AdminUsersProvider p, {AdminUser? existing}) {
  return showAdminSheet(
    context,
    (ctx) => _UserForm(provider: p, existing: existing),
  );
}

class _UserForm extends StatefulWidget {
  const _UserForm({required this.provider, this.existing});
  final AdminUsersProvider provider;
  final AdminUser? existing;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _email = TextEditingController(text: widget.existing?.gmail);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _country = TextEditingController(text: widget.existing?.country.isEmpty ?? true ? 'EG' : widget.existing!.country);
  final _password = TextEditingController();
  final _years = TextEditingController(text: '0');
  bool busy = false;

  bool get editing => widget.existing != null;
  String get role => widget.provider.role;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _country, _password, _years]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    bool ok;
    if (editing) {
      ok = await widget.provider.update(widget.existing!.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'country': _country.text.trim().isEmpty ? null : _country.text.trim(),
        if (_password.text.isNotEmpty) 'password': _password.text,
      });
    } else {
      ok = await widget.provider.create({
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'password': _password.text,
        'role': role,
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'country': _country.text.trim().isEmpty ? null : _country.text.trim(),
        if (role == 'teacher') 'experience_years': int.tryParse(_years.text.trim()) ?? 0,
      });
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(editing
          ? t('تعديل المستخدم', 'Edit user')
          : (role == 'teacher' ? t('إضافة معلم', 'Add teacher') : t('إضافة طالب', 'Add student'))),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Form(
            key: _form,
            child: Column(children: [
              Field(
                controller: _name,
                label: t('الاسم', 'Name'),
                validator: (v) => (v == null || v.trim().length < 2) ? t('الاسم مطلوب', 'Name is required') : null,
              ),
              Field(
                controller: _email,
                label: t('البريد الإلكتروني', 'Email'),
                keyboard: TextInputType.emailAddress,
                ltr: true,
                enabled: !editing,
                validator: (v) => (v == null || !v.contains('@') || !v.contains('.'))
                    ? t('بريد غير صحيح', 'Invalid email')
                    : null,
              ),
              Field(controller: _phone, label: t('الهاتف', 'Phone'), keyboard: TextInputType.phone, ltr: true),
              Field(controller: _country, label: t('الدولة (كود)', 'Country code'), ltr: true),
              if (!editing && role == 'teacher')
                Field(controller: _years, label: t('سنوات الخبرة', 'Experience years'), keyboard: TextInputType.number),
              Field(
                controller: _password,
                label: editing ? t('كلمة مرور جديدة (اختياري)', 'New password (optional)') : t('كلمة المرور', 'Password'),
                obscure: true,
                validator: (v) {
                  if (editing && (v == null || v.isEmpty)) return null;
                  return (v == null || v.length < 6) ? t('6 أحرف على الأقل', 'At least 6 characters') : null;
                },
              ),
              PrimaryButton(label: t('حفظ', 'Save'), busy: busy, onPressed: _submit),
            ]),
          ),
        ),
      ),
    ]);
  }
}
