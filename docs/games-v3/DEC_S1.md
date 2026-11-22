# Games v3, stream S1 decisions (motion, engines, sounds): D-1740..D-1749

The lead folds these into `docs/DECISIONS.md`.

**D-1740: one motion vocabulary for the games, all from tokens.** `lib/features/games/shell/game_motion.dart` derives
tap / snap / settle / celebrate / stagger / hold from `AppMotion.of(context)` (so Reduce motion and `app.animations`
zero them) and holds the shared moves: `GameShake`, `GamePulse`, `GamePopIn`, `GameDraggable` + `GameDragOffset`,
`GameFlight`, `GameComboChip`; `game_tile.dart` is `GameTile` (idle / selected / correct / wrong / locked / hint +
hover), the learn kit's look with the games' moves; the learn kit itself is unchanged. `AppBorder.line = 3` is the
connector stroke. A move's wrapper is always in the tree (the identity when idle), so starting or ending a move never
remounts the child (a remount reset the memory card's flip).

**D-1741: sounds through one seam, `GameFeedback.play(GameSound)`** (`shell/game_sounds.dart`, exported from
`game_shell.dart`; only that file imports `audioplayers`). Eight synthesized MP3s (`tool/gen_game_sounds.py`, MP3 only
by default now; `--ogg` writes OGG copies that are never shipped), 29 KB in total. Players are made by the first shell
that opens (on the web at the first touch inside a shell), one low-latency player per sound, released when the last
shell closes; muted = no player at all. Android: usage `game`, content `sonification`, no audio focus; iOS: the
`ambient` category. Under a test binding the default factory makes no player.

**D-1742: `hold` stays 600 ms under Reduce motion.** Every motion token is zero there, but `hold` is how long a wrong
state stays readable (two memory cards that do not belong, a wrong match), which is reading time, not motion.

**D-1743: the combo and its sound.** The shell counts right answers in a row (`streak`). From 3 the header shows
`×n` (it bumps on each new one) and the burst has 24 particles instead of 16. The `combo` sound replaces `correct` on
every third right answer in a row (3, 6, 9 …), so the two never play together. The combo adds no points.

**D-1744: sacred categories.** `quran` / `tajweed` (from the game's category, through `GameRound(category:)`): no
tile in the round shakes (the content may be an ayah, and we cannot tell which tile holds one), no live drag line
crosses the tiles, and the `wrong` sound is skipped (vibration + colour + icon only). Bursts stay in the header.

**D-1745: drag next to tap, not instead.** Match: a long press (touch) or a plain drag (mouse) on a tile draws a live
line to the finger; letting go on a tile of the other side is the same try as two taps. Order: the placed rows drag to
reorder (neighbours slide aside over `snap`, the row snaps into the gap), with Move up / Move down for screen
readers; tapping still places and takes back. A long press on touch, so a swipe still scrolls the page.

**D-1746: flights decorate, they never gate.** In fill_blank and word_puzzle the answer is settled at the tap; the
flying copy (overlay, transform only) lands afterwards and only then does the blank / slot show its letter. Logic,
tests and screen readers never wait on a flight, and a fast player can tap ahead.

**D-1747: the trace lives in the shell controller.** `GameShellController.record(i, a)` with `ms` from a stopwatch
started when the round's controller is made; `GameRound(onTrace:)` hands it over just before `onFinished`. Content
indices only (CONTRACT §3). A typed fill_blank answer is sent as typed (the server trims), a picked option as written.

**D-1748: ranked rounds never block play.** `GamePlayPage` asks `POST /games/{id}/rounds` when each round starts
(not for a guest, not with `games.champions` off); any error or a late answer = the round is unranked, exactly as
before. A ranked play is posted to the plays route directly, because the outbox's sync route has no `round_id` /
`trace`; only when that post is lost on the network does the play fall back to the outbox (then unranked). The finish
view shows "Rank N today" only when the server says `ranked: true`.

**D-1749: no sound while a live room is open; video needs no rule.** `LiveRoomHost.isOpen` (a minimized room floats
over the games) silences the games. The course video is a full page pushed over the game, so no game tap can happen
under it. The super admin's "Sound check" (the games admin page's app bar) plays each sound through the same seam,
ignoring the mute and the live-room rule but not the `games.sounds` switch, so the owner can audition the set.

Snapshots: `test/contract/api_paths.json` gains `POST /api/v1/games/{game_id:int}/rounds` and
`test/contract/feature_keys.json` gains `games.champions` and `games.sounds` by hand (S3 adds both to the catalog;
the lead's regeneration gives the same lines).
