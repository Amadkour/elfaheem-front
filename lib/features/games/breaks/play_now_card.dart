// lib/features/games/breaks/play_now_card.dart — Games v4 T75: "Play now" for a course page.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/games/breaks/breaks_service.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';

/// Plain values: the card (icon, line, button).
class PlayNowCardView extends StatelessWidget {
  const PlayNowCardView({super.key, required this.onPlay, this.busy = false});
  final VoidCallback onPlay;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(children: [
        const Icon(Icons.sports_esports_rounded),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(breakText('خذ استراحة بلعبة سريعة', 'Take a break with a quick game'),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600)),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(child: AppButton(label: breakText('العب الآن', 'Play now'), onPressed: busy ? null : onPlay, busy: busy)),
      ]),
    );
  }
}

/// Draws nothing unless the super admin switched "Play now" on (and the kill switch is off).
class PlayNowCard extends StatefulWidget {
  const PlayNowCard({super.key, required this.courseId, this.api});
  final int courseId;
  final GamesV4Api? api;

  @override
  State<PlayNowCard> createState() => _PlayNowCardState();
}

class _PlayNowCardState extends State<PlayNowCard> {
  bool _on = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BreaksService.instance.config(api: widget.api).then((c) {
      if (mounted && c.playNow) setState(() => _on = true);
    });
  }

  Future<void> _play() async {
    setState(() => _busy = true);
    try {
      final ok = await openSuggestedGame(context, courseId: widget.courseId, api: widget.api);
      if (!ok && mounted) showAppNotice(breakText('لا توجد لعبة متاحة الآن', 'No game available right now'));
    } catch (_) {
      if (mounted) showAppNotice(breakText('تعذر فتح اللعبة', 'Could not open the game'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _on ? PlayNowCardView(onPlay: _play, busy: _busy) : const SizedBox.shrink();
}
