import 'package:quds_db_interface/quds_db_interface.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Settings specific to the SQLite database engine.
class SqliteDatabaseSettings extends DatabaseSettings {
  /// The name or path of the database file. Use `sqflite.inMemoryDatabasePath` for an in-memory DB.
  final String dbName;
  
  /// The schema version of the database.
  final int version;
  
  /// Callback when the database is created for the first time.
  final sqflite.OnDatabaseCreateFn? onCreate;
  
  /// Callback when the database needs to be upgraded.
  final sqflite.OnDatabaseVersionChangeFn? onUpgrade;

  /// Callback when the database needs to be downgraded.
  final sqflite.OnDatabaseVersionChangeFn? onDowngrade;

  /// Callback when the database is opened.
  final sqflite.OnDatabaseOpenFn? onOpen;

  SqliteDatabaseSettings({
    required this.dbName,
    this.version = 1,
    this.onCreate,
    this.onUpgrade,
    this.onDowngrade,
    this.onOpen,
  });
}
