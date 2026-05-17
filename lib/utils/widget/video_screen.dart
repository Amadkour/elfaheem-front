import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:video_player/video_player.dart';

// ─── Theme Constants ────────────────────────────────────────────────
class _AppColors {
  static const background = Color(0xFF0A0C14);
  static const surface = Color(0xFF12151F);
  static const surfaceElevated = Color(0xFF1A1E2E);
  static const border = Color(0xFF252A3D);
  static const accent = Color(0xFF6C63FF);
  static const accentGlow = Color(0x336C63FF);
  static const accentSecondary = Color(0xFF00D4AA);
  static const textPrimary = Color(0xFFF0F2FF);
  static const textSecondary = Color(0xFF8890B5);
  static const textMuted = Color(0xFF4A5175);
  static const live = Color(0xFFFF4567);
  static const liveGlow = Color(0x33FF4567);
  static const recorded = Color(0xFF00D4AA);
  static const scheduled = Color(0xFFFFB830);
}

// ─── Main Screen ─────────────────────────────────────────────────────
class VideoScreen extends StatelessWidget {
  const VideoScreen({
    super.key,
    required this.uri,
    required this.session,
  });

  final Uri uri;
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _AppColors.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
            return isWide
                ? _WideLayout(uri: uri, session: session)
                : _NarrowLayout(uri: uri, session: session);
          },
        ),
      ),
    );
  }
}

// ─── Wide (Web/Tablet) Layout ─────────────────────────────────────────
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.uri, required this.session});
  final Uri uri;
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _PremiumAppBar(session: session),
              Expanded(
                child: _VideoPlayer(uri: uri),
              ),
            ],
          ),
        ),
        Container(
          width: 360,
          decoration: const BoxDecoration(
            color: _AppColors.surface,
            border: Border(
              left: BorderSide(color: _AppColors.border),
            ),
          ),
          child: _SessionInfoPanel(session: session),
        ),
      ],
    );
  }
}

// ─── Narrow (Mobile) Layout ───────────────────────────────────────────
class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.uri, required this.session});
  final Uri uri;
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PremiumAppBar(session: session),
        _VideoPlayer(uri: uri),
        Expanded(
          child: _SessionInfoPanel(session: session),
        ),
      ],
    );
  }
}

// ─── App Bar ──────────────────────────────────────────────────────────
class _PremiumAppBar extends StatelessWidget {
  const _PremiumAppBar({required this.session});
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left: 8,
        right: 16,
      ),
      decoration: const BoxDecoration(
        color: _AppColors.surface,
        border: Border(
          bottom: BorderSide(color: _AppColors.border),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session ${session.order}',
                  style: const TextStyle(
                    color: _AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.name,
                  style: const TextStyle(
                    color: _AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (session.isLiveActive) _LiveBadge(),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color.lerp(
            _AppColors.liveGlow,
            _AppColors.live.withValues(alpha:0.25),
            _pulse.value,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _AppColors.live, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _AppColors.live,
                boxShadow: [
                  BoxShadow(
                    color: _AppColors.live,
                    blurRadius: _pulse.value * 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'LIVE',
              style: TextStyle(
                color: _AppColors.live,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Video Player ─────────────────────────────────────────────────────
class _VideoPlayer extends StatefulWidget {
  const _VideoPlayer({required this.uri});
  final Uri uri;

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  late VideoPlayerController _controller;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      widget.uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      viewType: VideoViewType.textureView,
    );
    _controller.addListener(() => setState(() {}));
    _controller.setLooping(true);
    _controller.initialize().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleControls() {
    if(mounted) setState(() => _showControls = !_showControls);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isInit = _controller.value.isInitialized;

    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: isInit ? _controller.value.aspectRatio : 16 / 9,
        child: isInit
            ? GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(_controller),
              // Gradient overlay
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x88000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                      stops: [0, 0.3, 0.6, 1],
                    ),
                  ),
                ),
              ),
              // Center play/pause
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black45,
                        border: Border.all(
                            color: Colors.white24, width: 1.5),
                      ),
                      child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom controls bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress bar
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                            activeTrackColor: _AppColors.accent,
                            inactiveTrackColor:
                            Colors.white.withValues(alpha:0.2),
                            thumbColor: Colors.white,
                            overlayColor:
                            _AppColors.accent.withValues(alpha:0.2),
                          ),
                          child: Slider(
                            value: _controller.value.position.inSeconds
                                .toDouble(),
                            max: _controller.value.duration.inSeconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            onChanged: (v) {
                              _controller.seekTo(
                                  Duration(seconds: v.toInt()));
                            },
                          ),
                        ),
                        // Time & speed row
                        Row(
                          children: [
                            Text(
                              _formatDuration(
                                  _controller.value.position),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const Text(' / ',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11)),
                            Text(
                              _formatDuration(
                                  _controller.value.duration),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            _SpeedSelector(controller: _controller),
                            const SizedBox(width: 8),
                            _FullscreenButton(
                                controller: _controller),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Closed caption
              if (_controller.value.caption.text.isNotEmpty)
                Positioned(
                  bottom: 60,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _controller.value.caption.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
        )
            : const Center(
          child: CircularProgressIndicator(
            color: _AppColors.accent,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.controller});
  final VideoPlayerController controller;

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: controller.value.playbackSpeed,
      tooltip: 'Playback speed',
      color: _AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _AppColors.border),
      ),
      onSelected: controller.setPlaybackSpeed,
      itemBuilder: (_) => speeds
          .map((s) => PopupMenuItem<double>(
        value: s,
        child: Text(
          '${s}x',
          style: TextStyle(
            color: s == controller.value.playbackSpeed
                ? _AppColors.accent
                : _AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          '${controller.value.playbackSpeed}x',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Fullscreen logic can be added with a fullscreen package
      },
      child: const Icon(Icons.fullscreen_rounded,
          color: Colors.white70, size: 20),
    );
  }
}

// ─── Session Info Panel ───────────────────────────────────────────────
class _SessionInfoPanel extends StatelessWidget {
  const _SessionInfoPanel({required this.session});
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SessionHeader(session: session),
          const SizedBox(height: 20),
          _SessionStatsRow(session: session),
          const SizedBox(height: 20),
          if (session.description != null && session.description!.isNotEmpty)
            _DescriptionCard(description: session.description!),
          const SizedBox(height: 16),
          _SessionMetaList(session: session),
          const SizedBox(height: 20),
          if (session.roomUrl != null || session.recordingUrl != null)
            _ActionButtons(session: session),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});
  final TeacherSessionItem session;

  Color get _statusColor {
    if (session.isLiveActive) return _AppColors.live;
    if (session.recordingStatus == 'ready') return _AppColors.recorded;
    if (session.scheduledAt != null) return _AppColors.scheduled;
    return _AppColors.textMuted;
  }

  String get _statusLabel {
    if (session.isLiveActive) return 'Live Now';
    if (session.recordingStatus == 'ready') return 'Recorded';
    if (session.recordingStatus == 'processing') return 'Processing';
    if (session.scheduledAt != null) return 'Scheduled';
    return 'Draft';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                Border.all(color: _statusColor.withValues(alpha:0.4)),
              ),
              child: Text(
                _statusLabel.toUpperCase(),
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (session.type != null)
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _AppColors.accent.withValues(alpha:0.4)),
                ),
                child: Text(
                  session.type!.toUpperCase(),
                  style: const TextStyle(
                    color: _AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          session.name,
          style: const TextStyle(
            color: _AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _SessionStatsRow extends StatelessWidget {
  const _SessionStatsRow({required this.session});
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.border),
      ),
      child: Row(
        children: [
          _StatCell(
            icon: Icons.timer_outlined,
            label: 'Duration',
            value: '${session.durationMinutes} min',
          ),
          _VerticalDivider(),
          _StatCell(
            icon: Icons.format_list_numbered_rounded,
            label: 'Order',
            value: '#${session.order}',
          ),
          _VerticalDivider(),
          _StatCell(
            icon: Icons.folder_outlined,
            label: 'Course ID',
            value: '${session.courseId}',
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: _AppColors.accent, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: _AppColors.textMuted,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: _AppColors.border,
    );
  }
}

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.description});
  final String description;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ABOUT THIS SESSION',
          style: TextStyle(
            color: _AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedCrossFade(
          firstChild: Text(
            widget.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AppColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          secondChild: Text(
            widget.description,
            style: const TextStyle(
              color: _AppColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () { if(mounted) setState(() => _expanded = !_expanded);},
          child: Text(
            _expanded ? 'Show less' : 'Show more',
            style: const TextStyle(
              color: _AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionMetaList extends StatelessWidget {
  const _SessionMetaList({required this.session});
  final TeacherSessionItem session;

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day} ${_monthName(dt.month)} ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _monthName(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _AppColors.border),
      ),
      child: Column(
        children: [
          _MetaTile(
            icon: Icons.calendar_today_outlined,
            label: 'Scheduled',
            value: _formatDate(session.scheduledAt),
            highlight: session.scheduledAt != null,
          ),
          _MetaDivider(),
          _MetaTile(
            icon: Icons.access_time_rounded,
            label: 'Created',
            value: _formatDate(session.createdAt),
          ),
          _MetaDivider(),
          _MetaTile(
            icon: Icons.videocam_outlined,
            label: 'Recording',
            value: session.recordingStatus?.toUpperCase() ?? 'N/A',
            valueColor: _recordingColor(session.recordingStatus),
          ),
          if (session.isLiveActive) ...[
            _MetaDivider(),
            _MetaTile(
              icon: Icons.wifi_tethering_rounded,
              label: 'Live Status',
              value: 'STREAMING NOW',
              valueColor: _AppColors.live,
            ),
          ],
        ],
      ),
    );
  }

  Color _recordingColor(String? status) {
    switch (status) {
      case 'ready':
        return _AppColors.recorded;
      case 'processing':
        return _AppColors.scheduled;
      default:
        return _AppColors.textMuted;
    }
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon,
              color: highlight ? _AppColors.accent : _AppColors.textMuted,
              size: 16),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: _AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: _AppColors.border,
      indent: 44,
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.session});
  final TeacherSessionItem session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (session.isLiveActive && session.roomUrl != null)
          _PremiumButton(
            label: 'Join Live Room',
            icon: Icons.wifi_tethering_rounded,
            isPrimary: true,
            onTap: () {
              // Navigate to room URL
            },
          ),
        if (session.recordingUrl != null) ...[
          const SizedBox(height: 10),
          _PremiumButton(
            label: 'Watch Recording',
            icon: Icons.play_circle_outline_rounded,
            isPrimary: false,
            onTap: () {
              // Navigate to recording
            },
          ),
        ],
      ],
    );
  }
}

class _PremiumButton extends StatelessWidget {
  const _PremiumButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF9B5DE5)],
          )
              : null,
          color: isPrimary ? null : _AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary
                ? Colors.transparent
                : _AppColors.accent.withValues(alpha:0.3),
          ),
          boxShadow: isPrimary
              ? [
            BoxShadow(
              color: _AppColors.accent.withValues(alpha:0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            )
          ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isPrimary
                    ? Colors.white
                    : _AppColors.accent,
                size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : _AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}