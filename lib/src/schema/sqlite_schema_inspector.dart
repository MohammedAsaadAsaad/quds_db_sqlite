import 'package:quds_db_interface/quds_db_interface.dart';
import '../adapters/sqlite_database_connection.dart';

class SqliteSchemaInspector implements SchemaInspector {
  final SqliteDatabaseConnection connection;

  SqliteSchemaInspector(this.connection);

  @override
  Future<bool> tableExists(String table, {String? schema}) async {
    final result = await connection.query(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [table],
    );
    return result.isNotEmpty;
  }

  @override
  Future<bool> columnExists(
    String table,
    String column, {
    String? schema,
  }) async {
    final columns = await listColumns(table);
    return columns.any((c) => c.name == column);
  }

  @override
  Future<String?> columnNativeType(
    String table,
    String column, {
    String? schema,
  }) async {
    final columns = await listColumns(table);
    for (final info in columns) {
      if (info.name == column) return info.nativeType;
    }
    return null;
  }

  @override
  Future<List<ColumnInfo>> listColumns(String table, {String? schema}) async {
    final result = await connection.query('PRAGMA table_info($table)');
    return result
        .map(
          (row) => ColumnInfo(
            name: row['name']?.toString() ?? '',
            nativeType: row['type']?.toString().toUpperCase() ?? 'TEXT',
            isNullable: (row['notnull'] as int? ?? 0) == 0,
            hasDefault: row['dflt_value'] != null,
          ),
        )
        .toList();
  }
}
