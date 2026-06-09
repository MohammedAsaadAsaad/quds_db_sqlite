# Quds DB SQLite

A high-performance, strictly-typed, and fully automated SQLite implementation for the `quds_db_interface`.

Quds DB SQLite provides a sophisticated "No-SQL" Dart approach to database management. It eliminates the need for raw SQL strings, manual schema migrations, and explicit transaction context passing, allowing developers to focus on application logic with absolute type safety.

## Key Features

* **Strict Type Safety**: All database operations (including queries, filtering, and ordering) use strongly-typed closures.
* **Automated Migrations**: Automatically detects new fields in your `DbModel` and executes native schema modifications (`ALTER TABLE`) to integrate them.
* **Auto-Indexing**: Flag fields as `isIndexed`, and the provider will automatically generate and manage `CREATE INDEX` queries.
* **Zone-Based Transactions**: Execute complex, multi-provider operations within an implicitly injected transaction zone. No `Transaction` objects need to be passed down your architecture.
* **Silent Bulk Operations**: Perform massive data imports instantly with `insertCollection`, natively wrapped in an atomic transaction that notifies UI listeners exactly once upon completion to prevent rendering bottlenecks.
* **Native Pagination**: Query large data sets seamlessly with `loadAllEntriesByPaging`.
* **Complex Queries**: Fully supports multi-table relationship capabilities (`INNER JOIN`, `LEFT JOIN`) and aggregations (`SUM`, `MAX`, `MIN`, `AVG`, `COUNT`).

---

## Setup & Initialization

```dart
import 'package:quds_db_sqlite/quds_db_sqlite.dart';

// 1. Setup the Settings and Adapter
final adapter = SqliteDatabaseAdapter();
await adapter.initialize(
  SqliteDatabaseSettings(dbName: 'my_database.db', version: 1),
);

final connection = await adapter.getConnection();

// 2. Initialize your Provider (Automatically Migrates & Indexes)
final tasksProvider = TaskProvider(connection, () => TaskModel(), 'Tasks');
await tasksProvider.initialize();
```

---

## Defining Models

Your models should extend `StandardDbModel` and define their fields statically to allow the provider to map rows correctly and maintain strict typing.

```dart
class TaskModel extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final isCompleted = BoolField(columnName: 'isCompleted', defaultValue: false);
  final priority = IntField(columnName: 'priority', defaultValue: 0, isIndexed: true); // Auto-Indexed
  final tags = JsonField(columnName: 'tags'); // Native JSON encoding/decoding

  @override
  List<FieldDefinition>? getFields() => [title, isCompleted, priority, tags];
}
```

---

## Pure-Dart Queries (No SQL)

With strict closure typing, queries are robust, readable, and immune to SQL injection vulnerabilities.

```dart
// Fetch all pending high-priority tasks
final urgentTasks = await tasksProvider.select(
  where: (t) => ConditionGroup(conditions: [
    t.isCompleted.equals(false),
    t.priority.greaterThan(5),
  ]),
  orderBy: (t) => [t.priority.descOrder],
  limit: 10,
);

// Native Pagination
final page = await tasksProvider.loadAllEntriesByPaging(
  pageQuery: DataPageQuery(page: 1, resultsPerPage: 20),
  orderBy: (t) => [t.id.ascOrder],
);
print('Total Pages: ${page.pages}');
```

---

## Zone-Based Transactions

Quds DB SQLite utilizes `runZoned` to implicitly inject the SQLite transaction context. This eliminates the necessity of passing transaction objects throughout your provider architecture.

### Automated Bulk Transactions

For bulk operations, `insertCollection` handles the transaction natively and suppresses redundant UI rebuilds:

```dart
try {
  final t1 = TaskModel()..title.value = 'Bulk Task 1';
  final t2 = TaskModel()..title.value = 'Bulk Task 2';

  // Automatically opens a transaction, inserts all entries efficiently, and commits.
  // Notifies entry listeners exactly once upon successful completion.
  await tasksProvider.insertCollection([t1, t2]);
  
} catch (e) {
  print('Bulk Insert Failed & Rolled Back');
}
```

### Custom Zone-Based Transactions

For complex, multi-provider operations, wrap the execution logic in `connection.transaction()`. Any provider invoked within this block will natively join the transaction context:

```dart
try {
  await connection.transaction(() async {
    final user = UserModel()..name.value = 'John';
    await userProvider.insertEntry(user);
    
    final log = LogModel()..action.value = 'User Created';
    await logProvider.insertEntry(log);
    
    // If either operation fails, the entire transaction is safely rolled back.
  });
} catch (e) {
  print('Transaction Failed');
}
```
