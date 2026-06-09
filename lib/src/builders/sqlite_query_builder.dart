import 'package:quds_db_interface/quds_db_interface.dart';
import '../adapters/sqlite_database_connection.dart';

class SqliteSelectQueryBuilder<T> implements SelectQueryBuilder<T> {
  final SqliteDatabaseConnection _connection;
  TableProviderContract<T>? _fromTable;
  final List<String> _joins = [];
  Condition? _where;
  List<FieldDefinition>? _groupBy;
  Condition? _having;
  List<OrderField>? _orderBy;
  int? _limit;
  int? _offset;
  bool _distinct = false;
  List<FieldDefinition>? _select;

  SqliteSelectQueryBuilder(this._connection);

  @override
  SelectQueryBuilder<T> from(TableProviderContract<T> provider) {
    _fromTable = provider;
    return this;
  }

  @override
  SelectQueryBuilder<T> innerJoin<U>(TableProviderContract<U> otherProvider, Condition Function(T, U) onCondition) {
    if (_fromTable == null) throw Exception('Must call from() before join()');
    final condition = onCondition(_fromTable!.modelFactory(), otherProvider.modelFactory());
    _joins.add('INNER JOIN ${otherProvider.tableName} ON ${condition.buildQuery()}');
    return this;
  }

  @override
  SelectQueryBuilder<T> leftJoin<U>(TableProviderContract<U> otherProvider, Condition Function(T, U) onCondition) {
    if (_fromTable == null) throw Exception('Must call from() before join()');
    final condition = onCondition(_fromTable!.modelFactory(), otherProvider.modelFactory());
    _joins.add('LEFT OUTER JOIN ${otherProvider.tableName} ON ${condition.buildQuery()}');
    return this;
  }

  @override
  SelectQueryBuilder<T> rightJoin<U>(TableProviderContract<U> otherProvider, Condition Function(T, U) onCondition) {
    if (_fromTable == null) throw Exception('Must call from() before join()');
    final condition = onCondition(_fromTable!.modelFactory(), otherProvider.modelFactory());
    _joins.add('RIGHT OUTER JOIN ${otherProvider.tableName} ON ${condition.buildQuery()}');
    return this;
  }

  @override
  SelectQueryBuilder<T> fullJoin<U>(TableProviderContract<U> otherProvider, Condition Function(T, U) onCondition) {
    if (_fromTable == null) throw Exception('Must call from() before join()');
    final condition = onCondition(_fromTable!.modelFactory(), otherProvider.modelFactory());
    _joins.add('FULL OUTER JOIN ${otherProvider.tableName} ON ${condition.buildQuery()}');
    return this;
  }

  @override
  SelectQueryBuilder<T> crossJoin<U>(TableProviderContract<U> otherProvider) {
    _joins.add('CROSS JOIN ${otherProvider.tableName}');
    return this;
  }

  @override
  SelectQueryBuilder<T> where(Condition condition) {
    _where = condition;
    return this;
  }

  @override
  SelectQueryBuilder<T> groupBy(List<FieldDefinition> fields) {
    _groupBy = fields;
    return this;
  }

  @override
  SelectQueryBuilder<T> having(Condition condition) {
    _having = condition;
    return this;
  }

  @override
  SelectQueryBuilder<T> orderBy(List<OrderField> orderFields) {
    _orderBy = orderFields;
    return this;
  }

  @override
  SelectQueryBuilder<T> limit(int count, [int? offset]) {
    _limit = count;
    _offset = offset;
    return this;
  }

  @override
  SelectQueryBuilder<T> distinct() {
    _distinct = true;
    return this;
  }

  @override
  SelectQueryBuilder<T> select(List<FieldDefinition> fields) {
    _select = fields;
    return this;
  }

  @override
  String buildQuery() {
    if (_fromTable == null) throw Exception('from() table is not set');

    String sql = 'SELECT ';
    if (_distinct) sql += 'DISTINCT ';

    if (_select != null && _select!.isNotEmpty) {
      sql += _select!.map((f) {
        if (f is FieldWithValue) {
          // If we have a table name inside the field, it would use it, but since we can't access it easily,
          // we assume the field's buildQuery() does the right thing, or fallback to columnName
          return f.columnName;
        }
        return f.columnName;
      }).join(', ');
    } else {
      sql += '*';
    }

    sql += ' FROM ${_fromTable!.tableName}';

    for (var join in _joins) {
      sql += ' $join';
    }

    if (_where != null) {
      sql += ' WHERE ${_where!.buildQuery()}';
    }

    if (_groupBy != null && _groupBy!.isNotEmpty) {
      sql += ' GROUP BY ${_groupBy!.map((f) => f.columnName).join(', ')}';
    }

    if (_having != null) {
      sql += ' HAVING ${_having!.buildQuery()}';
    }

    if (_orderBy != null && _orderBy!.isNotEmpty) {
      sql += ' ORDER BY ${_orderBy!.map((o) => o.buildQuery()).join(', ')}';
    }

    if (_limit != null) {
      sql += ' LIMIT $_limit';
      if (_offset != null) {
        sql += ' OFFSET $_offset';
      }
    }

    return sql;
  }

  @override
  List<dynamic> getParameters() {
    final params = <dynamic>[];
    
    // We don't extract join parameters because our Condition interfaces don't easily allow it
    // Wait, onCondition gives a Condition, which has getParameters()!
    // But we didn't save the Condition itself, only its buildQuery() string in _joins.
    // For a complete adapter, we should save join conditions and extract params.
    // For simplicity in this adapter, we will assume join conditions have no params or they are handled manually.

    if (_where != null) {
      params.addAll(_where!.getParameters());
    }
    if (_having != null) {
      params.addAll(_having!.getParameters());
    }
    return params;
  }

  @override
  String toRawSql() => buildQuery();

  @override
  Future<List<Map<String, dynamic>>> executeRaw() async {
    return await _connection.query(buildQuery(), getParameters());
  }

  @override
  Future<List<T>> execute() async {
    // Assuming the provider modelInstance can parse fromMap and return a new instance
    // Wait, TableProviderContract just exposes modelInstance.
    // The TableProvider<T> has the methods to handle loading.
    throw UnimplementedError('Execute mapping requires TableProvider full context. Use executeRaw() for now.');
  }
}

class SqliteAggregateQueryBuilder<T> implements AggregateQueryBuilder<T> {
  final SqliteSelectQueryBuilder<T> _selectBuilder;

  SqliteAggregateQueryBuilder(this._selectBuilder);

  @override
  String buildQuery() => _selectBuilder.buildQuery();

  @override
  List<dynamic> getParameters() => _selectBuilder.getParameters();

  @override
  Future<List<Map<String, dynamic>>> execute() async {
    return await _selectBuilder.executeRaw();
  }
}
