// The Phase 4 advising pages must lay out at every size and language (320×640 · 1400×900, ar · en, text scale 1.3):
// every presentational view in every state — the workspace (director · advisor · filtered · empty · loading ·
// offline · failed · server update), a case card, the filter sheet, the student 360 (each section on a phone, two
// columns on a wide screen, without a registrar record, loading / failed), the flags pane (ready · empty · loading),
// the flag form (accommodations, urgent, error), the status form (resolve with outcome · reopen), the flag history,
// the notes pane with its composer (online · offline · queued · refused · contact · editing), the timeline, the
// categories (list · empty · form for a system and a new category) and the advising page's workspace links.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/advising/adv_case_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_categories_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_draft_store.dart' show AdvQueuedNote;
import 'package:flutter_education_app/features/org/advising/adv_flags.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_notes.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_workspace_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart';
import '../org/adv_models_test.dart' show sampleAdvStatusJson;
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

AdvPage<AdvCaseItem> get _work => AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson);
List<AdvCategory> get _cats => [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];
AdvPage<AdvFlag> get _flags => AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson);
AdvPage<AdvNote> get _notes => AdvPage.fromJson(sampleAdvNotesJson(), AdvNote.fromJson);
AdvTimelinePage get _timeline => AdvTimelinePage.fromJson(sampleAdvTimelineJson());
AdvCaseProfile _profile({bool academic = true}) => AdvCaseProfile.fromJson(sampleAdvProfileJson(academic: academic));

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AdvWorkspaceView _workspace({AdvLoad load = AdvLoad.ready, bool manage = true, AdvPage<AdvCaseItem>? page, AdvWorkspaceQuery query = const AdvWorkspaceQuery(), AdvSelection? selection}) =>
    AdvWorkspaceView(
      load: load,
      manage: manage,
      query: query,
      page: load == AdvLoad.ready ? (page ?? _work) : null,
      errorText: _err,
      categoryNames: {for (final c in _cats) c.key: c.name},
      now: advCaseNow,
      onRetry: () {},
      onSearch: (_) {},
      onFilters: () {},
      onClearFilters: () {},
      onPage: (_) {},
      onOpen: (_) {},
      onRegistrationCases: () {},
      onCategories: manage ? () {} : null,
      selection: selection,
      onSelectStart: (_) {},
      onToggle: (_) {},
      onTogglePage: () {},
      onSelectDone: () {},
      onMessageSelected: () {},
    );

AdvFlagsPane _flagsPane({AdvLoad load = AdvLoad.ready, AdvPage<AdvFlag>? page, String view = 'all'}) => AdvFlagsPane(
      load: load,
      page: load == AdvLoad.ready ? (page ?? _flags) : null,
      view: view,
      errorText: _err,
      onView: (_) {},
      onAdd: () {},
      onRetry: () {},
      canChange: (_) => true,
      canEdit: (_) => true,
      onStatus: (_) {},
      onEdit: (_) {},
      onHistory: (_) {},
    );

AdvNoteComposer _composer({
  AdvNoteDraft draft = const AdvNoteDraft(),
  bool offline = false,
  bool saved = false,
  List<AdvQueuedNote> queued = const [],
  bool editing = false,
  String? error,
  String text = 'اتفقنا على لقاء أسبوعي حتى الامتحانات النهائية.',
}) =>
    AdvNoteComposer(
      body: TextEditingController(text: text),
      draft: draft,
      categories: _cats,
      canSensitive: true,
      editing: editing,
      offline: offline,
      draftSaved: saved,
      queued: queued,
      error: error,
      onVisibility: (_) {},
      onSensitive: (_) {},
      onCategory: (_) {},
      onContact: (_) {},
      onMode: (_) {},
      onPickContactDate: () {},
      onSubmit: () {},
      onDiscardQueued: (_) {},
      onReopenQueued: (_) {},
    );

AdvNotesPane _notesPane({Widget? composer, AdvLoad load = AdvLoad.ready, List<AdvNote>? notes}) => AdvNotesPane(
      load: load,
      composer: composer,
      notes: load == AdvLoad.ready ? (notes ?? _notes.items) : null,
      total: 7,
      restricted: 4,
      hasMore: true,
      errorText: _err,
      onRetry: () {},
      onMore: () {},
      canEdit: (n) => n.mine,
      canDelete: (_) => true,
      onEdit: (_) {},
      onDelete: (_) {},
    );

AdvTimelinePane _timelinePane({AdvLoad load = AdvLoad.ready, List<AdvTimelineEntry>? entries}) =>
    AdvTimelinePane(load: load, entries: load == AdvLoad.ready ? (entries ?? _timeline.items) : null, hasMore: true, errorText: _err, onRetry: () {}, onMore: () {});

AdvStudentView _student(String section, {AdvLoad load = AdvLoad.ready, bool academic = true}) => AdvStudentView(
      load: load,
      profile: load == AdvLoad.ready ? _profile(academic: academic) : null,
      errorText: _err,
      section: section,
      now: advCaseNow,
      onRetry: () {},
      onSection: (_) {},
      onChangeAdvisor: () {},
      flags: _flagsPane(),
      notes: _notesPane(composer: _composer()),
      timeline: _timelinePane(),
    );

final _refusedNote = AdvQueuedNote(
  userId: 31,
  orgId: 3,
  memberId: 601,
  draft: const AdvNoteDraft(body: 'Shared with the student: the medical report and what the doctor said about the hearing aid.', visibility: 'student', clientId: 'n1'),
  error: 'advising_bad_visibility',
  message: 'A sensitive note is never shown to the student — choose Private or Advising team',
);

const _waitingNote = AdvQueuedNote(userId: 31, orgId: 3, memberId: 601, draft: AdvNoteDraft(body: 'Written offline', clientId: 'n2'));

void main() {
  group('workspace', () {
    testWidgets('director: risk-sorted cards, facets, advisor on each card', (t) => expectNoLayoutErrors(t, () => _workspace()));
    testWidgets('advisor: own students', (t) => expectNoLayoutErrors(t, () => _workspace(manage: false)));
    testWidgets('filters and a non-default order on',
        (t) => expectNoLayoutErrors(t, () => _workspace(query: const AdvWorkspaceQuery(flag: 'urgent', level: 'Level 3', priority: 'high', sort: 'contact'))));
    testWidgets('nothing matches the filters',
        (t) => expectNoLayoutErrors(t, () => _workspace(page: const AdvPage(), query: const AdvWorkspaceQuery(flag: 'urgent', q: 'zzz'))));
    testWidgets('no students yet (advisor)', (t) => expectNoLayoutErrors(t, () => _workspace(manage: false, page: const AdvPage())));
    for (final load in [AdvLoad.loading, AdvLoad.offline, AdvLoad.failed, AdvLoad.missing]) {
      testWidgets('state ${load.name}', (t) => expectNoLayoutErrors(t, () => _workspace(load: load)));
    }
    // Phase 9: selecting students for a group message (some of the page · all of it · at the limit · none yet)
    testWidgets('selecting: two chosen', (t) => expectNoLayoutErrors(t, () => _workspace(selection: const AdvSelection().toggle(_work.items[0]).toggle(_work.items[2]))));
    testWidgets('selecting: the whole page, at the limit',
        (t) => expectNoLayoutErrors(t, () => _workspace(selection: AdvSelection(const {}, _work.items.length).togglePage(_work.items))));
    testWidgets('selecting: nobody yet, advisor', (t) => expectNoLayoutErrors(t, () => _workspace(manage: false, selection: const AdvSelection())));
    testWidgets('a case card on its own (urgent, never contacted, four categories)', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvCaseCard(item: _work.items.first, showAdvisor: true, now: advCaseNow, onTap: () {}));
        }));
    testWidgets('the filter sheet (director)', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvWorkspaceFilterForm(
            query: const AdvWorkspaceQuery(sort: 'cgpa', flag: 'open', advisor: AdvRef(userId: 31, name: 'د. هدى سالم'), categoryId: 7),
            choices: AdvWorkspaceChoices.from(
              options: const AdvPolicyOptions(levels: ['Level 1', 'Level 2', 'Level 3'], cohorts: ['2023', '2024'], programs: [AdvNamed(id: 11, nameAr: 'هندسة البرمجيات', nameEn: 'Software Engineering')]),
              seen: _work.items,
              categories: _cats,
            ),
            manage: true,
            onChanged: (_) {},
            onPickAdvisor: () {},
            onApply: () {},
          ));
        }));
    testWidgets('the filter sheet (advisor, choices from the students)', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvWorkspaceFilterForm(
            query: const AdvWorkspaceQuery(),
            choices: AdvWorkspaceChoices.from(seen: _work.items),
            manage: false,
            onChanged: (_) {},
            onApply: () {},
          ));
        }));
    testWidgets('the risk meter at the edges', (t) => expectNoLayoutErrors(t, () {
          return _sheet(const Column(children: [
            AdvRiskMeter(score: 0),
            AdvRiskMeter(score: 100, reason: 'CGPA 1.62, under 2.00', large: true),
            AdvRiskMeter(score: 45, reason: 'No contact for 41 days and three failed courses in the last term, the highest Urgent'),
          ]));
        }));
  });

  group('student 360', () {
    for (final s in advCaseSections) {
      testWidgets('section $s', (t) => expectNoLayoutErrors(t, () => _student(s)));
    }
    testWidgets('no registrar record', (t) => expectNoLayoutErrors(t, () => _student('academic', academic: false)));
    testWidgets('overview without a registrar record', (t) => expectNoLayoutErrors(t, () => _student('overview', academic: false)));
    for (final load in [AdvLoad.loading, AdvLoad.failed, AdvLoad.offline]) {
      testWidgets('state ${load.name}', (t) => expectNoLayoutErrors(t, () => _student('overview', load: load)));
    }
    testWidgets('a student with no advisor and no risk', (t) => expectNoLayoutErrors(t, () {
          final j = sampleAdvProfileJson(manage: false);
          j['advisors'] = <Map<String, dynamic>>[];
          j['stats'] = {...(j['stats'] as Map<String, dynamic>), 'risk_score': 0, 'risk_reasons': <Map<String, dynamic>>[]};
          return _sheet(AdvStudentHeader(profile: AdvCaseProfile.fromJson(j)));
        }));
  });

  group('flags', () {
    testWidgets('pane: open, contacted with accommodations, resolved; hidden count', (t) => expectNoLayoutErrors(t, () => _sheet(_flagsPane())));
    testWidgets('pane: no open flags', (t) => expectNoLayoutErrors(t, () => _sheet(_flagsPane(page: const AdvPage(), view: 'open'))));
    testWidgets('pane: loading and failed', (t) => expectNoLayoutErrors(t, () => _sheet(Column(children: [_flagsPane(load: AdvLoad.loading), _flagsPane(load: AdvLoad.failed)]))));
    testWidgets('form: accessibility with accommodations, urgent, an error', (t) => expectNoLayoutErrors(t, () {
          final acc = _cats.firstWhere((c) => c.key == 'accessibility');
          return _sheet(AdvFlagForm(
            categories: [for (final c in _cats) if (c.active) c],
            draft: const AdvFlagDraft(priority: 'urgent', accommodations: ['extra_time', 'front_seating']).copyWith(categoryId: () => acc.id, reviewDueAt: () => DateTime.utc(2026, 11, 20, 12)),
            note: TextEditingController(text: 'Needs the lectures recorded; the hearing aid is being repaired until the end of the month.'),
            error: 'Those accommodations do not belong to this category',
            onCategory: (_) {},
            onPriority: (_) {},
            onPickDate: () {},
            onClearDate: () {},
            onAccommodation: (_) {},
            onSubmit: () {},
          ));
        }));
    testWidgets('form: editing, no category chosen yet', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvFlagForm(categories: _cats, draft: const AdvFlagDraft(), note: TextEditingController(), editing: true, onSubmit: () {}));
        }));
    testWidgets('status: resolve with an outcome', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvFlagStatusForm(flag: _flags.items.first, outcome: TextEditingController(text: 'Met twice; the lab section moved to the morning.'), chosen: 'resolved', onChoose: (_) {}, onSubmit: () {}));
        }));
    testWidgets('status: reopen a resolved flag, with an error', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvFlagStatusForm(flag: _flags.items.last, outcome: TextEditingController(), chosen: 'open', error: _err, onChoose: (_) {}, onSubmit: () {}));
        }));
    testWidgets('history', (t) => expectNoLayoutErrors(t, () {
          return _sheet(Column(children: [
            AdvFlagHistoryList(entries: [for (final m in (sampleAdvFlagHistoryJson()['items'] as List).cast<Map<String, dynamic>>()) AdvFlagEvent.fromJson(m)]),
            const AdvFlagHistoryList(entries: null),
            const AdvFlagHistoryList(entries: []),
          ]));
        }));
  });

  group('notes', () {
    testWidgets('pane with the composer, notes, older notes and the hidden count', (t) => expectNoLayoutErrors(t, () => _sheet(_notesPane(composer: _composer(saved: true)))));
    testWidgets('composer offline with a contact logged', (t) => expectNoLayoutErrors(t, () {
          return _sheet(_composer(offline: true, draft: const AdvNoteDraft(visibility: 'private', sensitive: true, categoryId: 5, contactMode: 'video')));
        }));
    testWidgets('composer with notes waiting and one refused', (t) => expectNoLayoutErrors(t, () {
          return _sheet(_composer(queued: [_waitingNote, _refusedNote, _waitingNote], error: _err));
        }));
    testWidgets('composer editing a note (contact time set)', (t) => expectNoLayoutErrors(t, () {
          return _sheet(_composer(editing: true, draft: AdvNoteDraft(visibility: 'student', contactMode: 'email', contactAt: DateTime.utc(2026, 11, 4, 15))));
        }));
    testWidgets('pane: no notes, read only', (t) => expectNoLayoutErrors(t, () => _sheet(_notesPane(notes: const []))));
    testWidgets('pane: loading and offline', (t) => expectNoLayoutErrors(t, () => _sheet(Column(children: [_notesPane(load: AdvLoad.loading), _notesPane(load: AdvLoad.offline)]))));
  });

  group('timeline', () {
    testWidgets('entries and older activity', (t) => expectNoLayoutErrors(t, () => _sheet(_timelinePane())));
    testWidgets('empty and loading', (t) => expectNoLayoutErrors(t, () => _sheet(Column(children: [_timelinePane(entries: const []), _timelinePane(load: AdvLoad.loading)]))));
  });

  group('categories', () {
    testWidgets('list: active and switched off', (t) => expectNoLayoutErrors(t, () => AdvCategoriesView(load: AdvLoad.ready, categories: _cats, onAdd: () {}, onOpen: (_) {})));
    testWidgets('list: empty', (t) => expectNoLayoutErrors(t, () => const AdvCategoriesView(load: AdvLoad.ready, categories: [])));
    testWidgets('list: loading', (t) => expectNoLayoutErrors(t, () => const AdvCategoriesView(load: AdvLoad.loading)));
    testWidgets('list: failed', (t) => expectNoLayoutErrors(t, () => AdvCategoriesView(load: AdvLoad.failed, errorText: _err, onRetry: () {})));
    testWidgets('form: a system category with its accommodations', (t) => expectNoLayoutErrors(t, () {
          final acc = _cats.firstWhere((c) => c.key == 'accessibility');
          return _sheet(AdvCategoryForm(
            category: acc,
            nameAr: TextEditingController(text: acc.nameAr),
            nameEn: TextEditingController(text: acc.nameEn),
            sensitive: true,
            active: true,
            rows: [for (final a in acc.accommodations) AdvAccommodationRow.of(a)],
            error: 'The category cannot be deleted while open flags use it',
            onSensitive: (_) {},
            onActive: (_) {},
            onAddRow: () {},
            onRemoveRow: (_) {},
            onSubmit: () {},
            onDelete: () {},
          ));
        }));
    testWidgets('form: a new category', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvCategoryForm(
            nameAr: TextEditingController(),
            nameEn: TextEditingController(),
            sensitive: false,
            active: true,
            rows: const [],
            onAddRow: () {},
            onSubmit: () {},
          ));
        }));
  });

  testWidgets('the advising page: workspace and categories links with urgent and overdue flags', (t) => expectNoLayoutErrors(t, () {
        return AdvSetupView(
          state: AdvSetupState.on,
          deptName: 'Academic Advising',
          status: AdvStatus.fromJson({
            ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
            'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'handovers_pending': 3, 'flags_urgent': 2, 'flags_overdue': 14},
            'counts': {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14, 'away': 22, 'over': 1},
          }),
          onOpen: (_) {},
          onDisable: () {},
        );
      }));
  testWidgets('the advising page of an advisor (My students first)', (t) => expectNoLayoutErrors(t, () {
        return AdvSetupView(
          state: AdvSetupState.on,
          status: AdvStatus.fromJson({
            ...sampleAdvStatusJson(admin: false, director: false, advisor: true),
            'me': {'admin': false, 'director': false, 'advisor': true, 'advisees': 31, 'flags_urgent': 1},
            'counts': null,
          }),
          onOpen: (_) {},
        );
      }));
}
