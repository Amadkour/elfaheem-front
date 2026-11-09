// lib/features/shared/chat/chat_new_message.dart — the New message sheet (D-371): recent and suggested people first,
// search as you type, role and context under each name, and a clear state for "direct" vs "request". A person the
// server says needs a request gets the first message written right here (`POST /chat/requests`), so the thread opens
// already holding it. Pure parts (`ChatPeopleView`, `ChatPersonTile`, `ChatRequestComposer`) take plain values and are
// what test/chat/chat_new_message_layout_test.dart pumps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'chat_models.dart';
import 'chat_page.dart' show chatErrorText;
import 'chat_store.dart';
import 'chat_widgets.dart' show ChatAvatar;

/// One client id per composed text: pressing Send again after a lost answer is the same message on the server. Editing
/// the words, or writing to someone else, is a new one.
class ChatComposedId {
  String? _key, _id;

  String idFor(int peerId, String text) {
    final key = '$peerId:$text';
    if (key != _key) {
      _key = key;
      _id = chatNewClientId();
    }
    return _id!;
  }
}

/// The line under a name: how we know each other, the course or organization, else the role.
String chatPersonLine(ChatPersonRow r) {
  final child = r.child?.name.split(' ').first;
  final parts = <String>[
    switch (r.relation) {
      'teacher' => 'chat_rel_teacher'.tr,
      'student' => 'chat_rel_student'.tr,
      'classmate' => 'chat_rel_classmate'.tr,
      'child' => 'chat_rel_child'.tr,
      'parent' => 'chat_rel_parent'.tr,
      'child_teacher' => child == null ? 'chat_person_teacher'.tr : '${'chat_rel_child_teacher'.tr} $child',
      'student_parent' => child == null ? 'chat_person_parent'.tr : '${'chat_rel_student_parent'.tr} $child',
      _ => chatRoleLabel(r.user.role),
    },
    ?r.course?.label,
    if (r.course == null && (r.orgName ?? '').isNotEmpty) r.orgName!,
  ];
  return parts.where((p) => p.isNotEmpty).join(' · ');
}

/// The role under a name when nothing better is known about the two people.
String chatRoleLabel(String role) => switch (role) {
      'student' => 'chat_person_student'.tr,
      'teacher' => 'chat_person_teacher'.tr,
      'parent' => 'chat_person_parent'.tr,
      'admin' || 'super-admin' || 'developer' => 'chat_person_admin'.tr,
      'org-admin' || 'org-staff' => 'chat_person_staff'.tr,
      _ => '',
    };

/// A small pill saying how the chat would start.
class ChatReachPill extends StatelessWidget {
  const ChatReachPill({super.key, required this.reach});
  final ChatReach reach;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (String label, Color color) = switch (reach.state) {
      'direct' => ('chat_nm_reach_direct'.tr, c.success),
      'request' => ('chat_nm_reach_request'.tr, c.accent2),
      'request_sent' => ('chat_nm_reach_sent'.tr, c.textMedium),
      'request_received' => ('chat_nm_reach_received'.tr, c.primary),
      'thread' => ('chat_nm_reach_open'.tr, c.textLight),
      _ => ('', c.textLight),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 112), child: AppBadgePill(label, color: color));
  }
}

/// One person: avatar, name and @username, the line under it, the state at the end.
class ChatPersonTile extends StatelessWidget {
  const ChatPersonTile({super.key, required this.row, required this.onTap});
  final ChatPersonRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocked = row.reach.unavailable;
    final username = row.user.username;
    final line = blocked ? row.reach.reasonText : chatPersonLine(row);
    return Opacity(
      opacity: blocked ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: blocked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
            child: Row(children: [
              ChatAvatar(name: row.user.name, url: row.user.imageUrl, size: 46),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: row.user.name, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
                      if (username != null) TextSpan(text: '  @$username', style: appText(12, w: FontWeight.w400, c: c.textLight)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(line, maxLines: blocked ? 2 : 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w400, c: c.textMedium, h: 1.3)),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              ChatReachPill(reach: row.reach),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.row, required this.onTap});
  final ChatPersonRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChatAvatar(name: row.user.name, url: row.user.imageUrl, size: 50),
            const SizedBox(height: AppSpace.xxs),
            Text(row.user.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: appText(12, w: FontWeight.w500, c: c.textDark)),
          ]),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.sm, AppSpace.xxs, AppSpace.xxs),
      child: Text(text, style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
    );
  }
}

/// The list part of the sheet, from plain values.
class ChatPeopleView extends StatelessWidget {
  const ChatPeopleView({super.key, required this.people, required this.query, required this.onPick});
  final ChatPeople people;
  final String query;
  final ValueChanged<ChatPersonRow> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searching = query.trim().isNotEmpty;
    final results = people.results;
    final short = searching && query.trim().replaceFirst('@', '').length < 2;
    final strangers = results.any((r) => r.reach.needsRequest || r.reach.state == 'unavailable');
    final children = <Widget>[];
    if (searching) {
      if (short) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.sm, AppSpace.xxs, AppSpace.xxs),
          child: Text('chat_nm_short_query'.tr, style: appText(12.5, w: FontWeight.w400, c: c.textMedium)),
        ));
      }
      if (results.isEmpty && !short) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: AppEmpty(icon: Icons.person_search_rounded, title: 'chat_nm_no_results_title'.tr, message: 'chat_nm_no_results_body'.tr),
        ));
      }
      if (results.isNotEmpty) {
        children.add(_SectionTitle('chat_nm_results'.tr));
        children.addAll(results.map((r) => ChatPersonTile(row: r, onTap: () => onPick(r))));
      }
      if (strangers && people.requestsOn) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.sm, AppSpace.xxs, 0),
          child: Text(
            people.requestsLeft > 0
                ? countText(people.requestsLeft,
                    ar1: 'يمكنك إرسال طلب محادثة واحد آخر اليوم',
                    ar2: 'يمكنك إرسال طلبي محادثة آخرين اليوم',
                    arFew: 'يمكنك إرسال {n} طلبات محادثة أخرى اليوم',
                    arMany: 'يمكنك إرسال {n} طلبًا آخر اليوم',
                    en1: 'You can send 1 more message request today',
                    en: 'You can send {n} more message requests today')
                : 'chat_nm_requests_none'.tr,
            style: appText(12, w: FontWeight.w400, c: c.textLight),
          ),
        ));
      }
    } else {
      if (people.recent.isEmpty && people.suggested.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: AppEmpty(icon: Icons.forum_outlined, title: 'chat_nm_empty_title'.tr, message: 'chat_nm_empty_body'.tr),
        ));
      }
      if (people.recent.isNotEmpty) {
        children.add(_SectionTitle('chat_nm_recent'.tr));
        children.add(AppHScroll(
          thumbVisibility: false,
          child: Row(children: [for (final r in people.recent) _RecentChip(row: r, onTap: () => onPick(r))]),
        ));
      }
      if (people.suggested.isNotEmpty) {
        children.add(_SectionTitle('chat_nm_suggested'.tr));
        children.addAll(people.suggested.map((r) => ChatPersonTile(row: r, onTap: () => onPick(r))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// The first message to someone with no link, right in the sheet.
class ChatRequestComposer extends StatelessWidget {
  const ChatRequestComposer({super.key, required this.person, required this.controller, required this.busy, this.error, required this.onSend, required this.onBack});
  final ChatPersonRow person;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onSend;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = person.user.name.split(' ').first;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(icon: Icon(Icons.arrow_back_rounded, color: c.textDark), tooltip: 'chat_back'.tr, onPressed: busy ? null : onBack),
        Expanded(child: Text('chat_nm_request_title'.tr, style: appText(16, w: FontWeight.w700, c: c.textDark))),
      ]),
      const SizedBox(height: AppSpace.xs),
      Row(children: [
        ChatAvatar(name: person.user.name, url: person.user.imageUrl, size: 52),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(person.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
            if (chatRoleLabel(person.user.role).isNotEmpty) Text(chatRoleLabel(person.user.role), style: appText(12.5, w: FontWeight.w400, c: c.textMedium)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppBanner(icon: Icons.mark_chat_unread_outlined, text: 'chat_nm_request_explain'.tr.replaceAll('{name}', first), color: c.accent2),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: controller, label: 'chat_nm_request_first'.tr, hint: 'chat_nm_request_hint'.tr, maxLines: 4),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: 'chat_nm_request_send'.tr, icon: Icons.send_rounded, busy: busy, expand: true, onPressed: busy ? null : onSend),
    ]);
  }
}

/// The sheet: search on top, the list under it; picks a person or holds the first message of a request.
class ChatNewMessageSheet extends StatefulWidget {
  const ChatNewMessageSheet({super.key});

  @override
  State<ChatNewMessageSheet> createState() => _ChatNewMessageSheetState();
}

class _ChatNewMessageSheetState extends State<ChatNewMessageSheet> {
  final _message = TextEditingController();
  ChatPeople? _people;
  String _query = '';
  bool _loading = true;
  String? _error;
  int _seq = 0;
  ChatPersonRow? _requesting;
  bool _sending = false;
  String? _sendError;
  final _composedId = ChatComposedId();

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final mine = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _query = q;
    });
    try {
      final people = await ChatHub.instance.api.people(q: q);
      if (mounted && mine == _seq) {
        setState(() {
          _people = people;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && mine == _seq) {
        setState(() {
          _error = chatErrorText(e);
          _loading = false;
        });
      }
    }
  }

  void _pick(ChatPersonRow r) {
    if (r.reach.needsRequest) {
      setState(() {
        _requesting = r;
        _sendError = null;
      });
      return;
    }
    Navigator.of(context).pop(r.toContact());
  }

  Future<void> _sendRequest() async {
    final r = _requesting;
    final text = _message.text.trim();
    if (r == null || text.isEmpty) {
      setState(() => _sendError = 'chat_nm_request_hint'.tr);
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final conv = await ChatHub.instance.api.sendRequest(peerId: r.user.id, clientId: _composedId.idFor(r.user.id, text), body: text);
      if (!mounted) return;
      showAppNotice('chat_nm_request_done'.tr);
      Navigator.of(context).pop(ChatContact(user: r.user, conversationId: conv.id));
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendError = chatErrorText(e);
        });
      }
    }
  }

  Widget _list() {
    final p = _people;
    if (_error != null && p == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: 'chat_retry'.tr, onAction: () => _load(_query));
    }
    if (p == null || (_loading && p.results.isEmpty && p.recent.isEmpty && p.suggested.isEmpty)) {
      return const AppListSkeleton(items: 5);
    }
    return ChatPeopleView(people: p, query: _query, onPick: _pick);
  }

  @override
  Widget build(BuildContext context) {
    final requesting = _requesting;
    final motion = AppMotion.of(context).base;
    final body = requesting != null
        ? SingleChildScrollView(
            padding: AppSheetContent.padding,
            child: ChatRequestComposer(person: requesting, controller: _message, busy: _sending, error: _sendError, onSend: _sendRequest, onBack: () => setState(() => _requesting = null)),
          )
        : LayoutBuilder(builder: (context, box) {
            final search = Padding(
              padding: EdgeInsets.fromLTRB(AppSheetContent.padding.left, 0, AppSheetContent.padding.left, AppSpace.xs),
              child: AppSearchField(hint: 'chat_nm_search_hint'.tr, autofocus: true, onChanged: _load, debounce: const Duration(milliseconds: 280)),
            );
            // a keyboard on a short screen leaves little room: everything scrolls together then
            if (box.maxHeight < 160) {
              return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, Padding(padding: AppSheetContent.padding, child: _list())]));
            }
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              search,
              Flexible(child: SingleChildScrollView(padding: AppSheetContent.padding, child: _list())),
            ]);
          });
    return LayoutBuilder(builder: (context, box) {
      final bounded = box.maxHeight.isFinite;
      final content = SizedBox(
        height: bounded ? math.min(560.0, math.max(0.0, box.maxHeight - 90)) : 480,
        child: AnimatedSwitcher(
          duration: motion,
          // the default centres a child shorter than the box: a blank band above the search and the request form
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(requesting?.user.id ?? 0), child: body),
        ),
      );
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('chat_new_message'.tr),
        if (bounded) Flexible(child: content) else content,
      ]);
    });
  }
}
