# Agent B — shared export engine + fonts (feature/studio-export)

Tracker of agent B's part of the Studio + Requests job (`PROGRESS.md` next to this file has the audit).
States: done · partial · left.

## B1 — ONE font catalog (2.1.5, 2.3d) — done

- `lib/design/export/export_fonts.dart`: `ExportFonts.catalog` = the certificate studio's `kCertFonts` (keys = the
  server renderer's `FONT_KEYS`, labels = `cert_font_*`) + the two export-only families older designs name (`bahij`,
  `plex`). `certFontFiles` (key → file) is checked against `../back/services/certificate_design_renderer.py`
  `FONT_CATALOG` by `test/export/export_fonts_test.dart` (skipped when `../back` is absent, e.g. CI).
  Bold text = the key's `_bold` sibling file; a font without one prints bold text with the same file (never a
  synthesized bold, like the certificate renderer). Latin-only fonts set Arabic in the certificate's fallback
  (Amiri / Amiri Bold).
- PDF (`ttf_tools.ttfForPdf`): package:pdf draws Arabic through presentation-form code points; most catalog fonts
  lack many of them (Scheherazade New had 30, Reem Kufi / Aref Ruqaa 0–2, Cairo / Tajawal / El Messiri / Markazi a few
  dozen missing). The font's cmap is completed from its own GSUB (isol / init / medi / fina singles, lam-alef
  ligatures). Reem Kufi and Aref Ruqaa build letters from dotless shapes + dots (GSUB decomposition + GPOS marks),
  which no cmap can express: in PDF their Arabic is drawn by a stand-in (Cairo / Amiri), the Latin keeps the font.
  The UI says so.
- Word (`docx_fonts.dart`): every catalog font a file uses is embedded (obfuscated `word/fonts/*.odttf`,
  `fontTable.xml` embedRegular / embedBold / embedItalic with a font key, `settings.xml` embedTrueTypeFonts). Runs
  name the font's internal family (name ID 1). Checked in real Word 365 (docx → PDF via COM, fonts not installed on
  the machine): Amiri, Cairo (both weights), Cinzel (+ Amiri for Arabic), Scheherazade, Tajawal, El Messiri, Markazi,
  Cormorant, Great Vibes, Pinyon, IBM Plex, Bahij are used from the file. Aref Ruqaa, Reem Kufi, Playfair Display,
  Libre Baskerville and EB Garamond are Office 365 "cloud fonts": Word 365 prefers its own downloaded copy of the
  same family over the embedded one (it rendered Calibri until the cloud copy arrived, then the font) — other Word
  versions / LibreOffice use the embedded file.
- Excel: `XlsxSheetOptions.font` names the font (`<name val>`, bold / italic for `_bold` / `_italic` keys); the
  flow shows "Excel cannot embed fonts" under the picker.
- Export flow: a Font picker in the Design step (per language, every catalog font drawn in itself, "The layout's
  font" = default), applied by every writer (`AppExportChoice.fonts`, template options `fonts`); the designers'
  page / block font pickers list the whole catalog.
- Fixed on the way: Arabic inside an English (LTR) PDF printed unshaped and reversed (`exportPdfText`).
- Standard PDF / Word without a chosen font now print Tajawal regular + bold, the font the preview draws (the PDF
  used Bahij for bold text, Word used Arial); Excel keeps Arial as its default name.

## B2 — Lazy fonts (7.1) — done

- The 27 certificate fonts left pubspec `fonts:` (the web engine downloads every manifest font at start-up,
  6.2 MB) and became plain assets (`assets/fonts/cert/`).
- The certificate studio's families (`CertCinzel`, …) are registered by `ExportFonts.ensureCertFamilies()` from a
  one-line hook in `lib/design/studio/studio_canvas.dart` `initState` (every studio opens through the canvas; the
  certificate designer's font picker shows all of them anyway). Fallback: until a file lands the text draws in the
  default font and redraws when it arrives (RenderParagraph listens to font changes).
- Exports load only the files of the fonts they use, once (`ExportFonts.bytes` cache; test "lazy").

## Next

B3 parity tests (preview layout vs PDF / Word writers), B4 certificate Word export, B5 background exports,
B6 watermark, B7 shared panels (only if agent A left `studio_props.dart` alone).
