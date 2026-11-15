// lib/design/app_errors.dart
//
// Actionable errors (UX v3 phase 1): one place that turns an [ApiException] into words a person can act on.
//
//   AppErrorBox(error: e, onRetry: _load, onFix: _addAndSave, fixLabel: '…')   the inline card, wording per kind
//   showAppError(context, e, onRetry: _load)                                   a notice (Retry / Copy code action)
//   final fe = FieldErrors(aliases: {'head_user_id': 'head'});                 a form's server field errors:
//     fe.take(e)  →  fe.errorFor('head')  →  errorText: of the field; fe.keyFor('head') on the field's wrapper;
//     fe.summary (several bad fields) above the form; fe.revealFirst() scrolls to and focuses the first one.
//   AppFixActions.register('open_members', handler)                           an app-wide fix for a server fix_action
//   AppFixScope(fixes: {'pick_reassign': (focusPicker, 'Choose the unit')})    a screen's own fix (wins over the app's)
//
// The server half sends `detail: {code, message, message_en, kind, field?, fields?, fix?, fix_en?, fix_action?,
// ref?}`; older servers send less, and every value falls back (ApiException derives kind from the status).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/personal_access.dart' show PersonalAccess, enablePersonalFix, enablePersonalLabel;
import 'app_buttons.dart';
import 'app_notice.dart';
import 'app_tokens.dart';

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The icon of an error kind.
IconData appErrorIcon(ApiErrorKind k) => switch (k) {
      ApiErrorKind.validation => Icons.edit_note_rounded,
      ApiErrorKind.permission => Icons.lock_outline_rounded,
      ApiErrorKind.conflict => Icons.sync_problem_rounded,
      ApiErrorKind.notFound => Icons.search_off_rounded,
      ApiErrorKind.rateLimit => Icons.hourglass_top_rounded,
      ApiErrorKind.network => Icons.wifi_off_rounded,
      ApiErrorKind.server => Icons.report_gmailerrorred_rounded,
      ApiErrorKind.unknown => Icons.error_outline_rounded,
    };

/// The title line of an error kind, in the current language.
String appErrorTitle(ApiErrorKind k) => switch (k) {
      ApiErrorKind.validation => _tx('راجع الحقل المحدَّد', 'Check the highlighted field'),
      ApiErrorKind.permission => _tx('ليست لديك صلاحية لهذا الإجراء', "You don't have the rights for this"),
      ApiErrorKind.conflict => _tx('يتعارض هذا مع بيانات موجودة', 'This clashes with existing data'),
      ApiErrorKind.notFound => _tx('لم يُعثر عليه — ربما حُذف', 'Not found: it may have been removed'),
      ApiErrorKind.rateLimit => _tx('محاولات كثيرة — انتظر لحظة', 'Too many tries: wait a moment'),
      ApiErrorKind.network => _tx('لا يوجد اتصال', 'No connection'),
      ApiErrorKind.server => _tx('حدث خطأ من جهتنا', 'Something went wrong on our side'),
      ApiErrorKind.unknown => _tx('تعذّر إكمال الطلب', 'That did not go through'),
    };

/// The body text of [e]: the server's (coded) words, else a sentence per kind. [text] overrides it (orgErrorText).
String appErrorBody(ApiException e, {String? text}) {
  if (text != null && text.trim().isNotEmpty) return text;
  switch (e.kind) {
    case ApiErrorKind.permission:
      return e.code != null ? e.message : _tx('اطلب الصلاحية من مدير المؤسسة.', 'Ask the institution admin to give you access.');
    case ApiErrorKind.network:
      return _tx('تحقق من الإنترنت ثم أعد المحاولة.', 'Check your internet, then try again.');
    case ApiErrorKind.server:
      return _tx('أعد المحاولة بعد قليل. إن تكرر الخطأ فأرسل الرمز أدناه إلى الدعم.',
          'Try again in a moment. If it keeps happening, send the code below to support.');
    default:
      return e.message;
  }
}

/// The inline error card: an icon and a title per kind, the server's text, its fix sentence, then the actions:
/// [onFix] (a one-tap fix the caller can run, labelled [fixLabel]), Retry ([onRetry], network and server), and on a
/// server error the reference id with a copy button ("Send this code to support").
class AppErrorBox extends StatelessWidget {
  const AppErrorBox({super.key, required this.error, this.text, this.onRetry, this.onFix, this.fixLabel, this.busy = false});

  final ApiException error;

  /// Replaces the body text (e.g. orgErrorText(error)); null = the server's words.
  final String? text;
  final VoidCallback? onRetry, onFix;
  final String? fixLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shared = onFix == null ? appSharedFix(error, onRetry: onRetry, context: context) : null;
    final fixTap = onFix ?? shared?.$1;
    final k = error.kind;
    final tone = switch (k) {
      ApiErrorKind.network || ApiErrorKind.rateLimit || ApiErrorKind.notFound => c.warning,
      _ => c.danger,
    };
    final body = appErrorBody(error, text: text);
    final fix = error.fix;
    final ref = error.ref;
    final retry = onRetry != null && (k == ApiErrorKind.network || k == ApiErrorKind.server || k == ApiErrorKind.unknown);
    final title = appErrorTitle(k);
    return Semantics(
      container: true,
      liveRegion: true,
      // one announcement: the title, the body and the fix; the buttons below stay their own focus stops
      label: [title, if (body.trim().isNotEmpty && body != title) body, if (fix != null && !body.contains(fix)) fix].join('. '),
      child: Container(
        key: const ValueKey('app_error_box'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: tone.withValues(alpha: 0.35), width: AppBorder.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(appErrorIcon(k), color: tone, size: AppIconSize.md),
            AppSpace.gapXs,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appErrorTitle(k), style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                if (body.trim().isNotEmpty && body != appErrorTitle(k)) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(body, style: AppType.body(context).copyWith(color: c.textDark)),
                ],
                if (fix != null && !body.contains(fix)) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(fix, style: AppType.label(context).copyWith(color: c.textMedium)),
                ],
              ]),
            ),
          ]),
          ),
          if (ref != null) ...[
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_tx('أرسل هذا الرمز إلى الدعم:', 'Send this code to support:'), style: AppType.meta(context).copyWith(color: c.textMedium)),
              SelectableText(ref, key: const ValueKey('app_error_ref'), style: AppType.label(context).copyWith(color: c.textDark)),
              IconButton(
                key: const ValueKey('app_error_copy'),
                tooltip: _tx('نسخ الرمز', 'Copy the code'),
                icon: const Icon(Icons.copy_rounded, size: AppIconSize.sm),
                onPressed: () => copyErrorRef(ref),
              ),
            ]),
          ],
          if (fixTap != null || retry) ...[
            AppSpace.gapXs,
            // focus order: the fix first, then Retry (reading order in both directions)
            FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              if (fixTap != null)
                AppButton.primary(
                    key: const ValueKey('app_error_fix'),
                    size: AppButtonSize.sm,
                    icon: Icons.auto_fix_high_rounded,
                    label: fixLabel ?? shared?.$2 ?? _tx('أصلحه', 'Fix it'),
                    busy: busy,
                    onPressed: busy ? null : fixTap),
              if (retry)
                AppButton.tonal(
                    key: const ValueKey('app_error_retry'),
                    size: AppButtonSize.sm,
                    icon: Icons.refresh_rounded,
                    label: _tx('إعادة المحاولة', 'Retry'),
                    onPressed: busy ? null : onRetry),
            ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The fixes the app runs itself, whatever screen got the error (fix_action → handler + label), in this order:
/// `enable_personal` (403 personal_off: turns the personal profile on, then retries [onRetry]); the screen's own
/// [AppFixScope] around [context]; the app-wide [AppFixActions] (the org module's open_members · open_agenda ·
/// setup_councils · pick_reassign). Null = none.
(VoidCallback, String)? appSharedFix(ApiException e, {VoidCallback? onRetry, BuildContext? context}) {
  if (e.fixAction == PersonalAccess.fixAction || e.code == PersonalAccess.offCode) {
    return (() => enablePersonalFix(onRetry: onRetry), enablePersonalLabel());
  }
  final act = e.fixAction;
  if (act == null) return null;
  final local = context == null ? null : AppFixScope.maybeOf(context)?[act];
  if (local != null) return local;
  return AppFixActions.of(act)?.call(e, context, onRetry);
}

/// An app-wide fix for one server `fix_action`: the handler and its button label, or null when this error offers
/// none (e.g. the target is unknown). [context] is the screen's when there is one (it may be gone by the tap).
typedef AppFixHandler = (VoidCallback, String)? Function(ApiException e, BuildContext? context, VoidCallback? onRetry);

/// The app-wide fix actions: a feature registers its own once (the org module in OrgSession's constructor), so any
/// [AppErrorBox] / [showAppError] carrying that fix_action gets a working button.
class AppFixActions {
  AppFixActions._();
  static final Map<String, AppFixHandler> _handlers = {};

  static void register(String action, AppFixHandler handler) => _handlers[action] = handler;
  static void unregister(String action) => _handlers.remove(action);
  static bool has(String action) => _handlers.containsKey(action);
  static AppFixHandler? of(String? action) => action == null ? null : _handlers[action];
}

/// A screen's own fixes (fix_action → handler + label), e.g. the archive sheet's `pick_reassign` that focuses its
/// own picker. Wins over [AppFixActions].
class AppFixScope extends InheritedWidget {
  const AppFixScope({super.key, required this.fixes, required super.child});

  final Map<String, (VoidCallback, String)> fixes;

  static Map<String, (VoidCallback, String)>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppFixScope>()?.fixes;

  @override
  bool updateShouldNotify(AppFixScope oldWidget) => oldWidget.fixes != fixes;
}

/// Copies a support reference and says so.
Future<void> copyErrorRef(String ref) async {
  await Clipboard.setData(ClipboardData(text: ref));
  showAppNotice(_tx('نُسخ الرمز', 'Code copied'));
}

/// Shows [error] as a notice: [text] (or the server's words); network + [onRetry] → a Retry action; a one-tap
/// [onFix] → its action ([fixLabel]); a server error with a reference → "Copy code". Use [AppErrorBox] inline when
/// the screen has room for the full card.
void showAppError(BuildContext? context, Object error, {String? text, VoidCallback? onRetry, VoidCallback? onFix, String? fixLabel}) {
  final e = ApiException.from(error);
  final k = e.kind;
  final shared = onFix == null ? appSharedFix(e, onRetry: onRetry, context: context) : null;
  if (shared != null) (onFix, fixLabel) = shared;
  var msg = text ?? (k == ApiErrorKind.network || k == ApiErrorKind.server ? appErrorTitle(k) : e.message);
  final fix = e.fix;
  if (fix != null && !msg.contains(fix)) msg = '$msg — $fix';
  final ref = e.ref;
  if (onFix != null) {
    showAppNotice(msg, error: true, actionLabel: fixLabel ?? _tx('أصلحه', 'Fix it'), onAction: onFix);
  } else if (onRetry != null && (k == ApiErrorKind.network || k == ApiErrorKind.server)) {
    showAppNotice(msg, error: true, icon: appErrorIcon(k), actionLabel: _tx('إعادة المحاولة', 'Retry'), onAction: onRetry);
  } else if (ref != null) {
    showAppNotice('$msg (${_tx('الرمز', 'code')}: $ref)', error: true, actionLabel: _tx('نسخ الرمز', 'Copy code'), onAction: () => copyErrorRef(ref));
  } else {
    showAppNotice(msg, error: true, icon: k == ApiErrorKind.network ? appErrorIcon(k) : null);
  }
}

/// A form's server-side field errors. [aliases] maps a server field name (`secretary_user_id`, `members.2.user_id`
/// → its first segment `members`) to the form's own field id; unmapped names are kept as they come. [codes] maps an
/// error code to a field for older servers that send a code but no `field` (`head_required` → `head`); [actions]
/// maps a server `fix_action` to the field it points at (`pick_head` → `head`). A dotted name matches its longest
/// mapped prefix (`members.0.weight` → `members`), then a mapped last part (`faculty.chair_user_id` →
/// `chair_user_id`); only `body.` is stripped (`query.` stays).
///
/// Register each field with [keyFor] (on the widget around it, in build order = on-screen order) so [revealFirst]
/// can scroll to the first bad one and focus it.
class FieldErrors extends ChangeNotifier {
  FieldErrors({this.aliases = const {}, this.codes = const {}, this.actions = const {}});

  /// Builds a binder and takes [e] at once.
  factory FieldErrors.fromException(ApiException e,
      {Map<String, String> aliases = const {}, Map<String, String> codes = const {}, Map<String, String> actions = const {}, String? text}) =>
      FieldErrors(aliases: aliases, codes: codes, actions: actions)..take(e, text: text);

  final Map<String, String> aliases;
  final Map<String, String> codes;
  final Map<String, String> actions;
  final Map<String, GlobalKey> _keys = {};
  final Map<String, String> _errors = {};

  /// The form field id of a server field name.
  String fieldOf(String server) {
    final n = server.startsWith('body.') ? server.substring(5) : server;
    final parts = n.split('.');
    for (var i = parts.length; i > 0; i--) {
      final p = parts.sublist(0, i).join('.');
      if (aliases.containsKey(p)) return aliases[p]!;
    }
    for (var i = 1; i < parts.length; i++) {
      final s = parts.sublist(i).join('.');
      if (aliases.containsKey(s)) return aliases[s]!;
    }
    return n;
  }

  /// Takes the field errors of [e] (replacing the ones before). Returns true when at least one field is marked.
  /// [text] replaces the message of a code-only mapping (e.g. orgErrorText(e)).
  bool take(ApiException e, {String? text}) {
    _errors.clear();
    for (final (f, msg) in e.fields) {
      _errors.putIfAbsent(fieldOf(f), () => msg);
    }
    final code = e.code;
    if (_errors.isEmpty && code != null && codes.containsKey(code)) _errors[codes[code]!] = text ?? e.message;
    final act = e.fixAction;
    if (_errors.isEmpty && act != null && actions.containsKey(act)) _errors[actions[act]!] = text ?? e.message;
    notifyListeners();
    return _errors.isNotEmpty;
  }

  /// Marks one field locally (a client-side check).
  void set(String field, String? text) {
    if (text == null) {
      if (_errors.remove(field) == null) return;
    } else {
      _errors[field] = text;
    }
    notifyListeners();
  }

  /// Clears one field (as the person edits it) or all of them.
  void clear([String? field]) {
    if (field == null ? _errors.isEmpty : !_errors.containsKey(field)) return;
    field == null ? _errors.clear() : _errors.remove(field);
    notifyListeners();
  }

  String? errorFor(String field) => _errors[field];
  bool has(String field) => _errors.containsKey(field);
  bool get isEmpty => _errors.isEmpty;
  int get count => _errors.length;

  /// The bad fields: registered ones in on-screen order first, then the rest as the server listed them.
  List<String> get bad => [
        for (final f in _keys.keys) if (_errors.containsKey(f)) f,
        for (final f in _errors.keys) if (!_keys.containsKey(f)) f,
      ];

  /// A line for the top of the form when several fields are wrong; null for none or one.
  String? get summary {
    final n = _errors.length;
    if (n < 2) return null;
    return _tx(n == 2 ? 'حقلان يحتاجان إلى تصحيح — راجع المحدَّد بالأحمر' : '$n حقول تحتاج إلى تصحيح — راجع المحدَّد بالأحمر',
        '$n fields need fixing: check the ones marked in red');
  }

  /// The key a form puts on the widget around [field].
  GlobalKey keyFor(String field) => _keys.putIfAbsent(field, () => GlobalKey(debugLabel: 'field.$field'));

  /// Scrolls the first bad registered field into view and focuses it (its first focusable descendant).
  Future<void> revealFirst() async {
    for (final f in bad) {
      final key = _keys[f];
      if (key?.currentContext == null) continue;
      await revealAndFocus(key!);
      return;
    }
  }
}

/// Scrolls the widget under [key] into view and focuses its first focusable descendant (a fix's "take me there").
/// False when it is not built (off-screen in a lazy list: scroll near it first).
Future<bool> revealAndFocus(GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null) return false;
  await Scrollable.ensureVisible(ctx, alignment: 0.2, duration: AppMotion.of(ctx).base);
  if (!ctx.mounted) return true;
  FocusNode? node;
  void visit(Element el) {
    if (node != null) return;
    if (el.widget is Focus) {
      el.visitChildElements((child) => node ??= Focus.maybeOf(child, createDependency: false));
      return;
    }
    el.visitChildElements(visit);
  }

  (ctx as Element).visitChildElements(visit);
  node?.requestFocus();
  return true;
}
