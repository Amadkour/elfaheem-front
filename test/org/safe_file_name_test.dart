import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show safeFileName;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server file names are made safe before saving (no traversal, no control characters, bounded)', () {
    expect(safeFileName('..' + String.fromCharCode(92) + '..' + String.fromCharCode(92) + 'x.pdf'), isNot(contains(String.fromCharCode(92))));
    expect(safeFileName('../../etc/passwd'), isNot(contains('/')));
    expect(safeFileName('a${String.fromCharCode(0)}b.txt'), 'a_b.txt');
    expect(safeFileName('report.final.pdf'), 'report.final.pdf');
    expect(safeFileName('...'), 'download');
    expect(safeFileName('x' * 300).length, 120);
    expect(safeFileName('لائحة الطلاب.docx'), 'لائحة الطلاب.docx');
  });
}
