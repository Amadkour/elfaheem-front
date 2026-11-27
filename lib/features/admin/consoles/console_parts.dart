// lib/features/admin/consoles/console_parts.dart
//
// Small shared pieces of the super admin's consoles for the redesign's backend packages (booking, teacher demand,
// payment markets): value readers, the country dropdown over `GET /api/v1/countries` (WorldCountries), the
// weekday names (Python's numbers: Monday 0 … Sunday 6) and a labelled number field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/world_phone_field.dart' show WorldCountries;

String cStr(dynamic v, [String or = '']) => v == null ? or : (v is String ? v : v.toString());

int? cInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(cStr(v).trim()));

double? cNum(dynamic v) => v is num ? v.toDouble() : double.tryParse(cStr(v).trim().replaceAll(',', '.'));

Map<String, dynamic> cMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> cList(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// A number as typed back into a field: "12" for 12.0, "12.5" for 12.5, "" for null.
String cNumText(dynamic v) {
  final n = cNum(v);
  if (n == null) return '';
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// The weekday of Python's number (Monday 0 … Sunday 6).
String consoleWeekday(int d) => 'a2_wd_${d.clamp(0, 6)}'.tr;

/// A country dropdown over every country (featured first), optionally with "every country" as the empty choice.
class ConsoleCountryField extends StatefulWidget {
  const ConsoleCountryField({super.key, required this.value, required this.onChanged, required this.label, this.emptyLabel});

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  /// The text of the empty choice; null = a country is required.
  final String? emptyLabel;

  @override
  State<ConsoleCountryField> createState() => _ConsoleCountryFieldState();
}

class _ConsoleCountryFieldState extends State<ConsoleCountryField> {
  final _w = WorldCountries.instance;

  @override
  void initState() {
    super.initState();
    _w.ensure();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _w,
        builder: (context, _) {
          final codes = {for (final c in _w.countries) c.code: c.name};
          final v = widget.value?.toUpperCase();
          if (v != null && v.isNotEmpty && !codes.containsKey(v)) codes[v] = v;
          return AppDropdown<String>(
            decoration: InputDecoration(labelText: widget.label),
            value: v == null || v.isEmpty ? (widget.emptyLabel == null ? null : '') : v,
            items: [
              if (widget.emptyLabel != null) DropdownMenuItem(value: '', child: Text(widget.emptyLabel!)),
              for (final e in codes.entries)
                DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (x) => widget.onChanged(x == null || x.isEmpty ? null : x),
          );
        },
      );
}

/// A number field of a console form.
class ConsoleNumberField extends StatelessWidget {
  const ConsoleNumberField({super.key, required this.controller, required this.label, this.helper, this.onChanged, this.decimal = false});

  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String>? onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppField(
          controller: controller,
          label: label,
          helper: helper,
          ltr: true,
          keyboard: TextInputType.numberWithOptions(decimal: decimal),
          onChanged: onChanged,
        ),
      );
}
