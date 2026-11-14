// lib/features/admin/admin_filter_models.dart
//
// Pure-Dart model of the admin "premium filter": what can be filtered, which
// values are active and how they are turned into query parameters.
// No Flutter import on purpose, so the providers can use it too.
library;

/// A value picked from a server-side lookup (teacher, course, country …).
/// [id] is what the API receives, [label] is what the admin sees on the chip.
class LookupValue {
  const LookupValue(this.id, this.label);

  final Object id;
  final String label;

  @override
  bool operator ==(Object other) => other is LookupValue && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum FilterKind { choice, remoteChoice, tri, dateRange, numberRange, lookup }

/// One row of the filter sheet.
class FilterSpec {
  const FilterSpec._(
      this.kind,
      this.key,
      this.labelKey, {
        this.keyTo,
        this.options = const {},
        this.lookup,
        this.yesKey = 'admin_filter_yes',
        this.noKey = 'admin_filter_no',
      });

  final FilterKind kind;

  /// Query parameter (for ranges: the "from"/"min" one).
  final String key;

  /// Query parameter of the "to"/"max" end of a range.
  final String? keyTo;

  /// Translation key of the section title.
  final String labelKey;

  /// value -> translation key (choice).
  final Map<String, String> options;

  /// `/admin/lookup/<kind>` (remoteChoice, lookup).
  final String? lookup;

  final String yesKey;
  final String noKey;

  /// Single choice among fixed options (values are the API values).
  const FilterSpec.choice(String key, String labelKey, Map<String, String> options)
      : this._(FilterKind.choice, key, labelKey, options: options);

  /// Single choice among options the server provides (enums) — a few chips.
  const FilterSpec.remoteChoice(String key, String labelKey, String lookup)
      : this._(FilterKind.remoteChoice, key, labelKey, lookup: lookup);

  /// Any / Yes / No  →  bool?
  const FilterSpec.tri(String key, String labelKey,
      {String yesKey = 'admin_filter_yes', String noKey = 'admin_filter_no'})
      : this._(FilterKind.tri, key, labelKey, yesKey: yesKey, noKey: noKey);

  const FilterSpec.dateRange(String keyFrom, String keyTo, String labelKey)
      : this._(FilterKind.dateRange, keyFrom, labelKey, keyTo: keyTo);

  const FilterSpec.numberRange(String keyMin, String keyMax, String labelKey)
      : this._(FilterKind.numberRange, keyMin, labelKey, keyTo: keyMax);

  /// Searchable picker backed by `/admin/lookup/<lookup>` → [LookupValue].
  const FilterSpec.lookup(String key, String labelKey, String lookup)
      : this._(FilterKind.lookup, key, labelKey, lookup: lookup);

  /// Every query key this row owns.
  List<String> get keys => [key, if (keyTo != null) keyTo!];
}

/// Sort options of a list: value -> translation key. First one is the default.
class SortSpec {
  const SortSpec(this.options);

  final Map<String, String> options;

  String get defaultKey => options.keys.first;
}

/// API value -> query-string value.
String? encodeFilterValue(Object? v) {
  if (v == null) return null;
  if (v is LookupValue) return '${v.id}';
  if (v is bool) return v ? 'true' : 'false';
  if (v is DateTime) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${v.year.toString().padLeft(4, '0')}-${two(v.month)}-${two(v.day)}';
  }
  if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

/// Active-filter map -> query parameters (nulls dropped).
Map<String, String> encodeFilters(Map<String, Object?> values) {
  final out = <String, String>{};
  values.forEach((k, v) {
    final e = encodeFilterValue(v);
    if (e != null) out[k] = e;
  });
  return out;
}

/// What the filter bar needs from a provider. [AdminPagedProvider],
/// [AdminCategoriesProvider] and the admins provider all implement it.
abstract interface class AdminQueryHost {
  String get search;
  Map<String, Object?> get adv;
  String? get sort;
  bool get hasActiveQuery;

  /// Rows of the current result (null while the first page is loading).
  int? get resultCount;

  Future<void> setSearch(String v);
  Future<void> applyAdv(Map<String, Object?> values, {String? sortKey});
  Future<void> removeAdv(Iterable<String> keys);
  Future<void> setSort(String? v);
  Future<void> clearAll();
}
