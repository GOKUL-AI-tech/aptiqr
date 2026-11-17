import 'package:drift/drift.dart';
import 'package:drift/web.dart';

LazyDatabase openLocalDatabase() {
  return LazyDatabase(() async {
    return WebDatabase.withStorage(
      DriftWebStorage.indexedDb('aptiqr_offline'),
      logStatements: false,
    );
  });
}
