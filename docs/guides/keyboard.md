# Keyboard support (web / desktop)

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

- **Keyboard (web / desktop):** `AppKeyboardSupport` in `MaterialApp.builder` (`lib/design/app_keyboard.dart`, D-012) handles every text field: Enter moves to the next field of the form and, on the last one, presses the form's primary button (`PrimaryButton` / `AppPrimaryButton` / `FilledButton` / `ElevatedButton`, the one nearest the field; a dialog with text buttons only presses the last one); Ctrl+Enter submits a multi-line field; a field with its own `onSubmitted` and a search / filter box are left alone; Esc leaves a field; Ctrl+K or "/" focuses the search box. Nothing to wire on a new screen; `EnterSubmits(onSubmit:)` / `EnterSubmits.none` decide by hand where the guess would be wrong (an exam's answer box). Tests: `test/ui/app_keyboard_test.dart`.
