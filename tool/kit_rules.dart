// The UI kit's ratchet (test/ui/kit_rules_test.dart): counts, per file under lib/, the raw spacing / radius numbers
// that should be tokens (AppSpace / AppRadius / AppIconSize, lib/design/app_tokens.dart), and finds the "never"
// widgets (SnackBar, Switch / SwitchListTile, a dropdown that is not AppDropdown) outside lib/design.
//
// A raw number is a non-zero numeric literal written directly (not inside a nested call) in:
//   EdgeInsets.* / EdgeInsetsDirectional.* (all, symmetric, only, fromLTRB, fromSTEB)
//   SizedBox(width: n) / SizedBox(height: n)
//   Radius.circular(n) / BorderRadius.circular(n)
// Comments and string contents are ignored, and so are prefixed names (`pw.EdgeInsets`: a PDF, in points).
//
//   dart run tool/kit_rules.dart            print the 20 worst files
//   dart run tool/kit_rules.dart --write    regenerate test/ui/kit_rules_baseline.json (after lowering counts)
import 'dart:convert';
import 'dart:io';

const baselinePath = 'test/ui/kit_rules_baseline.json';

/// [src] with comments and string contents replaced by spaces (newlines kept, so offsets and lines stay valid).
String stripCommentsAndStrings(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final ch = src[i];
    if (ch == '/' && i + 1 < n && src[i + 1] == '/') {
      while (i < n && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (ch == '/' && i + 1 < n && src[i + 1] == '*') {
      var depth = 0;
      while (i < n) {
        if (src.startsWith('/*', i)) {
          depth++;
          out.write('  ');
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
        } else {
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      final raw = i > 0 && src[i - 1] == 'r';
      final triple = src.startsWith(ch * 3, i);
      final close = triple ? ch * 3 : ch;
      out.write(close);
      i += close.length;
      while (i < n) {
        if (!raw && src[i] == '\\' && i + 1 < n) {
          out.write('  ');
          i += 2;
          continue;
        }
        if (src.startsWith(close, i)) break;
        if (!triple && src[i] == '\n') break; // unterminated: stop at the line end
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < n && src.startsWith(close, i)) {
        out.write(close);
        i += close.length;
      }
      continue;
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}

/// The text between the `(` at [open] and its matching `)`, with everything inside nested brackets blanked.
String _topLevelArgs(String s, int open) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final ch = s[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
      if (depth == 1) continue;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
      if (depth == 0) break;
    }
    out.write(depth == 1 ? ch : ' ');
  }
  return out.toString();
}

final _number = RegExp(r'(?<![\w.$])(\d+(?:\.\d+)?)(?![\w.])');
// `(?<![\w.])`: a prefixed name (`pw.EdgeInsets` in a PDF document) is another library's, measured in points.
final _insets = RegExp(r'(?<![\w.])EdgeInsets(?:Directional)?\.(?:all|symmetric|only|fromLTRB|fromSTEB)\s*\(');
final _sizedBox = RegExp(r'(?<![\w.])SizedBox\s*\(');
final _sizeArg = RegExp(r'\b(?:width|height)\s*:\s*-?(\d+(?:\.\d+)?)(?![\w.])');
final _radius = RegExp(r'(?<![\w.])(?:Border)?Radius\.circular\s*\(');

bool _nonZero(String lit) => double.parse(lit) != 0;

/// Raw spacing / radius numbers in one (stripped) source.
int countRawNumbers(String stripped) {
  var count = 0;
  for (final m in _insets.allMatches(stripped)) {
    final args = _topLevelArgs(stripped, m.end - 1);
    count += _number.allMatches(args).where((x) => _nonZero(x.group(1)!)).length;
  }
  for (final m in _sizedBox.allMatches(stripped)) {
    final args = _topLevelArgs(stripped, m.end - 1);
    count += _sizeArg.allMatches(args).where((x) => _nonZero(x.group(1)!)).length;
  }
  for (final m in _radius.allMatches(stripped)) {
    final args = _topLevelArgs(stripped, m.end - 1);
    count += _number.allMatches(args).where((x) => _nonZero(x.group(1)!)).length;
  }
  return count;
}

/// The "never" widgets outside lib/design (rule → pattern).
final neverRules = <String, RegExp>{
  'SnackBar': RegExp(r'\bSnackBar\s*\(|\.showSnackBar\s*\('),
  'Switch': RegExp(r'\b(?:Switch(?:\.adaptive)?|SwitchListTile(?:\.adaptive)?|CupertinoSwitch)\s*\('),
  'Dropdown (not AppDropdown)': RegExp(r'\b(?:DropdownButton|DropdownButtonFormField|DropdownMenu)\s*(?:<[^>]*>)?\s*\('),
};

/// rule → ["path:line", …] for one (stripped) source.
Map<String, List<String>> neverHits(String path, String stripped) {
  final out = <String, List<String>>{};
  for (final e in neverRules.entries) {
    for (final m in e.value.allMatches(stripped)) {
      final line = '\n'.allMatches(stripped.substring(0, m.start)).length + 1;
      (out[e.key] ??= []).add('$path:$line');
    }
  }
  return out;
}

/// Every Dart file under lib/ (forward-slash paths relative to the package root).
List<String> libFiles() => [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) f.path.replaceAll(r'\', '/'),
    ]..sort();

/// path → raw number count, files with 0 left out.
Map<String, int> scanLib() {
  final out = <String, int>{};
  for (final p in libFiles()) {
    final n = countRawNumbers(stripCommentsAndStrings(File(p).readAsStringSync()));
    if (n > 0) out[p] = n;
  }
  return out;
}

void main(List<String> args) {
  final counts = scanLib();
  if (args.contains('--write')) {
    final sorted = {for (final k in counts.keys.toList()..sort()) k: counts[k]};
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final json = const JsonEncoder.withIndent('  ').convert({
      '_about': 'Raw spacing / radius numbers per file (tool/kit_rules.dart). Regenerate with '
          '`dart run tool/kit_rules.dart --write` after lowering a count; never raise one.',
      'total': total,
      'files': sorted,
    });
    File(baselinePath).writeAsStringSync('$json\n');
    stdout.writeln('${counts.length} files, $total raw numbers -> $baselinePath');
    return;
  }
  final worst = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in worst.take(args.isEmpty ? 20 : int.tryParse(args.first) ?? 20)) {
    stdout.writeln('${e.value.toString().padLeft(5)}  ${e.key}');
  }
  stdout.writeln('total ${counts.values.fold<int>(0, (a, b) => a + b)} in ${counts.length} files');
}
