import 'package:drift/drift.dart';
import 'package:referredline/data/local/app_database.dart' as db;
import 'package:referredline/domain/entities/master_list_query.dart';

/// Query helpers shared by the School and AWC repositories.

/// The escape character used in [likePattern].
const String likeEscape = r'\';

/// A case-insensitive substring pattern for `LIKE`, with the user's `%`, `_`
/// and `\` taken literally. Null when there is nothing to search for.
String? likePattern(String text) {
  final needle = text.trim().toLowerCase();
  if (needle.isEmpty) {
    return null;
  }
  final escaped = needle
      .replaceAll(likeEscape, '$likeEscape$likeEscape')
      .replaceAll('%', '$likeEscape%')
      .replaceAll('_', '${likeEscape}_');
  return '%$escaped%';
}

Expression<bool> activeFilterExpression(
  GeneratedColumn<bool> isActive,
  ActiveFilter filter,
) => switch (filter) {
  ActiveFilter.active => isActive.equals(true),
  ActiveFilter.inactive => isActive.equals(false),
  ActiveFilter.all => const Constant(true),
};

/// Distinct non-blank values of [column] among rows that are not deleted,
/// sorted case-insensitively — the options of a filter. Only stored values
/// are offered; none are invented.
Future<List<String>> distinctValues(
  db.AppDatabase database,
  TableInfo<Table, dynamic> table,
  GeneratedColumn<String> column,
  GeneratedColumn<bool> isDeleted, {
  GeneratedColumn<String>? whereColumn,
  String? whereValue,
}) async {
  final query = database.selectOnly(table, distinct: true)
    ..addColumns([column])
    ..where(isDeleted.equals(false) & column.isNotNull());
  if (whereColumn != null && whereValue != null) {
    query.where(whereColumn.equals(whereValue));
  }
  final values = {
    for (final row in await query.get())
      if ((row.read(column) ?? '').trim().isNotEmpty) row.read(column)!,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}

/// Groups of two or more [items] sharing the same [key], ordered by key.
List<List<T>> groupBy<T>(List<T> items, String Function(T) key) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    (groups[key(item)] ??= []).add(item);
  }
  final keys = groups.keys.where((k) => groups[k]!.length > 1).toList()..sort();
  return [for (final k in keys) groups[k]!];
}
