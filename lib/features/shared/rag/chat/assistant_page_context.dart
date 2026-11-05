// "Ask about this page" for the Info panel (workstream f3 calls it): opens the app assistant on a NEW chat with a
// starter question already typed in the box (not sent) — the person reads it, edits it or presses send.
//
// The page id is NOT sent to the server: `POST /rag/ask` has no `page_id` field yet. It stays client-side as the
// prefilled question; when the server accepts a page context, pass [pageId] to `RagApi.ask` here (one place).
import 'package:flutter/widgets.dart';

import '../../../admin/admin_common.dart' show t;
import '../app_assistant.dart' show AppAssistant;

/// The question typed into the box for a page called [pageTitle] (the page id when it has no title).
String ragPageQuestion({required String pageId, String? pageTitle}) {
  final title = (pageTitle ?? '').trim();
  final name = title.isEmpty ? pageId : title;
  return t('اسأل عن هذه الصفحة: $name', 'Ask about this page: $name');
}

/// Opens the app assistant for [pageId] (an `AppRoutes` page id). Does nothing when the assistant is not available
/// for this person (signed out, a guest, switched off).
void openAssistantForPage(BuildContext context, {required String pageId, String? pageTitle}) {
  if (!AppAssistant.availableFor(context)) return;
  AppAssistant.ask(ragPageQuestion(pageId: pageId, pageTitle: pageTitle));
}
