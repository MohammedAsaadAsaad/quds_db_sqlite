import 'package:quds_db_sqlite/quds_db_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

class SchemaNote extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final isImportant = BoolField(columnName: 'isImportant', defaultValue: false);

  @override
  List<FieldDefinition>? getFields() => [title, isImportant];
}

class SchemaNoteProvider extends SqliteStandardTableProvider<SchemaNote> {
  SchemaNoteProvider(super.connection, super.modelFactory, super.tableName);
}

void main() {
  late SqliteDatabaseAdapter adapter;
  late SqliteDatabaseConnection connection;
  late SchemaNoteProvider provider;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    adapter = SqliteDatabaseAdapter();
    await adapter.initialize(
      SqliteDatabaseSettings(dbName: inMemoryDatabasePath, version: 1),
    );

    connection = await adapter.getConnection() as SqliteDatabaseConnection;
    provider = SchemaNoteProvider(connection, () => SchemaNote(), 'schema_notes');
    await provider.initialize();
  });

  tearDown(() async {
    await connection.execute('DROP TABLE IF EXISTS schema_bool_int_test');
    await connection.execute('DROP TABLE IF EXISTS schema_bool_text_test');
    await connection.execute('DROP TABLE IF EXISTS schema_bool_missing_test');
    await connection.execute('DROP TABLE IF EXISTS schema_ensure_field_test');
  });

  tearDownAll(() async {
    await adapter.close();
  });

  group('SchemaInspector', () {
    test('tableExists returns true for initialized provider table', () async {
      expect(await connection.schema.tableExists('schema_notes'), isTrue);
    });

    test('columnExists detects present and missing columns', () async {
      expect(await connection.schema.columnExists('schema_notes', 'title'), isTrue);
      expect(await connection.schema.columnExists('schema_notes', 'missing'), isFalse);
    });

    test('columnNativeType returns sqlite affinity', () async {
      final type = await connection.schema.columnNativeType('schema_notes', 'title');
      expect(type, isNotNull);
      expect(type!.toUpperCase(), contains('TEXT'));
    });

    test('listColumns returns metadata for all columns', () async {
      final columns = await connection.schema.listColumns('schema_notes');
      expect(columns.map((c) => c.name), contains('title'));
      expect(columns.map((c) => c.name), contains('isImportant'));
    });
  });

  group('SchemaMigrator.ensureBooleanNotNull', () {
    test('adds missing boolean column with default', () async {
      await connection.execute(
        'CREATE TABLE schema_bool_missing_test (id INTEGER PRIMARY KEY)',
      );

      final field = BoolField(
        columnName: 'is_active',
        defaultValue: true,
        notNull: true,
      );

      await connection.migration.ensureBooleanNotNull('schema_bool_missing_test', field);

      expect(await connection.schema.columnExists('schema_bool_missing_test', 'is_active'), isTrue);
    });

    test('coerces legacy integer column to boolean storage', () async {
      await connection.execute(
        'CREATE TABLE schema_bool_int_test (legacy_flag INTEGER)',
      );
      await connection.execute(
        'INSERT INTO schema_bool_int_test (legacy_flag) VALUES (1), (0), (NULL)',
      );

      final field = BoolField(
        columnName: 'legacy_flag',
        defaultValue: false,
        notNull: true,
      );

      await connection.migration.ensureBooleanNotNull('schema_bool_int_test', field);

      final rows = await connection.query('SELECT legacy_flag FROM schema_bool_int_test');
      expect(rows.every((r) => r['legacy_flag'] == 0 || r['legacy_flag'] == 1), isTrue);
    });

    test('safe mode does not throw on repeated migration', () async {
      await connection.execute(
        'CREATE TABLE schema_bool_missing_test (flag INTEGER NOT NULL DEFAULT 0)',
      );

      final field = BoolField(
        columnName: 'flag',
        defaultValue: false,
        notNull: true,
      );

      await connection.migration.ensureBooleanNotNull(
        'schema_bool_missing_test',
        field,
        safe: true,
      );
    });
  });

  group('TableProvider schema helpers', () {
    test('ensureField adds a new column through migration API', () async {
      await connection.execute(
        'CREATE TABLE schema_ensure_field_test (id INTEGER PRIMARY KEY)',
      );

      final nickname = StringField(columnName: 'nickname', defaultValue: 'anon');
      await connection.migration.ensureField('schema_ensure_field_test', nickname);

      expect(await connection.schema.columnExists('schema_ensure_field_test', 'nickname'), isTrue);
    });

    test('provider ensureBooleanNotNull runs safely on existing model field', () async {
      await provider.ensureBooleanNotNull(provider.modelInstance.isImportant, safe: true);
      expect(await connection.schema.columnExists('schema_notes', 'isImportant'), isTrue);
    });

    test('provider ensureField adds column to provider table', () async {
      final tag = StringField(columnName: 'tag', defaultValue: 'general');
      await provider.ensureField(tag, safe: true);
      expect(await connection.schema.columnExists('schema_notes', 'tag'), isTrue);
    });
  });
}
