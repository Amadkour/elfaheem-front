// The certificate designer's save and field limit:
//   * an edit made while a save is in flight survives the save's answer and keeps the design dirty
//   * a duplicate near the 60-field limit adds only the copies that fit (the server refuses more with a 400)
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _design({String name = 'Design', int fields = 1}) => {
      'id': 7,
      'name': name,
      'owner_id': 3,
      'orientation': 'landscape',
      'theme': {'color': '#C49A47', 'dark': false, 'style': 'classic'},
      'fields': [
        for (var i = 0; i < fields; i++)
          {'id': 't$i', 'kind': 'text', 'text': 'Line $i', 'x': 100, 'y': 10 + i * 10, 'w': 400, 'h': 0, 'size': 14, 'max_lines': 1},
      ],
      'fields_en': <Object>[],
      'can_edit': true,
      'langs': ['ar'],
      'updated_at': '2026-10-31T10:00:00',
    };

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  test('an edit made while the save is in flight is kept and the design stays dirty', () async {
    final fake = FakeApi({
      // the server answers with the design as it was sent (the old name)
      'POST /api/v1/certificate-designs/7/save': (_) => _design(name: 'Before'),
    }, latency: const Duration(milliseconds: 40));
    fake.install();
    addTearDown(fake.uninstall);
    final p = CertificateDesignerProvider()..adopt(CertDesign.fromJson(_design(name: 'Before')));
    addTearDown(p.dispose);
    p.rename('Before ');
    expect(p.dirty, isTrue);

    final saving = p.save();
    expect(p.saving, isTrue);
    p.rename('After'); // typed while the request is on its way
    expect(await saving, isTrue);
    expect(p.design!.name, 'After');
    expect(p.dirty, isTrue);
    expect(p.loaded!.name, 'Before');

    // a save with no edit in between adopts the server copy and is clean
    final fake2 = FakeApi({'POST /api/v1/certificate-designs/7/save': (_) => _design(name: 'After')}, latency: Duration.zero);
    fake.uninstall();
    fake2.install();
    addTearDown(fake2.uninstall);
    expect(await p.save(), isTrue);
    expect(p.dirty, isFalse);
    expect(p.design!.name, 'After');
  });

  test('duplicating near the field limit adds only the copies that fit', () {
    final p = CertificateDesignerProvider()..adopt(CertDesign.fromJson(_design(fields: kCertMaxFields - 1)));
    addTearDown(p.dispose);
    final st = p.studio;
    st.select('t0');
    st.select('t1', additive: true);
    st.select('t2', additive: true);
    st.duplicate();
    expect(p.fieldsOf('ar'), hasLength(kCertMaxFields));
    expect(st.selection, hasLength(1)); // only the copy that was added is selected
    expect(p.canAddField, isFalse);
    st.duplicate();
    expect(p.fieldsOf('ar'), hasLength(kCertMaxFields));
  });
}
