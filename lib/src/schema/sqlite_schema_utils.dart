import 'package:quds_db_interface/quds_db_interface.dart';

class SqliteSchemaUtils {
  static bool isBooleanType(String? nativeType) {
    if (nativeType == null) return false;
    final t = nativeType.toUpperCase();
    return t == 'BOOLEAN' || t == 'INTEGER' || t == 'INT';
  }

  static String boolLiteral(bool value) => value ? '1' : '0';

  static String mapBoolColumnDef(BoolField field) {
    final parts = <String>['INTEGER'];
    if (field.value != null) {
      parts.add('DEFAULT ${boolLiteral(field.value!)}');
    }
    if (field.notNull == true) parts.add('NOT NULL');
    return '${field.columnName} ${parts.join(' ')}';
  }
}
