import 'package:quds_db_sqlite/quds_db_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

List<Migration> buildTaskMigrations() {
  return [
    ClosureMigration(
      version: 1,
      name: 'create_tasks',
      up: (ctx) async {
        await ctx.createTable('mig_tasks', [
          IdField(),
          StringField(columnName: 'title', notNull: true),
          BoolField(columnName: 'isDone', defaultValue: false),
        ]);
      },
      down: (ctx) async {
        await ctx.dropTable('mig_tasks');
      },
    ),
    ClosureMigration(
      version: 2,
      name: 'add_priority',
      up: (ctx) async {
        final priority = IntField(columnName: 'priority', notNull: true)
          ..value = 0;
        await ctx.addColumn('mig_tasks', priority);
        await ctx.createIndex('mig_tasks', 'priority');
        await ctx.updateRows(
          table: 'mig_tasks',
          transform: (row) {
            final title = row['title']?.toString() ?? '';
            return {
              ...row,
              'priority': title.startsWith('URGENT') ? 10 : 0,
            };
          },
        );
      },
      down: (ctx) async {
        await ctx.dropIndex('idx_mig_tasks_priority');
        await ctx.dropColumn('mig_tasks', 'priority');
      },
    ),
    ClosureMigration(
      version: 3,
      name: 'rename_title_to_name',
      up: (ctx) async {
        await ctx.renameColumn('mig_tasks', 'title', 'name');
      },
      down: (ctx) async {
        await ctx.renameColumn('mig_tasks', 'name', 'title');
      },
    ),
  ];
}

void main() {
  late SqliteDatabaseAdapter adapter;
  late SqliteDatabaseConnection connection;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    adapter = SqliteDatabaseAdapter();
    await adapter.initialize(
      SqliteDatabaseSettings(dbName: inMemoryDatabasePath, version: 1),
    );
    connection = await adapter.getConnection() as SqliteDatabaseConnection;
  });

  tearDown(() async {
    await adapter.close();
  });

  group('SchemaMigrationRunner (SQLite)', () {
    test('migrate applies versions in order and journals them', () async {
      final migrations = buildTaskMigrations();
      final result = await connection.migrations.migrate(migrations);

      expect(result.fromVersion, 0);
      expect(result.toVersion, 3);
      expect(result.executed.map((m) => m.version), [1, 2, 3]);
      expect(await connection.migrations.currentVersion(), 3);

      final applied = await connection.migrations.appliedMigrations();
      expect(applied.map((a) => a.name), [
        'create_tasks',
        'add_priority',
        'rename_title_to_name',
      ]);

      expect(await connection.schema.tableExists('mig_tasks'), isTrue);
      expect(await connection.schema.columnExists('mig_tasks', 'name'), isTrue);
      expect(
        await connection.schema.columnExists('mig_tasks', 'title'),
        isFalse,
      );
      expect(
        await connection.schema.columnExists('mig_tasks', 'priority'),
        isTrue,
      );
    });

    test('migrate is idempotent when already at latest', () async {
      final migrations = buildTaskMigrations();
      await connection.migrations.migrate(migrations);
      final second = await connection.migrations.migrate(migrations);

      expect(second.didChange, isFalse);
      expect(second.fromVersion, 3);
      expect(second.toVersion, 3);
      expect(second.executed, isEmpty);
    });

    test('supports partial migrate then continue', () async {
      final migrations = buildTaskMigrations();
      final first = await connection.migrations.migrate(
        migrations,
        targetVersion: 1,
      );
      expect(first.toVersion, 1);
      expect(await connection.schema.columnExists('mig_tasks', 'title'), isTrue);

      await connection.insert('mig_tasks', {
        'title': 'URGENT ship',
        'isDone': 0,
      });
      await connection.insert('mig_tasks', {
        'title': 'normal',
        'isDone': 0,
      });

      final second = await connection.migrations.migrate(
        migrations,
        targetVersion: 2,
      );
      expect(second.toVersion, 2);
      expect(second.executed.map((m) => m.version), [2]);

      final withPriority = await connection.query(
        'SELECT title, priority FROM mig_tasks ORDER BY id ASC',
      );
      expect(withPriority[0]['priority'], 10);
      expect(withPriority[1]['priority'], 0);    });

    test('updateRows transforms data in Dart during migration', () async {
      await connection.migrations.migrate(
        buildTaskMigrations(),
        targetVersion: 1,
      );
      await connection.insert('mig_tasks', {'title': 'URGENT a', 'isDone': 0});
      await connection.insert('mig_tasks', {'title': 'b', 'isDone': 0});

      await connection.migrations.migrate(
        buildTaskMigrations(),
        targetVersion: 2,
      );

      final rows = await connection.query(
        'SELECT title, priority FROM mig_tasks ORDER BY id ASC',
      );
      expect(rows[0]['priority'], 10);
      expect(rows[1]['priority'], 0);
    });

    test('renameColumn and dropColumn work through ORM API', () async {
      await connection.migrations.migrate(buildTaskMigrations());
      expect(await connection.schema.columnExists('mig_tasks', 'name'), isTrue);

      await connection.migrations.rollback(
        buildTaskMigrations(),
        targetVersion: 2,
      );
      expect(await connection.schema.columnExists('mig_tasks', 'title'), isTrue);
      expect(await connection.schema.columnExists('mig_tasks', 'name'), isFalse);

      await connection.migrations.rollback(
        buildTaskMigrations(),
        targetVersion: 1,
      );
      expect(
        await connection.schema.columnExists('mig_tasks', 'priority'),
        isFalse,
      );
      expect(await connection.migrations.currentVersion(), 1);
    });

    test('full rollback to 0 drops created schema', () async {
      await connection.migrations.migrate(buildTaskMigrations());
      final result = await connection.migrations.rollback(
        buildTaskMigrations(),
        targetVersion: 0,
      );
      expect(result.toVersion, 0);
      expect(await connection.schema.tableExists('mig_tasks'), isFalse);
      expect(await connection.migrations.currentVersion(), 0);
    });

    test('failed migration does not advance journal version', () async {
      final migrations = [
        ClosureMigration(
          version: 1,
          name: 'ok_create',
          up: (ctx) async {
            await ctx.createTable('mig_fail_demo', [
              IdField(),
              StringField(columnName: 'label'),
            ]);
          },
        ),
        ClosureMigration(
          version: 2,
          name: 'boom',
          up: (ctx) async {
            await ctx.addColumn(
              'mig_fail_demo',
              StringField(columnName: 'ok_col'),
            );
            throw StateError('simulated failure');
          },
        ),
      ];

      await expectLater(
        connection.migrations.migrate(migrations),
        throwsA(isA<MigrationException>()),
      );

      expect(await connection.migrations.currentVersion(), 1);
      expect(
        await connection.schema.columnExists('mig_fail_demo', 'ok_col'),
        isFalse,
      );
    });

    test('rejects migrate backwards; requires rollback', () async {
      await connection.migrations.migrate(buildTaskMigrations());
      await expectLater(
        connection.migrations.migrate(
          buildTaskMigrations(),
          targetVersion: 1,
        ),
        throwsA(isA<MigrationException>()),
      );
    });

    test('detects journal name mismatch', () async {
      await connection.migrations.migrate([
        ClosureMigration(
          version: 1,
          name: 'original',
          up: (ctx) async {
            await ctx.createTable('mig_name_check', [IdField()]);
          },
        ),
      ]);

      await expectLater(
        connection.migrations.migrate([
          ClosureMigration(
            version: 1,
            name: 'renamed',
            up: (_) async {},
          ),
        ]),
        throwsA(isA<MigrationException>()),
      );
    });

    test('rawSql escape hatch is available', () async {
      final result = await connection.migrations.migrate([
        ClosureMigration(
          version: 1,
          name: 'raw_sql_case',
          up: (ctx) async {
            await ctx.createTable('mig_raw', [
              IdField(),
              IntField(columnName: 'n'),
            ]);
            await ctx.rawSql('INSERT INTO mig_raw (n) VALUES (?)', [42]);
          },
        ),
      ]);
      expect(result.toVersion, 1);
      final rows = await connection.query('SELECT n FROM mig_raw');
      expect(rows.single['n'], 42);
    });

    test('rejects unsafe identifiers', () async {
      await expectLater(
        connection.migrations.migrate([
          ClosureMigration(
            version: 1,
            name: 'bad_ident',
            up: (ctx) async {
              await ctx.createTable('mig;drop', [IdField()]);
            },
          ),
        ]),
        throwsA(isA<MigrationException>()),
      );
    });
  });
}
