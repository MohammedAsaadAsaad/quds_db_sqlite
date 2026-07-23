import 'dart:async';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:quds_db_interface/quds_db_interface.dart';
import '../migration/sqlite_migration_context.dart';
import '../schema/sqlite_schema_inspector.dart';
import '../schema/sqlite_schema_migrator.dart';

class SqliteDatabaseConnection implements DatabaseConnection {
  final sqflite.DatabaseExecutor _baseExecutor;
  final bool _isTransaction;
  bool _isOpen = true;

  @override
  late final SqliteSchemaInspector schema = SqliteSchemaInspector(this);
  @override
  late final SqliteSchemaMigrator migration = SqliteSchemaMigrator(this);
  @override
  late final MigrationRunner migrations = SchemaMigrationRunner(
    connection: this,
    contextFactory: () => SqliteMigrationContext(this),
    ensureJournalTable: SqliteMigrationContext.ensureJournalTable,
  );

  SqliteDatabaseConnection(this._baseExecutor, {bool isTransaction = false})
      : _isTransaction = isTransaction;

  sqflite.DatabaseExecutor get _executor {
    if (_isTransaction) return _baseExecutor;
    return Zone.current[#sqlite_executor] as sqflite.DatabaseExecutor? ?? _baseExecutor;
  }

  @override
  bool get isOpen => _isOpen;

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final sanitized = <String, dynamic>{};
    map.forEach((k, v) {
      sanitized[k] = _sanitizeValue(v);
    });
    return sanitized;
  }

  List<dynamic>? _sanitizeList(List<dynamic>? list) {
    if (list == null) return null;
    return list.map((v) => _sanitizeValue(v)).toList();
  }

  dynamic _sanitizeValue(dynamic v) {
    if (v is bool) return v ? 1 : 0;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    // sqflite supports int, num, String, Uint8List, null
    return v;
  }

  @override
  Future<List<Map<String, dynamic>>> query(String sql, [List<dynamic>? parameters]) async {
    return await _executor.rawQuery(sql, _sanitizeList(parameters));
  }

  @override
  Future<int?> insert(String tableName, Map<String, dynamic> values) async {
    final sValues = _sanitizeMap(values);
    if (_executor is sqflite.Database) {
      return await (_executor as sqflite.Database).insert(tableName, sValues);
    } else if (_executor is sqflite.Transaction) {
      return await (_executor as sqflite.Transaction).insert(tableName, sValues);
    }
    final columns = sValues.keys.join(', ');
    final placeholders = sValues.keys.map((_) => '?').join(', ');
    final sql = 'INSERT INTO $tableName ($columns) VALUES ($placeholders)';
    return await _executor.rawInsert(sql, sValues.values.toList());
  }

  @override
  Future<int> update(String tableName, Map<String, dynamic> values, String where, [List<dynamic>? parameters]) async {
    final sValues = _sanitizeMap(values);
    final sParams = _sanitizeList(parameters);
    if (_executor is sqflite.Database) {
      return await (_executor as sqflite.Database).update(tableName, sValues, where: where, whereArgs: sParams);
    } else if (_executor is sqflite.Transaction) {
      return await (_executor as sqflite.Transaction).update(tableName, sValues, where: where, whereArgs: sParams);
    }
    
    final setClause = sValues.keys.map((k) => '$k = ?').join(', ');
    final sql = 'UPDATE $tableName SET $setClause WHERE $where';
    return await _executor.rawUpdate(sql, [...sValues.values, ...?sParams]);
  }

  @override
  Future<int> delete(String tableName, String where, [List<dynamic>? parameters]) async {
    final sParams = _sanitizeList(parameters);
    if (_executor is sqflite.Database) {
      return await (_executor as sqflite.Database).delete(tableName, where: where, whereArgs: sParams);
    } else if (_executor is sqflite.Transaction) {
      return await (_executor as sqflite.Transaction).delete(tableName, where: where, whereArgs: sParams);
    }
    
    final sql = 'DELETE FROM $tableName WHERE $where';
    return await _executor.rawDelete(sql, sParams);
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    return await _executor.rawUpdate(sql, _sanitizeList(parameters));
  }

  @override
  Future<T> transaction<T>(Future<T> Function() operation) async {
    if (_isTransaction) {
      // Already inside a transaction, just run the operation.
      return await operation();
    }
    
    final db = _baseExecutor;
    if (db is! sqflite.Database) {
      throw UnsupportedError('Transactions must be started on a base Database connection');
    }
    
    return await db.transaction((txn) async {
      return await runZoned(
        () => operation(),
        zoneValues: {#sqlite_executor: txn},
      );
    });
  }

  @override
  Future<void> close() async {
    if (!_isTransaction && _baseExecutor is sqflite.Database) {
      await (_baseExecutor as sqflite.Database).close();
    }
    _isOpen = false;
  }
}
