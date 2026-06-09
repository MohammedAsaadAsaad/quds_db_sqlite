import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart' as path;
import 'package:quds_db_interface/quds_db_interface.dart';
import 'sqlite_database_connection.dart';
import 'sqlite_database_settings.dart';

/// SQLite implementation of DatabaseAdapter
class SqliteDatabaseAdapter implements DatabaseAdapter {
  sqflite.Database? _db;
  SqliteDatabaseSettings? _settings;

  SqliteDatabaseAdapter();

  @override
  Future<void> initialize(DatabaseSettings settings) async {
    if (settings is! SqliteDatabaseSettings) {
      throw ArgumentError('Settings must be of type SqliteDatabaseSettings');
    }
    _settings = settings;

    String fullPath = _settings!.dbName;
    if (_settings!.dbName != sqflite.inMemoryDatabasePath) {
      final dbPath = await sqflite.getDatabasesPath();
      fullPath = path.join(dbPath, _settings!.dbName);
    }

    _db = await sqflite.openDatabase(
      fullPath,
      version: _settings!.version,
      onCreate: _settings!.onCreate,
      onUpgrade: _settings!.onUpgrade,
      onDowngrade: _settings!.onDowngrade,
      onOpen: _settings!.onOpen,
    );
  }

  @override
  Future<DatabaseConnection> getConnection() async {
    if (_db == null) {
      throw StateError('Adapter not initialized. Call initialize(settings) first.');
    }
    return SqliteDatabaseConnection(_db!);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? parameters]) async {
    if (_db == null) throw StateError('Adapter not initialized');
    return await _db!.rawQuery(sql, parameters);
  }

  @override
  Future<int> rawExecute(String sql, [List<dynamic>? parameters]) async {
    if (_db == null) throw StateError('Adapter not initialized');
    return await _db!.rawUpdate(sql, parameters);
  }

  /// Vacuum (optimize) the database.
  ///
  /// This is a maintenance operation that can help reduce database file size.
  Future<void> vacuumDb() async {
    if (_db == null) throw StateError('Adapter not initialized');
    await _db!.execute('VACUUM');
  }
}
