import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../teacher/sessions/model/live_response_model.dart';
import '../models.dart';
import 'components/recording_button.dart';
import 'sessions_provider.dart';

class StudentSessionsScreen extends StatefulWidget {
  final int courseId;
  final String courseTitle;

  const StudentSessionsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  State<StudentSessionsScreen> createState() => _StudentSessionsScreenState();
}

class _StudentSessionsScreenState extends State<StudentSessionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentSessionsProvider>().fetchSessions(widget.courseId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
            child: Column(children: [
          ScreenAppBar(title: 'الدروس — ${widget.courseTitle}'),
          // Tab strip: الكل / مسجّلة / مباشرة
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            ),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(context.colors.radiusMedium),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: context.colors.textMedium,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'الكل'), Tab(text: 'مسجّلة / مباشرة')],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
              child: TabBarView(controller: _tabs, children: [
            _SessionList(courseId: widget.courseId, filter: 'all'),
            _SessionList(courseId: widget.courseId, filter: 'typed'),
          ])),
        ])),
      ),
    );
  }
}

// ── Session List ──────────────────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  final int courseId;
  final String filter; // 'all' | 'typed'
  const _SessionList({required this.courseId, required this.filter});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentSessionsProvider>();

    if (provider.isLoading && provider.sessions.isEmpty) {
      return  Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(context.colors.primary)));
    }

    final sessions = filter == 'all'
        ? provider.sessions
        : provider
            .sessions; // both types shown in one list with section headers

    if (sessions.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
         Icon(Icons.video_library_outlined,
            size: 64, color: context.colors.textLight),
        const SizedBox(height: 12),
        Text('لا توجد دروس بعد', style: context.colors.body)
      ]));
    }

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => provider.fetchSessions(courseId),
      child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          physics: const BouncingScrollPhysics(),
          itemCount: sessions.length,
          itemBuilder: (_, i) {
            final s = sessions[i];
            final showHeader = filter == 'typed' &&
                (i == 0 || (sessions[i - 1].isLive != s.isLive));
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader) ...[
                    Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                            s.isLive
                                ? '🔴 الحصص المباشرة'
                                : '▶ الدروس المسجّلة',
                            style: context.colors.h3.copyWith(
                                color: s.isLive
                                    ? context.colors.danger
                                    : context.colors.primary))),
                  ] else
                    const SizedBox(height: 12),
                  _SessionCard(session: s),
                ]);
          }),
    );
  }
}

// ── Session Card — matches the design ────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final SessionModel session;

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final isLive = session.isLive;
    final isCompleted = session.isCompleted;
    final checkedIn =
        context.watch<StudentSessionsProvider>().isCheckedIn(session.id);

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(context.colors.radiusMedium),
          boxShadow: context.colors.cardShadow,
          border: isCompleted
              ? Border.all(color: context.colors.success.withValues(alpha: 0.4))
              : isLive && checkedIn
                  ? Border.all(color: context.colors.danger.withValues(alpha: 0.5))
                  : null,
        ),
        child: Row(children: [
          // ── Right side: thumbnail with number badge ─────────────────────
          Stack(children: [
            ClipRRect(
              borderRadius:  BorderRadius.only(
                  topRight: Radius.circular(context.colors.radiusMedium),
                  bottomRight: Radius.circular(context.colors.radiusMedium)),
              child: Container(
                width: 100,
                height: 100,
                color: isLive ? Colors.red.shade900 : const Color(0xFF1E1B5E),
                child: Stack(alignment: Alignment.center, children: [
                  // Background texture
                  Positioned.fill(
                      child: Opacity(
                          opacity: 0.3,
                          child: Icon(
                              isLive
                                  ? Icons.live_tv_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 60,
                              color: Colors.white))),
                  // Course image placeholder (use AppNetworkImage in production)
                  const SizedBox.shrink(),
                ]),
              ),
            ),
            // Number badge
            Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      gradient: isLive
                          ? const LinearGradient(
                              colors: [Colors.redAccent, Color(0xFFFF6B6B)])
                          : context.colors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2))
                      ]),
                  child: Center(
                      child: Text(session.order.toString().padLeft(2, '0'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo'))),
                )),
            // Completed check
            if (isCompleted)
              Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                      width: 22,
                      height: 22,
                      decoration:  BoxDecoration(
                          color: context.colors.success, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14))),
          ]),

          // ── Left side: info ──────────────────────────────────────────────
          Expanded(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Title
              Text(session.name,
                  style: context.colors.h3.copyWith(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              // Duration
              Row(children: [
                 Icon(Icons.access_time_rounded,
                    size: 13, color: context.colors.textLight),
                const SizedBox(width: 4),
                Text('${session.durationMinutes} دقيقه',
                    style: context.colors.caption),
              ]),
              // Scheduled date
              if (session.scheduledAt != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                   Icon(Icons.calendar_month_rounded,
                      size: 13, color: context.colors.textLight),
                  const SizedBox(width: 4),
                  Text(session.scheduledLabel, style: context.colors.caption),
                ]),
              ],
              const SizedBox(height: 8),
              // Bottom row: type badge + status
              Row(children: [
                _TypeBadge(isLive: isLive),
                const SizedBox(width: 6),
                if (isCompleted)
                  _Badge('مكتمل', context.colors.success)
                else if (checkedIn && isLive)
                  _Badge('● مباشر', context.colors.danger),
              ]),
              // Check-in / check-out for live sessions
              if (isLive) ...[
                const SizedBox(height: 8),
                _AttendanceRow(session: session),
              ],
              RecordingButton(recordingUrl: session.recordingUrl)
            ]),
          )),
        ]),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final provider = context.read<StudentSessionsProvider>();
    if (session.isLive) {
      // Get join URL and launch
      final LiveResponseModel? liveResponseModel =
          await provider.joinLive(session.id);
      if (liveResponseModel != null && context.mounted) {
        await _launchUrl(context, liveResponseModel.url);
      } else if (context.mounted) {
        _snack(context, 'الحصة المباشرة غير متاحة الآن', context.colors.danger);
      }
    } else {
      // Recorded — track view
      await provider.trackView(session.id);
      if (session.hasRecording && context.mounted) {
        final uri = Uri.parse(session.recordingUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else if (!session.isCompleted && context.mounted) {
        // Offer to mark complete
        final ok = await showDialog<bool>(
            context: context,
            builder: (_) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('هل شاهدت هذا الدرس؟',
                        style: TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                    content: Text('هل تريد تحديد "${session.name}" كمكتمل؟',
                        style: const TextStyle(fontFamily: 'Cairo')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child:  Text('لاحقاً',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: context.colors.textMedium))),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.success,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('نعم، مكتمل',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700))),
                    ])));
        if (ok == true && context.mounted) {
          await context
              .read<StudentSessionsProvider>()
              .markComplete(session.id);
        }
      }
    }
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) _snack(context, 'تعذر فتح الرابط', context.colors.danger);
  }

  void _snack(BuildContext ctx, String msg, Color c) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: c,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}

// ── Attendance Row  (check-in / check-out) ────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  final SessionModel session;

  const _AttendanceRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentSessionsProvider>();
    final inSession = provider.isCheckedIn(session.id);

    return Row(children: [
      if (!inSession)
        _SmallBtn('تسجيل الحضور', Icons.login_rounded, context.colors.success,
            () async {
          await provider.checkIn(session.id);
          if (context.mounted) {
            _snack(context, 'تم تسجيل حضورك ✓', context.colors.success);
          }
        })
      else
        _SmallBtn('تسجيل المغادرة', Icons.logout_rounded, context.colors.danger,
            () async {
          await provider.checkOut(session.id);
          if (context.mounted) {
            _snack(context, 'تم تسجيل مغادرتك', context.colors.primary);
          }
        }),
    ]);
  }

  void _snack(BuildContext ctx, String msg, Color c) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: c,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700))
          ])));
}

class _TypeBadge extends StatelessWidget {
  final bool isLive;

  const _TypeBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(isLive ? '🔴 مباشر' : '▶ مسجّل',
            style: context.colors.caption
                .copyWith(color: c, fontWeight: FontWeight.w700)));
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(text,
          style: context.colors.caption
              .copyWith(color: color, fontWeight: FontWeight.w700)));
}
