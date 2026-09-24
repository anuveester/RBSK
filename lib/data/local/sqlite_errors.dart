import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// SQLite's extended result code for a UNIQUE constraint violation.
const int _sqliteConstraintUnique = 2067;

/// True if [error] is a UNIQUE constraint violation.
///
/// Raised directly as a [SqliteException] by an in-process database. When
/// the database runs in a background isolate, Drift wraps it in an
/// exception whose `toString()` is the original [SqliteException]'s text,
/// which always starts `SqliteException(<extended code>)`. That text is
/// matched instead of importing Drift's experimental remote API.
bool isUniqueConstraintViolation(Object error) {
  if (error is SqliteException) {
    return error.extendedResultCode == _sqliteConstraintUnique;
  }
  return error.toString().startsWith(
    'SqliteException($_sqliteConstraintUnique)',
  );
}
