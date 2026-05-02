// ── Teacher Schedule Queue ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../sessions/sessions_provider.dart';

// ── Entry point widget ────────────────────────────────────────────────────────

class ScheduleQueueList extends StatelessWidget {
  final List<ScheduleSession> sessions;

  const ScheduleQueueList({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const _EmptyQueue();

    final sorted = [...sessions]..sort((a, b) {
        if (a.isOngoing != b.isOngoing) return a.isOngoing ? -1 : 1;
        if (a.isToday != b.isToday) return a.isToday ? -1 : 1;
        final dateComp = a.scheduledDate.compareTo(b.scheduledDate);
        return dateComp != 0 ? dateComp : a.startTime.compareTo(b.startTime);
      });

    final groups = <String, List<ScheduleSession>>{};
    for (final s in sorted) {
      groups.putIfAbsent(s.dayLabel, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QueueHeader(count: sessions.length),
        ...groups.entries.map(
          (e) => _DayGroup(dayLabel: e.key, sessions: e.value),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _QueueHeader extends StatelessWidget {
  final int count;

  const _QueueHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Text(
            'جدول الأسبوع',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMedium,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              border: Border.all(color: AppTheme.divider),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day group ─────────────────────────────────────────────────────────────────

class _DayGroup extends StatelessWidget {
  final String dayLabel;
  final List<ScheduleSession> sessions;

  const _DayGroup({required this.dayLabel, required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Text(
            dayLabel,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMedium.withValues(alpha: 0.6),
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...sessions.map((s) => _SessionCard(session: s)),
      ],
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final ScheduleSession session;

  const _SessionCard({required this.session});

  Color get _accent {
    if (session.isOngoing) return const Color(0xFFE24B4A);
    if (session.isToday) return const Color(0xFF378ADD);
    return const Color(0xFF1D9E75);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: session.isOngoing
                ? _accent.withValues(alpha: 0.5)
                : AppTheme.divider,
            width: session.isOngoing ? 1.2 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: session.isOngoing ? 0.12 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Accent top bar
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_accent, _accent.withValues(alpha: 0.3)],
                ),
              ),
            ),

            // Main row: info (right/RTL start) + action button strip (left/RTL end)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info section
                  Expanded(
                    flex: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _TimeBlock(session: session, accent: _accent),
                          const SizedBox(width: 10),
                          _CourseImage(session: session),
                          const SizedBox(width: 10),
                          Expanded(
                            child:
                                _CourseInfo(session: session, accent: _accent),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Action button strip (left side in RTL = end)
                  Expanded(
                      flex: 1,
                      child: _InlineStartButton(session: session, accent: _accent)),
                ],
              ),
            ),

            // Progress bar for ongoing session
            if (session.isOngoing)
              LinearProgressIndicator(
                value: session.durationMinutes > 0
                    ? ((session.durationMinutes -
                                (session.minutesUntilEnd ?? 0)) /
                            session.durationMinutes)
                        .clamp(0.0, 1.0)
                    : 0,
                backgroundColor:
                    const Color(0xFFE24B4A).withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE24B4A)),
                minHeight: 3,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Inline start button strip (left side) ─────────────────────────────────────

class _InlineStartButton extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _InlineStartButton({required this.session, required this.accent});

  IconData get _icon {
    if (session.isOngoing) return Icons.sensors_rounded;
    if (session.isToday) return Icons.play_arrow_rounded;
    return Icons.sensors_rounded;
  }

  String get _label {
    if (session.isOngoing) return 'مباشر';
    if (session.isToday) return 'ابدأ';
    return 'ابدأ الان';
  }

  LinearGradient get _gradient {
    if (session.isOngoing) {
      return const LinearGradient(
        colors: [Color(0xFFE24B4A), Color(0xFFA32D2D)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }
    if (session.isToday) {
      return const LinearGradient(
        colors: [Color(0xFF378ADD), Color(0xFF185FA5)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateSessionSheet(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: _gradient,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (session.isOngoing) ...[
              _LiveDot(),
              const SizedBox(height: 5),
            ],
            Icon(_icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              _label,
              style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 10,
                fontWeight: FontWeight.normal,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Time block ────────────────────────────────────────────────────────────────

class _TimeBlock extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _TimeBlock({required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.startTime,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            width: 1.5,
            height: 8,
            color: accent.withValues(alpha: 0.3),
          ),
          Text(
            session.endTime,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accent.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Course image ──────────────────────────────────────────────────────────────

class _CourseImage extends StatelessWidget {
  final ScheduleSession session;

  const _CourseImage({required this.session});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 38,
        height: 38,
        color: AppTheme.primary.withValues(alpha: 0.08),
        child: session.courseImage != null
            ? Image.network(
                session.courseImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Initials(session.courseName),
              )
            : _Initials(session.courseName),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;

  const _Initials(this.name);

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          name.length >= 2
              ? name.substring(0, 2).toUpperCase()
              : name.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppTheme.textMedium,
          ),
        ),
      );
}

// ── Course info ───────────────────────────────────────────────────────────────

class _CourseInfo extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _CourseInfo({required this.session, required this.accent});

  @override
  Widget build(BuildContext context) {
    final dur =
        session.durationMinutes > 0 ? '${session.durationMinutes}د' : '—';
    final students = session.maxStudents != null
        ? '${session.maxStudents} طالب'
        : 'غير محدود';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                session.courseName,
                style: AppTheme.h3.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (session.isOngoing) ...[
              const SizedBox(width: 5),
              _LiveDot(),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _MetaChip(Icons.timer_rounded, dur),
            const SizedBox(width: 8),
            _MetaChip(Icons.group_rounded, students),
          ],
        ),
        const SizedBox(height: 5),
        _StatusBadge(session: session, accent: accent),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.textMedium),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: AppTheme.textMedium,
            ),
          ),
        ],
      );
}

class _StatusBadge extends StatelessWidget {
  final ScheduleSession session;
  final Color accent;

  const _StatusBadge({required this.session, required this.accent});

  String get _label {
    if (session.isOngoing) return 'مباشر الآن';
    if (session.isToday) return 'اليوم';
    return session.dayLabel;
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Text(
          _label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      );
}

// ── Live dot ──────────────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween(begin: 1.0, end: 0.3).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFE24B4A),
            shape: BoxShape.circle,
          ),
        ),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_today_outlined,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'لا توجد مواعيد خلال الأسبوع القادم',
                  style: AppTheme.caption.copyWith(color: AppTheme.textMedium),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _CreateSessionSheet extends StatefulWidget {
  final ScheduleSession session;

  const _CreateSessionSheet({required this.session});

  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.session.defaultSessionName);
    _descCtrl = TextEditingController();
    _durCtrl = TextEditingController(
        text: widget.session.durationMinutes > 0
            ? '${widget.session.durationMinutes}'
            : '60');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final duration =
        int.tryParse(_durCtrl.text.trim()) ?? widget.session.durationMinutes;
    final sessionId = await context.read<TeacherProvider>().createSession(
          courseId: widget.session.courseId,
          name: _nameCtrl.text.trim(),
          durationMinutes: duration,
          description:
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        );
    if (context.mounted) {
      context
          .read<TeacherSessionsProvider>()
          .joinLive(context, sessionId, widget.session.courseId, 100);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Header
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.videocam_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إنشاء حصة وبدء البث', style: AppTheme.h2),
                        Text(
                          widget.session.courseName,
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.primary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 18),

                // Schedule info chip
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded,
                        color: AppTheme.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.session.dayLabel}  '
                      '${widget.session.startTime} — ${widget.session.endTime}',
                      style: AppTheme.label.copyWith(color: AppTheme.primary),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),

                // Session name
                TextFormField(
                  controller: _nameCtrl,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  validator: (v) =>
                      (v?.isEmpty ?? true) ? 'أدخل اسم الحصة' : null,
                  decoration: InputDecoration(
                    labelText: 'اسم الحصة',
                    labelStyle: AppTheme.caption,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // Duration
                TextFormField(
                  controller: _durCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n <= 0) ? 'أدخل مدة صحيحة' : null;
                  },
                  decoration: InputDecoration(
                    labelText: 'المدة (بالدقائق)',
                    labelStyle: AppTheme.caption,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),

                // Submit
                GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.38),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'إنشاء الحصة وبدء البث 🚀',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                fontFamily: 'Cairo',
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Cancel
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: Text(
                    'إلغاء',
                    style: AppTheme.label.copyWith(color: AppTheme.textMedium),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
