import 'dart:io';

import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Reads and watches the synchronized Network Suite theme mode (`'dark'` or
/// `'light'`) stored in `suite_settings` inside `shared_devices.db`.
class SuiteThemeSyncService {
  SuiteThemeSyncService._();

  static String _resolveDatabasePath(String? dbPath) {
    return dbPath ??
        SharedDeviceDatabase.instance.databasePath ??
        SharedDeviceDatabase.getDefaultDatabasePath();
  }

  /// Returns `'dark'` (default) or `'light'`.
  static Future<String> getThemeMode({String? dbPath}) async {
    final targetPath = _resolveDatabasePath(dbPath);

    if (targetPath.isEmpty ||
        targetPath == ':memory:' ||
        !File(targetPath).existsSync()) {
      return 'dark';
    }

    Database? db;
    try {
      db = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      db.execute('PRAGMA busy_timeout = 1000;');
      final tableCheck = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'suite_settings' LIMIT 1;",
      );
      if (tableCheck.isEmpty) return 'dark';

      final rows = db.select(
        "SELECT value FROM suite_settings WHERE key = 'theme_mode' LIMIT 1;",
      );
      if (rows.isEmpty) return 'dark';
      final value = rows.first['value'];
      return value == 'light' ? 'light' : 'dark';
    } catch (_) {
      return 'dark';
    } finally {
      db?.close();
    }
  }

  /// Watches the directory containing `shared_devices.db` for external writes
  /// to the database file or its sidecars (`-wal`, `-journal`).
  ///
  /// Returns an empty stream if the path is in-memory, the directory does not
  /// exist, or directory watching fails on the host OS.
  static Stream<void> watchExternalChanges({String? dbPath}) {
    final targetPath = _resolveDatabasePath(dbPath);
    if (targetPath.isEmpty || targetPath == ':memory:') {
      return const Stream.empty();
    }

    final dir = Directory(p.dirname(targetPath));
    if (!dir.existsSync()) {
      return const Stream.empty();
    }

    final dbFileName = p.basename(targetPath);
    try {
      return dir
          .watch()
          .where((event) {
            if (p.basename(event.path).startsWith(dbFileName)) {
              return true;
            }
            if (event is FileSystemMoveEvent && event.destination != null) {
              return p.basename(event.destination!).startsWith(dbFileName);
            }
            return false;
          })
          .map<void>((_) {})
          .handleError((Object _) {});
    } catch (_) {
      return const Stream.empty();
    }
  }
}
