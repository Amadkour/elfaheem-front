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
  one-line hook in `lib/design/studio/studio_toolbar.dart` `build` (both designers show that toolbar; the
  certificate designer's font picker shows all of them anyway). Fallback: until a file lands the text draws in the
  default font and redraws when it arrives (RenderParagraph listens to font changes).
- Exports load only the files of the fonts they use, once (`ExportFonts.bytes` cache; test "lazy").

## B3 — Zero drift from the preview (2.3c) — done

- `lib/design/export_hub/export_layout.dart`: the column widths (`exportColumnFractions`, honouring the new
  `ExportTableStyle.widths`) and the header / footer sizes the preview, the PDF writer and the Word writer all read.
  Drift found and fixed: the preview's columns used other weights (name wide, 1:2:3:5) than the files; the PDF
  footer was .74 of the font size, the preview / Word .78; the Standard PDF printed bold in Bahij and Word in Arial
  while the preview showed Tajawal; the Standard preview was always portrait with fixed widths while the table
  writers go landscape for wide tables and measure the columns.
- `test/export/export_parity_test.dart` (ar + en; formal + clean themes; Standard with 4 and 9 columns): PDF
  (uncompressed, `exportPdfCompress = false`: the cells' clip boxes = column widths, /MediaBox, /BaseFont), Word
  (`tblGrid`, `pgSz`, `pgMar`, header / footer sizes, `rFonts`) and the rendered preview (cell widths, page aspect,
  footer size in points, font family) agree within 0.4 – 0.6 %.

## B4 — Certificate Word export (2.1.6) — done

- `lib/design/export/cert_docx.dart` (pure): one A4 page without margins; background behind the text; text boxes
  (Word 2010 shapes) at the fields' boxes with the catalog font embedded, size / colour / alignment / letter
  spacing, Arabic right to left, the renderer's shrink rule; every logo / signature field its OWN picture
  (`src`, else that language's default; one image part per distinct picture); signature name / title under the
  picture; photo cropped round; QR picture; lines.
- `lib/features/certificates/issue/cert_issue_word.dart`: fetches the batch's design, fills the
  placeholders like `CertificateIssueService._variables` (date, default title localized, organization, course,
  row values, name, serial, verify link), draws the QR codes, loads pictures and fonts; "Word file (.docx)" in each
  issued certificate's menu (`IssuedCertTile.onWord`), one file per issued language.
- Checked in Word 365 (COM → PDF → PNG): 1 page, 15 shapes, both languages; `test/export/cert_docx_test.dart`.
- Not filled client-side: teacher name, attendance, progress of course batches (the issued record does not carry
  them; the server computes them at issue time) — they print empty, like a placeholder without a value.

## B5 — Background exports with progress and Cancel (7.2) — done

- `lib/design/export/export_job.dart`: `ExportJob` (progress, step label, cancel), `exportCompute` (the pure writer
  in a killable isolate on phones / desktop, carrying the language, the translations and the timezone the writers
  read; on the web — no isolates for app code — on the page's thread after yielding a frame, with cancel checks),
  `runExportWithProgress` (dialog: bar, step, Cancel).
- Used by the export flow (`showAppExportSheet`: every file of an export, both languages), the Export Hub sheet
  (`exportWithDesigns`, `buildExportFile`) and the PagedList "export all" (`fetchAllRows`: "Fetching rows n / total",
  Cancel between pages). Fonts and images load before the writer (rootBundle / http stay on the UI isolate).
- `test/export/export_job_test.dart`: the writer runs on another isolate with the app's language / translations /
  timezone; Cancel kills a 30 s writer in < 5 s; errors reach the caller; the dialog (step, Cancel → null) and its
  layout at 320 / 1400 px ar / en. Widget tests run writers inline (`exportUseIsolates = false`: isolate messages
  never reach the fake-async zone).
- Web: the PDF writer itself (package:pdf `save()`) is one synchronous call; the dialog paints before it starts
  and Cancel is honoured between files / pages, not inside one `save()`.

## B6 — Watermark in data exports (6.4) — done

- `lib/design/export/export_watermark.dart`: one model (text or image, position centre / top / bottom / corners
  with start-end by reading side, size, rotation, opacity, colour, image width); additive JSON keys. Used by
  `ExportDesign.watermark` and the new `XlsxSheetOptions.watermark`.
- PDF: in each page's background, at its position in the content box; an image is embedded once per document.
- Word: text = the WordArt watermark at the position; image = a picture behind the text anchored in the header
  (`alphaModFix` opacity, `xfrm rot`), `word/_rels/header1.xml.rels`.
- Excel: a header picture (`&C&G` + `legacyDrawingHF` VML; `xlsx_watermark.dart`) of a transparent PNG of the
  content box drawn on the UI isolate (`export_watermark_png.dart`), both Excel writers.
- Preview: in the content box at the same alignment (it was centred on the whole paper).
- One editor (`export_watermark_editor.dart`) in the designer's Page panel and the Excel studio (upload or link).
- Checked: `test/export/export_watermark_test.dart`; PDF rendered, Word / Excel converted by Office 365.

## B7 — Shared panels (2.3b) — done

- Agent A did not change `lib/design/studio/studio_props.dart` (checked in `wt-front-cert` and on
  `feature/studio-cert`), so the export designer's last bespoke controls moved there as additive widgets:
  `StudioTextProp` (text / link / caption fields that keep the caret) and `StudioPlaceholderChips` ("Insert a
  variable", host-defined spelling: `{{key}}` for exports, `{key}` for certificates). The export designer (element,
  header / footer) and the watermark editor use them; every other style control there already was a studio
  primitive (font picker, stepper, weight, alignment, colour, opacity, border, segmented).
- The certificate designer still has its own panels (`cert_designer_panels.dart`, agent A's): it can adopt the two
  widgets without a model change.

## Gates

See the final report (analyze, suites, web build).
