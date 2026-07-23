import 'dart:async';
import 'package:quds_db_interface/quds_db_interface.dart';
import '../adapters/sqlite_database_connection.dart';
import '../builders/sqlite_query_builder.dart';

class SqliteTableProvider<T extends DbModel>
    implements TableProvider<T>, TableProviderContract<T> {
  final SqliteDatabaseConnection connection;
  @override
  final T Function() modelFactory;
  final String _tableName;
  final List<void Function(EntryChangeType, T)> _listeners = [];

  late final T _cachedModelInstance = modelFactory();

  SqliteTableProvider(this.connection, this.modelFactory, this._tableName);

  Map<String, dynamic> _unsanitizeMap(
    Map<String, dynamic> map,
    List<FieldDefinition> fields,
  ) {
    final result = Map<String, dynamic>.from(map);
    for (var field in fields) {
      if (field is FieldWithValue) {
        final key = field.jsonMapName ?? field.columnName;
        if (key != null && result.containsKey(key)) {
          final val = result[key];
          if (val != null) {
            if (field.valueType == bool) {
              result[key] = (val == 1 || val == '1' || val == true);
            } else if (field.valueType == DateTime) {
              if (val is int) {
                result[key] = DateTime.fromMillisecondsSinceEpoch(val);
              } else if (val is String) {
                result[key] = DateTime.tryParse(val);
              }
            }
          }
        }
      }
    }
    return result;
  }

  @override
  String get tableName => _tableName;

  @override
  Future<void> ensureField(FieldDefinition field, {bool safe = false}) async {
    try {
      await connection.migration.ensureField(tableName, field);
    } catch (e) {
      if (safe) {
        // ignore: avoid_print
        print('Migration warning ($tableName.${field.columnName}): $e');
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<void> ensureBooleanNotNull(BoolField field, {bool safe = false}) async {
    await connection.migration.ensureBooleanNotNull(
      tableName,
      field,
      safe: safe,
    );
  }

  @override
  Future<void> initialize() async {
    final fields = _cachedModelInstance.getAllFields();
    if (fields.isEmpty) return;

    String sql = 'CREATE TABLE IF NOT EXISTS $tableName (';
    sql += fields.map((f) => f.columnDefinition).join(', ');
    sql += ')';

    await connection.execute(sql);

    for (var field in fields) {
      await connection.migration.ensureField(tableName, field);
    }
  }

  @override
  Future<bool> closeDB() async {
    await connection.close();
    return true;
  }

  @override
  Future<int?> insertEntry(T entry, {bool notifyListeners = true}) async {
    await entry.beforeSave(true);
    final map = entry.toMap();
    final id = await connection.insert(tableName, map);
    // Setting ID is standard provider's job, but we'll leave it simple if there is an id field.
    if (id != null && entry.getAllFields().any((f) => f.columnName == 'id')) {
      final idField = entry.getAllFields().firstWhere(
            (f) => f.columnName == 'id',
          );
      if (idField is FieldWithValue) {
        idField.value = id;
      }
    }
    await entry.afterSave(true);
    if (notifyListeners) {
      _notifyListeners(EntryChangeType.insertion, entry);
    }
    return id;
  }

  @override
  Future<List<int?>> insertCollection(List<T> entries) async {
    if (entries.isEmpty) return [];

    return await connection.transaction(() async {
      final ids = <int?>[];
      for (var entry in entries) {
        ids.add(await insertEntry(entry, notifyListeners: false));
      }
      
      _notifyListeners(EntryChangeType.collectionInsertion, entries.last);
      return ids;
    });
  }

  @override
  Future<bool> updateEntry(T entry) async {
    await entry.beforeSave(false);
    final map = entry.toMap();
    FieldDefinition? idField;
    for (var f in entry.getAllFields()) {
      if (f.columnName == 'id') {
        idField = f;
        break;
      }
    }
    if (idField == null ||
        idField is! FieldWithValue ||
        idField.value == null) {
      return false; // Can't update without ID
    }

    final count = await connection.update(tableName, map, 'id = ?', [
      idField.value,
    ]);

    final success = count > 0;
    if (success) {
      await entry.afterSave(false);
      _notifyListeners(EntryChangeType.modification, entry);
    }
    return success;
  }

  @override
  Future<bool> deleteEntry(T entry) async {
    await entry.beforeDelete();
    FieldDefinition? idField;
    for (var f in entry.getAllFields()) {
      if (f.columnName == 'id') {
        idField = f;
        break;
      }
    }
    if (idField == null ||
        idField is! FieldWithValue ||
        idField.value == null) {
      return false;
    }

    final count = await connection.delete(tableName, 'id = ?', [idField.value]);
    final success = count > 0;
    if (success) {
      await entry.afterDelete();
      _notifyListeners(EntryChangeType.deletion, entry);
    }
    return success;
  }

  @override
  Future<int> clear() async {
    final count = await connection.delete(tableName, '1=1');
    if (count > 0) {
      _notifyListeners(EntryChangeType.deletion, modelInstance);
    }
    return count;
  }

  @override
  Future<bool> drop() async {
    try {
      await connection.execute('DROP TABLE IF EXISTS $tableName');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> deleteWhere(Condition Function(T model)? where) async {
    if (where == null) return await clear();

    Condition cond = where(_cachedModelInstance);

    final count = await connection.delete(
      tableName,
      cond.buildQuery(),
      cond.getParameters(),
    );
    if (count > 0) {
      _notifyListeners(EntryChangeType.deletion, modelInstance);
    }
    return count;
  }

  @override
  Future<List<T>> select({
    Condition Function(T model)? where,
    List<FieldOrder> Function(T model)? orderBy,
    List<FieldDefinition> Function(T model)? desiredFields,
    int? limit,
    int? offset,
  }) async {
    var q = query();

    if (desiredFields != null) {
      q = q.select(desiredFields(_cachedModelInstance));
    }

    if (where != null) {
      q = q.where(where(_cachedModelInstance));
    }

    if (orderBy != null) {
      q = q.orderBy(orderBy(_cachedModelInstance));
    }

    if (limit != null) {
      q = q.limit(limit, offset);
    }

    final rows = await q.executeRaw();
    final result = <T>[];
    for (var row in rows) {
      final instance = modelFactory();
      final parsedRow = _unsanitizeMap(row, instance.getAllFields());
      instance.fromMap(parsedRow);
      await instance.afterLoad();
      result.add(instance);
    }
    return result;
  }

  @override
  Future<DataPageQueryResult<T>> loadAllEntriesByPaging({
    required DataPageQuery<T> pageQuery,
    Condition Function(T model)? where,
    List<FieldOrder> Function(T model)? orderBy,
    List<FieldDefinition> Function(T model)? desiredFields,
  }) async {
    int count = await countWhere(where);
    return DataPageQueryResult<T>(
      count,
      await select(
        limit: pageQuery.resultsPerPage,
        offset: (pageQuery.page - 1) * pageQuery.resultsPerPage,
        where: where,
        orderBy: orderBy,
        desiredFields: desiredFields,
      ),
      pageQuery.page,
      pageQuery.resultsPerPage,
    );
  }

  @override
  Future<int> count() async {
    return countWhere(null);
  }

  @override
  Future<int> countWhere(Condition Function(T model)? where) async {
    String sql = 'SELECT COUNT(*) FROM $tableName';
    List<dynamic>? params;

    if (where != null) {
      Condition cond = where(_cachedModelInstance);
      sql += ' WHERE ${cond.buildQuery()}';
      params = cond.getParameters();
    }

    final result = await connection.query(sql, params);
    if (result.isNotEmpty) {
      return result.first.values.first as int;
    }
    return 0;
  }

  @override
  SelectQueryBuilder<T> query() {
    return SqliteSelectQueryBuilder<T>(connection).from(this);
  }

  @override
  AggregateQueryBuilder<T> aggregateQuery() {
    return SqliteAggregateQueryBuilder<T>(
      query() as SqliteSelectQueryBuilder<T>,
    );
  }

  @override
  SelectQueryBuilder<T> complexQuery() {
    return query();
  }

  @override
  void addEntryChangeListener(void Function(EntryChangeType, T) listener) {
    _listeners.add(listener);
  }

  @override
  void removeEntryChangeListener(void Function(EntryChangeType, T) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners(EntryChangeType type, T entry) {
    Zone.root.run(() {
      for (var listener in _listeners) {
        listener(type, entry);
      }
    });
  }

  T get modelInstance => _cachedModelInstance;
}

class SqliteStandardTableProvider<T extends StandardDbModel>
    extends SqliteTableProvider<T> implements StandardTableProvider<T> {
  SqliteStandardTableProvider(
    super.connection,
    super.modelFactory,
    super.tableName,
  );

  @override
  String get idColumnName => 'id';

  @override
  Future<bool> deleteById(int id) async {
    final count = await connection.delete(tableName, '$idColumnName = ?', [id]);
    final success = count > 0;
    if (success) {
      _notifyListeners(EntryChangeType.deletion, modelInstance);
    }
    return success;
  }

  @override
  Future<bool> exists(int id) async {
    final c = await countWhere(
      (m) => ConditionQuery(
        operatorString: '=',
        before: FieldWithValue(idColumnName, defaultValue: id),
        after: id,
      ),
    );
    return c > 0;
  }

  @override
  Future<T?> getById(int id) async {
    final q = query();
    q.where(
      ConditionQuery(
        operatorString: '=',
        before: FieldWithValue(idColumnName, defaultValue: id),
        after: id,
      ),
    );
    q.limit(1);

    final rows = await q.executeRaw();
    if (rows.isNotEmpty) {
      final instance = modelFactory();
      final parsedRow = _unsanitizeMap(rows.first, instance.getAllFields());
      instance.fromMap(parsedRow);
      await instance.afterLoad();
      return instance;
    }
    return null;
  }
}
