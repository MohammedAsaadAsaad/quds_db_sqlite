import 'package:quds_db_interface/quds_db_interface.dart';
import '../adapters/sqlite_database_connection.dart';
import 'sqlite_schema_inspector.dart';
import 'sqlite_schema_utils.dart';

class SqliteSchemaMigrator implements SchemaMigrator {
  final SqliteDatabaseConnection connection;
  late final SqliteSchemaInspector _inspector = SqliteSchemaInspector(connection);

  SqliteSchemaMigrator(this.connection);

  @override
  SchemaInspector get inspector => _inspector;

  @override
  Future<void> ensureField(String table, FieldDefinition field) async {
    final column = field.columnName;
    if (column == null || column == 'id') return;

    if (field is BoolField) {
      if (field.notNull == true) {
        await ensureBooleanNotNull(table, field);
      } else {
        await _ensureBooleanColumn(table, field);
      }
      if (field.isIndexed) await _ensureIndex(table, field);
      return;
    }

    final exists = await _inspector.columnExists(table, column);
    if (!exists) {
      await connection.execute(
        'ALTER TABLE $table ADD COLUMN ${field.columnDefinition}',
      );
    } else if (field is FieldWithValue && field.notNull == true) {
      await _backfillAndSetNotNull(table, column, field.value);
    }

    if (field is FieldWithValue && field.isIndexed) {
      await _ensureIndex(table, field);
    }
  }

  @override
  Future<void> ensureBooleanNotNull(
    String table,
    BoolField field, {
    bool safe = false,
  }) async {
    try {
      await _ensureBooleanNotNullInternal(table, field);
    } catch (e) {
      if (safe) {
        // ignore: avoid_print
        print('Migration warning ($table.${field.columnName}): $e');
      } else {
        rethrow;
      }
    }
  }

  Future<void> _ensureBooleanNotNullInternal(String table, BoolField field) async {
    final column = field.columnName;
    if (column == null) return;

    final defaultValue = field.value ?? false;
    final literal = SqliteSchemaUtils.boolLiteral(defaultValue);
    final exists = await _inspector.columnExists(table, column);

    if (!exists) {
      await connection.execute(
        'ALTER TABLE $table ADD COLUMN ${SqliteSchemaUtils.mapBoolColumnDef(field)}',
      );
    } else {
      final nativeType = await _inspector.columnNativeType(table, column);
      if (!SqliteSchemaUtils.isBooleanType(nativeType)) {
        await connection.execute(
          '''UPDATE $table SET $column = CASE
            WHEN $column IS NULL THEN $literal
            WHEN CAST($column AS TEXT) IN ('1', 'true', 't', 'yes') THEN 1
            ELSE 0
          END''',
        );
      }
    }

    await connection.execute(
      'UPDATE $table SET $column = $literal WHERE $column IS NULL',
    );
  }

  Future<void> _ensureBooleanColumn(String table, BoolField field) async {
    final column = field.columnName;
    if (column == null) return;

    final exists = await _inspector.columnExists(table, column);
    if (!exists) {
      await connection.execute(
        'ALTER TABLE $table ADD COLUMN ${SqliteSchemaUtils.mapBoolColumnDef(field)}',
      );
    }
  }

  Future<void> _backfillAndSetNotNull(
    String table,
    String column,
    dynamic defaultValue,
  ) async {
    if (defaultValue != null) {
      await connection.execute(
        'UPDATE $table SET $column = ? WHERE $column IS NULL',
        [defaultValue],
      );
    }
  }

  Future<void> _ensureIndex(String table, FieldWithValue field) async {
    final column = field.columnName;
    if (column == null) return;
    await connection.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_$column ON $table ($column)',
    );
  }
}
