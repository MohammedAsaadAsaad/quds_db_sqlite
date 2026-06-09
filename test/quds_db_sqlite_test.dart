import 'package:quds_db_sqlite/quds_db_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Note extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final isImportant = BoolField(columnName: 'isImportant', defaultValue: false);

  @override
  List<FieldDefinition>? getFields() => [title, isImportant];
}

class NotesProvider extends SqliteStandardTableProvider<Note> {
  NotesProvider(super.connection, super.modelFactory, super.tableName);
}

void main() {
  late SqliteDatabaseAdapter adapter;
  late SqliteDatabaseConnection connection;
  late NotesProvider provider;

  setUpAll(() async {
    // Initialize FFI for desktop execution
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    adapter = SqliteDatabaseAdapter();
    await adapter.initialize(SqliteDatabaseSettings(
      dbName: inMemoryDatabasePath,
      version: 1,
    ));
    
    connection = await adapter.getConnection() as SqliteDatabaseConnection;
    provider = NotesProvider(connection, () => Note(), 'Notes');
    await provider.initialize();
  });

  tearDownAll(() async {
    await adapter.close();
  });

  group('CRUD Operations', () {
    test('Insert, Exists and Select', () async {
      await provider.clear();

      final note1 = Note();
      note1.title.value = 'Buy milk';
      note1.isImportant.value = true;
      
      final id = await provider.insertEntry(note1);
      expect(id, isNotNull);
      
      final exists = await provider.exists(id!);
      expect(exists, isTrue);

      final notes = await provider.select();
      expect(notes.length, equals(1));
      expect(notes.first.title.value, equals('Buy milk'));
      expect(notes.first.isImportant.value, isTrue);
      
      final retrievedNote = await provider.getById(id);
      expect(retrievedNote, isNotNull);
      expect(retrievedNote!.title.value, equals('Buy milk'));
    });
    
    test('Update and Delete', () async {
      await provider.clear();
      final n1 = Note()..title.value = 'Old Title';
      await provider.insertEntry(n1);
      
      n1.title.value = 'New Title';
      final updated = await provider.updateEntry(n1);
      expect(updated, isTrue);
      
      final retrieved = await provider.getById(n1.id.value!);
      expect(retrieved!.title.value, equals('New Title'));
      
      final deleted = await provider.deleteEntry(n1);
      expect(deleted, isTrue);
      
      final checkExists = await provider.exists(n1.id.value!);
      expect(checkExists, isFalse);
    });

    test('Query Builder - Where Clause and DeleteWhere', () async {
      await provider.clear();

      final n1 = Note()..title.value = 'Task A'..isImportant.value = true;
      final n2 = Note()..title.value = 'Task B'..isImportant.value = false;
      await provider.insertCollection([n1, n2]);

      final importantNotes = await provider.select(
        where: (n) => n.isImportant.equals(true),
      );

      expect(importantNotes.length, equals(1));
      expect(importantNotes.first.title.value, equals('Task A'));
      
      final c1 = await provider.count();
      expect(c1, equals(2));
      
      final c2 = await provider.countWhere((n) => n.isImportant.equals(true));
      expect(c2, equals(1));
      
      final dCount = await provider.deleteWhere((n) => n.isImportant.equals(false));
      expect(dCount, equals(1));
      
      final remaining = await provider.count();
      expect(remaining, equals(1));
    });
  });

  group('Performance and Migrations', () {
    test('Performance: Bulk Insert and Read 1,000 records', () async {
      await provider.clear();
      
      final notes = List.generate(1000, (i) => Note()..title.value = 'Item $i'..isImportant.value = (i % 2 == 0));
      
      final stopwatch = Stopwatch()..start();
      
      // Batch insertion performance
      await provider.insertCollection(notes);
      final insertTime = stopwatch.elapsedMilliseconds;
      expect(insertTime, lessThan(2000), reason: 'Inserting 1,000 records took too long ($insertTime ms)');
      
      stopwatch.reset();
      
      // Read performance
      final allNotes = await provider.select();
      final readTime = stopwatch.elapsedMilliseconds;
      expect(allNotes.length, equals(1000));
      expect(readTime, lessThan(1000), reason: 'Reading 1,000 records took too long ($readTime ms)');
      
      // Clear performance
      stopwatch.reset();
      await provider.clear();
      final clearTime = stopwatch.elapsedMilliseconds;
      expect(clearTime, lessThan(500), reason: 'Clearing 1,000 records took too long ($clearTime ms)');
    });

    test('Migration and Indexing: Adding new fields automatically', () async {
      // In SQLite, adding a column to a table is tested by re-initializing 
      // the provider with a new field. We just verify initialize() doesn't throw.
      await provider.initialize();
      // Vacuuming should also work natively
      await adapter.vacuumDb();
    });

    test('Pagination: loadAllEntriesByPaging', () async {
      await provider.clear();
      
      final notes = List.generate(50, (i) => Note()..title.value = 'Item $i'..isImportant.value = (i % 2 == 0));
      await provider.insertCollection(notes);
      
      final page1 = await provider.loadAllEntriesByPaging(
        pageQuery: DataPageQuery(page: 1, resultsPerPage: 20),
        orderBy: (m) => [m.id.ascOrder],
      );
      
      expect(page1.total, equals(50));
      expect(page1.results.length, equals(20));
      expect(page1.pages, equals(3));
      expect(page1.page, equals(1));
      
      final page3 = await provider.loadAllEntriesByPaging(
        pageQuery: DataPageQuery(page: 3, resultsPerPage: 20),
      );
      
      expect(page3.results.length, equals(10)); // 50 total, so 3rd page has 10
    });
  });

  group('Advanced Capabilities', () {
    test('Zone-based Transactions: commit and rollback', () async {
      await provider.clear();
      
      // 1. Test successful transaction commit
      await connection.transaction(() async {
        final n1 = Note()..title.value = 'Txn 1';
        final n2 = Note()..title.value = 'Txn 2';
        await provider.insertEntry(n1);
        await provider.insertEntry(n2);
      });
      
      expect(await provider.count(), equals(2));
      
      // 2. Test transaction rollback on exception
      try {
        await connection.transaction(() async {
          final n3 = Note()..title.value = 'Txn 3';
          await provider.insertEntry(n3);
          
          final countInside = await provider.count();
          expect(countInside, equals(3));
          
          throw Exception('Intentional failure');
        });
      } catch (e) {
        expect(e.toString(), contains('Intentional failure'));
      }
      
      // Count should be 2 because the insert of n3 rolled back!
      expect(await provider.count(), equals(2));
    });
  });
}
