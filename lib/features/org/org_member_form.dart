// lib/features/org/org_member_form.dart — add / edit one organization member (API: POST|PUT /orgs/{o}/members).
//
//   showOrgMemberForm     add (any allowed role) or edit the membership of an existing row; returns the saved row.
//                         Used by the People page AND by the "Add new member" button of the manager pickers, so a
//                         half-filled department form stays open underneath and gets the new person selected.
//   showMembershipExtend  extend / make permanent / reactivate (POST /members/{mid}/extend)
//
// Trusted academic data (year / level, cohort, academic department) is written here by staff only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_access_page.dart' show OrgRoleEditor;
import 'org_dynamic_form.dart' show orgOption;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';

/// Membership roles of POST /members (`MemberIn.role`); positions and permission bundles are separate (below).
const orgMemberRoles = ['student', 'teacher', 'teacher_assistant', 'admin_assistant', 'org_admin'];

Map<String, String> orgRoleLabels() => {
      'student': t('طالب', 'Student'),
      'teacher': t('مدرس', 'Teacher'),
      'teacher_assistant': t('معيد', 'Teaching assistant'),
      'admin_assistant': t('مساعد إداري', 'Admin assistant'),
      'org_admin': t('مدير مشارك للمؤسسة', 'Co-admin of the organization'),
    };

/// The permission module that guards adding each role (server: ROLE_MODULE; co-admins: org admins only).
bool orgCanAddRole(OrgSession s, String role) => switch (role) {
      'org_admin' => s.isOrgAdmin,
      'student' => s.can('students', 'insert'),
      'teacher' => s.can('teachers', 'insert'),
      _ => s.can('staff', 'insert'),
    };

/// Everything the form needs from the organization, fetched once per form.
class _MemberFormData {
  List<Map<String, dynamic>> programs = [], levels = [], depts = [], roles = [];
  bool allowGeneral = false;

  static Future<_MemberFormData> load(OrgSession s) async {
    final d = _MemberFormData();
    final rs = await Future.wait([
      orgCall(() => s.api.get('${s.base}/academic/programs'), quiet: true),
      orgCall(() => s.api.get('${s.base}/academic/settings'), quiet: true),
      orgCall(() => s.api.get('${s.base}/departments'), quiet: true),
      if (s.can('roles', 'update')) orgCall(() => s.api.get('${s.base}/access/roles'), quiet: true),
    ]);
    d.programs = asMapList(rs[0].map['items']).where((p) => p['is_active'] != false).toList();
    d.levels = asMapList(rs[1].map['levels']);
    d.allowGeneral = rs[1].map['allow_general_teachers'] == true;
    d.depts = asMapList(rs[2].map['items']).where((x) => x['is_active'] != false).toList();
    if (rs.length > 3) d.roles = asMapList(rs[3].map['items']);
    return d;
  }
}

/// After the member exists: department head (team) and extra permission roles. Returns what failed, if anything.
Future<List<String>> _applyPositions(OrgSession s, int userId, {int? headOf, String? title, Set<int> roleIds = const {}, int? roleDept, List<Map<String, dynamic>> roles = const []}) async {
  final failed = <String>[];
  if (headOf != null) {
    final r = await orgCall(() => s.api.post('${s.base}/departments/$headOf/team', body: {'user_id': userId, 'is_head': true, if (title != null) 'title': title}), quiet: true);
    if (!r.ok) failed.add('${t('رئاسة الإدارة', 'Department head')}: ${orgErrorText(r.error!)}');
  }
  for (final id in roleIds) {
    final r = await orgCall(() => s.api.post('${s.base}/access/users/$userId/roles', body: {'role_id': id, 'dept_id': roleDept}), quiet: true);
    if (!r.ok) failed.add('${orgNameOf(roles.firstWhere((x) => asInt(x['id']) == id, orElse: () => {}))}: ${orgErrorText(r.error!)}');
  }
  return failed;
}

/// Returns the saved member row (with `generated_password` once, for a new account), or null.
Future<Map<String, dynamic>?> showOrgMemberForm(
  BuildContext context, {
  List<String> roles = const ['student'],
  Map<String, dynamic>? edit,
  int? deptId,
}) async {
  final s = context.read<OrgSession>();
  final data = await _MemberFormData.load(s);
  if (!context.mounted) return null;
  final u = asMap(edit?['user']);
  final email = TextEditingController(text: '${u['email'] ?? ''}');
  final name = TextEditingController(text: '${u['name'] ?? ''}');
  final phone = TextEditingController(), pass = TextEditingController(), title = TextEditingController();
  final code = TextEditingController(text: '${edit?['student_code'] ?? ''}');
  final exp = TextEditingController(text: edit?['experience_level'] == null ? '' : '${edit!['experience_level']}');
  final allowed = roles.where((r) => orgCanAddRole(s, r)).toList();
  final roleOptions = allowed.isEmpty ? roles : allowed;   // nothing allowed: the server explains why
  String role = '${edit?['role'] ?? roleOptions.first}';
  bool head = false;
  final extraRoles = <int>{};
  DateTime? starts = orgParseUtc(edit?['starts_at']), expires = orgParseUtc(edit?['expires_at']);
  bool limited = expires != null;
  int? program = edit?['program_id'] == null ? null : asInt(edit!['program_id']);
  String? level = edit?['academic_level'] as String?, cohort = edit?['cohort'] as String?;
  int? dept = deptId;
  bool busy = false;
  String? err;
  Map<String, dynamic>? saved;
  var failed = <String>[];

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final student = role == 'student';
        final teaching = role == 'teacher' || role == 'teacher_assistant';
        Text label(String x) => Text(x, style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium));
        Future<void> pickDate(bool isStart) async {
          final now = DateTime.now();
          final d = await showDatePicker(
              context: ctx,
              firstDate: isStart ? DateTime(now.year - 5) : now,
              lastDate: DateTime(2100),
              initialDate: (isStart ? starts : expires) ?? (isStart ? now : DateTime(now.year + 1, now.month, now.day)));
          if (d == null) return;
          set(() => isStart ? starts = DateTime(d.year, d.month, d.day) : expires = DateTime(d.year, d.month, d.day, 23, 59, 59));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('إضافة عضو', 'Add a member') : t('عضوية ${u['name']}', '${u['name']}\'s membership')),
            if (edit == null) ...[
              if (roleOptions.length > 1) ...[
                label(t('الدور', 'Role')),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final r in roleOptions)
                      ChoiceChip(label: Text(orgRoleLabels()[r] ?? r), selected: role == r, onSelected: (_) => set(() => role = r)),
                  ]),
                ),
              ],
              AppEmailField(controller: email, label: t('البريد الإلكتروني', 'Email')),
              Field(controller: name, label: t('الاسم (مطلوب للحساب الجديد)', 'Name (needed for a new account)')),
              AppPhoneField(controller: phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),
              Field(controller: pass, label: t('كلمة مرور (اتركها فارغة لتوليد واحدة)', 'Password (leave empty to generate)'), ltr: true),
            ],
            if (student) Field(controller: code, label: t('الرقم الجامعي (اختياري)', 'Student number (optional)')),
            // ── membership period ──
            label(t('مدة العضوية', 'Membership period')),
            ChoiceRow<bool>(
              options: {false: t('دائمة', 'Permanent'), true: t('لمدة محددة', 'Time-limited')},
              value: limited,
              onChanged: (v) => set(() {
                limited = v;
                if (!v) expires = null;
              }),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => pickDate(true),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(starts == null ? t('تبدأ الآن', 'Starts now') : '${t('تبدأ', 'Starts')} ${shortDate(starts!.toIso8601String())}'),
                ),
              ),
              if (limited) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pickDate(false),
                    icon: const Icon(Icons.flag_rounded),
                    label: Text(expires == null ? t('تاريخ الانتهاء', 'Expiry date') : '${t('تنتهي', 'Ends')} ${shortDate(expires!.toIso8601String())}'),
                  ),
                ),
              ],
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                  limited
                      ? t('عند الانتهاء تتوقف عضويته في هذه المؤسسة فقط — حسابه وعضوياته الأخرى تبقى. يمكن تمديدها لاحقاً.',
                          'When it ends, only this organization\'s membership stops — the account and other memberships stay. You can extend it later.')
                      : t('تبقى نشطة حتى تُوقفها.', 'Stays active until you stop it.'),
                  style: orgText(ctx, size: 11.5, color: c.textLight)),
            ),
            // ── academic data (trusted — staff only) ──
            if (student) ...[
              label(t('الفرقة / المستوى', 'Year / level')),
              if (data.levels.isEmpty)
                Text(t('لم تُعرّف مستويات للمؤسسة بعد', 'No levels are configured yet'), style: orgText(ctx, size: 12, color: c.textLight)),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final l in data.levels)
                  ChoiceChip(label: Text(orgOption(l).$2), selected: level == '${l['key']}', onSelected: (on) => set(() => level = on ? '${l['key']}' : null)),
              ]),
              const SizedBox(height: 10),
              label(t('الدفعة', 'Cohort')),
              Wrap(spacing: 8, children: [
                for (final e in memberCohortLabels().entries)
                  ChoiceChip(label: Text(e.value), selected: cohort == e.key, onSelected: (on) => set(() => cohort = on ? e.key : null)),
              ]),
              const SizedBox(height: 10),
            ],
            if (teaching) ...[
              OrgPickField<int>(
                label: t('القسم العلمي', 'Academic department'),
                icon: Icons.account_tree_rounded,
                value: program,
                allowNone: true,
                noneLabel: t('عام (بدون قسم)', 'General (no department)'),
                options: {for (final p in data.programs) asInt(p['id']): '${p['code']} · ${orgNameOf(p)}'},
                onChanged: (v) => set(() => program = v),
              ),
              if (program == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      data.allowGeneral
                          ? t('مدرس عام: يدرّس المقررات العامة، ومقررات الأقسام مسموحة حسب إعدادات المؤسسة.',
                              'General teacher: teaches general courses; department courses are allowed by the institution\'s settings.')
                          : t('مدرس عام: يدرّس المقررات العامة فقط (إعدادات المؤسسة لا تسمح للعام بمقررات الأقسام).',
                              'General teacher: general courses only (the institution doesn\'t allow general teachers on department courses).'),
                      style: orgText(ctx, size: 11.5, color: c.textLight)),
                ),
              const SizedBox(height: 10),
            ],
            if (!student) ...[
              Field(controller: exp, label: t('سنوات الخبرة (اختياري)', 'Years of experience (optional)'), keyboard: TextInputType.number, ltr: true),
              if (edit == null) ...[
                OrgPickField<int>(
                  label: t('إدارة خدمية (فريق) — اختياري', 'Service department (team) — optional'),
                  icon: Icons.apartment_rounded,
                  value: dept,
                  allowNone: true,
                  options: {for (final x in data.depts) asInt(x['id']): orgNameOf(x)},
                  onChanged: (v) => set(() => dept = v),
                ),
                if (dept != null) ...[
                  Field(controller: title, label: t('المسمى في الفريق', 'Job title in the team')),
                  if (s.can('departments', 'update'))
                    OrgSwitchRow(
                        title: t('رئيس / مدير هذه الإدارة', 'Head / manager of this department'),
                        subtitle: t('يحصل على دور «رئيس إدارة» داخلها', 'Gets the "Head of department" role inside it'),
                        value: head,
                        onChanged: (v) => set(() => head = v)),
                ],
                if (data.roles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: label(t('أدوار وصلاحيات إضافية (اختياري)', 'Extra roles & permissions (optional)'))),
                    if (s.can('roles', 'insert'))
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(t('دور جديد', 'New role')),
                        onPressed: () async {
                          final r = await Navigator.of(ctx).push<dynamic>(MaterialPageRoute(builder: (_) => const OrgRoleEditor()));
                          if (r is Map && ctx.mounted) {
                            set(() {
                              data.roles = [...data.roles, Map<String, dynamic>.from(r)];
                              extraRoles.add(asInt(r['id']));
                            });
                          }
                        },
                      ),
                  ]),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final r in data.roles)
                      if (!(head && r['key'] == 'dept_head'))
                        Tooltip(
                          message: '${r['description'] ?? ''}',
                          child: FilterChip(
                            label: Text(orgNameOf(r)),
                            selected: extraRoles.contains(asInt(r['id'])),
                            onSelected: (on) => set(() => on ? extraRoles.add(asInt(r['id'])) : extraRoles.remove(asInt(r['id']))),
                          ),
                        ),
                  ]),
                  if (extraRoles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                          dept == null
                              ? t('تُطبَّق على المؤسسة كلها.', 'Applies to the whole organization.')
                              : t('تُطبَّق داخل الإدارة المختارة فقط.', 'Applies inside the selected department only.'),
                          style: orgText(ctx, size: 11.5, color: c.textLight)),
                    ),
                ],
              ],
            ],
            if (err != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Text(err!, style: orgText(ctx, size: 12.5, color: c.danger)),
              ),
            AppButton.primary(
              busy: busy,
              label: edit == null ? t('إضافة', 'Add') : t('حفظ', 'Save'),
              onPressed: () async {
                if (edit == null && !email.text.contains('@')) return set(() => err = t('أدخل بريداً صحيحاً', 'Enter a valid email'));
                if (limited && expires == null) return set(() => err = t('اختر تاريخ الانتهاء', 'Pick the expiry date'));
                if (limited && starts != null && !starts!.isBefore(expires!)) return set(() => err = orgCodeText('bad_window'));
                final common = <String, dynamic>{
                  'starts_at': orgUtc(starts),
                  'expires_at': limited ? orgUtc(expires) : null,
                  if (student) ...{'academic_level': level, 'cohort': cohort, 'student_code': code.text.trim().isEmpty ? null : code.text.trim()},
                  if (teaching) 'program_id': program,
                  if (!student) 'experience_level': int.tryParse(exp.text.trim()),
                };
                final body = edit != null
                    ? common
                    : {
                        ...common,
                        'role': role,
                        'email': email.text.trim(),
                        if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
                        if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
                        if (pass.text.isNotEmpty) 'password': pass.text,
                        // a head joins the team through the team endpoint (it grants the head role); others here
                        if (!student && dept != null && !head) ...{'dept_id': dept, if (title.text.trim().isNotEmpty) 'title': title.text.trim()},
                        if (role == 'admin_assistant') 'permissions': {'students': ['view'], 'teachers': ['view'], 'courses': ['view']},
                      };
                body.removeWhere((k, v) => v == null && edit == null);   // create: omit empties; edit: null clears
                set(() {
                  busy = true;
                  err = null;
                });
                final r = await orgCall(
                    () => edit == null ? s.api.post('${s.base}/members', body: body) : s.api.put('${s.base}/members/${edit['id']}', body: body),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) return set(() => err = orgErrorText(r.error!));
                saved = r.map;
                if (edit == null && !student && ((head && dept != null) || extraRoles.isNotEmpty)) {
                  failed = await _applyPositions(s, asInt(asMap(r.map['user'])['id']),
                      headOf: head ? dept : null,
                      title: title.text.trim().isEmpty ? null : title.text.trim(),
                      roleIds: extraRoles,
                      roleDept: dept,
                      roles: data.roles);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ]),
        );
      }));
  final row = saved;
  if (row != null && context.mounted) {
    if (failed.isNotEmpty) {
      toast('${t('أُضيف العضو، لكن لم يكتمل:', 'Member added, but not completed:')}\n${failed.join('\n')}', error: true);
    } else {
      toast(edit == null ? t('تمت الإضافة', 'Added') : t('تم الحفظ', 'Saved'));
    }
    if (row['generated_password'] != null) await showGeneratedPassword(context, '${asMap(row['user'])['email'] ?? email.text.trim()}', '${row['generated_password']}');
  }
  return row;
}

/// Login details of a just-created account — shown once.
Future<void> showGeneratedPassword(BuildContext context, String login, String password) => showAdminSheet<void>(
    context,
    (c2) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('بيانات الدخول', 'Login details')),
            SelectableText('$login\n$password',
                textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(t('تظهر مرة واحدة فقط — انسخها الآن.', 'Shown once — copy it now.')),
          ]),
        ));

/// Extend a membership, make it permanent, or reactivate it. Returns the updated row.
Future<Map<String, dynamic>?> showMembershipExtend(BuildContext context, Map<String, dynamic> row) async {
  final s = context.read<OrgSession>();
  final live = row['is_live'] == true;
  DateTime? until = orgParseUtc(row['expires_at']);
  bool permanent = until == null, reactivate = !live;
  final note = TextEditingController();
  bool busy = false;
  String? err;
  Map<String, dynamic>? saved;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('تمديد العضوية', 'Extend membership')),
            Text(membershipPeriodText(row), style: orgText(ctx, color: c.textMedium)),
            const SizedBox(height: 10),
            ChoiceRow<bool>(
              options: {true: t('دائمة', 'Permanent'), false: t('حتى تاريخ', 'Until a date')},
              value: permanent,
              onChanged: (v) => set(() => permanent = v),
            ),
            if (!permanent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag_rounded, color: c.primary),
                title: Text(until == null ? t('اختر تاريخ الانتهاء', 'Pick the end date') : shortDate(until!.toIso8601String())),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: ctx, firstDate: now, lastDate: DateTime(2100), initialDate: until != null && until!.isAfter(now) ? until! : now);
                  if (d != null) set(() => until = DateTime(d.year, d.month, d.day, 23, 59, 59));
                },
              ),
            if (!live)
              OrgSwitchRow(
                  title: t('إعادة التفعيل', 'Reactivate'),
                  subtitle: t('تحتاج صلاحية اعتماد الطلبات', 'Needs the right to approve requests'),
                  value: reactivate,
                  onChanged: (v) => set(() => reactivate = v)),
            Field(controller: note, label: t('ملاحظة للسجل (اختياري)', 'Note for the log (optional)')),
            if (err != null) Text(err!, style: orgText(ctx, size: 12.5, color: c.danger)),
            const SizedBox(height: 8),
            AppButton.primary(
              busy: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (!permanent && until == null) return set(() => err = t('اختر تاريخ الانتهاء', 'Pick the end date'));
                set(() {
                  busy = true;
                  err = null;
                });
                final r = await orgCall(
                    () => s.api.post('${s.base}/members/${row['id']}/extend', body: {
                          'expires_at': permanent ? null : orgUtc(until),
                          'reactivate': reactivate,
                          if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
                        }),
                    quiet: true);
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (!r.ok) return set(() => err = orgErrorText(r.error!));
                saved = r.map;
                Navigator.pop(ctx);
                toast(t('تم تحديث العضوية', 'Membership updated'));
              },
            ),
          ]),
        );
      }));
  return saved;
}

/// A member picker that lists eligible live members and can add a new one in place.
/// The form underneath keeps its state; the new person is selected only after the server created them.
class OrgMemberPickField extends StatefulWidget {
  const OrgMemberPickField({
    super.key,
    required this.label,
    required this.value,
    required this.roles,
    required this.onChanged,
    this.initialName,
    this.allowNone = true,
  });

  final String label;
  final int? value;              // user id
  final List<String> roles;      // eligible roles (server-side eligibility still applies)
  final ValueChanged<int?> onChanged;
  final String? initialName;     // name of the current value, before the list loads
  final bool allowNone;

  @override
  State<OrgMemberPickField> createState() => _OrgMemberPickFieldState();
}

class _OrgMemberPickFieldState extends State<OrgMemberPickField> {
  Map<int, String>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final r = await orgCall(() => s.api.get('${s.base}/members', queryParams: {'role': widget.roles.join(','), 'size': 100}), quiet: true);
    if (!mounted) return;
    setState(() => _people = {
          if (widget.value != null && widget.initialName != null) widget.value!: widget.initialName!,
          for (final m in asMapList(r.map['items'])) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']} · ${orgRoleLabels()['${m['role']}'] ?? m['role']}',
        });
  }

  Future<void> _addNew() async {
    final row = await showOrgMemberForm(context, roles: widget.roles);
    if (row == null || !mounted) return;
    final id = asInt(asMap(row['user'])['id']);
    setState(() => _people = {...?_people, id: '${asMap(row['user'])['name']} · ${orgRoleLabels()['${row['role']}'] ?? row['role']}'});
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final canAdd = widget.roles.any((r) => s.can(r == 'student' ? 'students' : r == 'teacher' ? 'teachers' : 'staff', 'insert'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OrgPickField<int>(
        label: widget.label,
        icon: Icons.person_rounded,
        value: widget.value,
        allowNone: widget.allowNone,
        options: _people ?? {if (widget.value != null) widget.value!: widget.initialName ?? '#${widget.value}'},
        onChanged: widget.onChanged,
      ),
      if (canAdd)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: _addNew,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(t('إضافة عضو جديد', 'Add new member')),
          ),
        ),
    ]);
  }
}
