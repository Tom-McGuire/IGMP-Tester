import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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

    if (targetPath.isEmpty || targetPath == ':memory:') {
      return 'dark';
    }

    try {
      if (!await File(targetPath).exists()) {
        return 'dark';
      }
      return await Isolate.run(() => _readThemeModeSync(targetPath));
    } catch (_) {
      return 'dark';
    }
  }

  static String _readThemeModeSync(String targetPath) {
    Database? db;
    try {
      db = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      db.execute('PRAGMA busy_timeout = 150;');
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
  /// to the database file or its sidecars (`-wal`, `-shm`, `-journal`).
  ///
  /// Rapid bursts of filesystem events are debounced by [debounce] so a single
  /// SQLite transaction triggers one refresh instead of several back-to-back
  /// queries. Returns an empty stream if the path is in-memory, the directory
  /// does not exist, or directory watching fails on the host OS.
  static Stream<void> watchExternalChanges({
    String? dbPath,
    Duration debounce = const Duration(milliseconds: 120),
  }) {
    final targetPath = _resolveDatabasePath(dbPath);
    if (targetPath.isEmpty || targetPath == ':memory:') {
      return const Stream.empty();
    }

    final dir = Directory(p.dirname(targetPath));
    if (!dir.existsSync()) {
      return const Stream.empty();
    }

    final dbFileName = p.basename(targetPath);
    StreamSubscription<FileSystemEvent>? watchSub;
    Timer? debounceTimer;
    var isCancelled = false;
    late final StreamController<void> controller;

    bool matchesTargetFile(FileSystemEvent event) {
      if (p.basename(event.path).startsWith(dbFileName)) {
        return true;
      }
      if (event is FileSystemMoveEvent && event.destination != null) {
        return p.basename(event.destination!).startsWith(dbFileName);
      }
      return false;
    }

    void emitChange() {
      if (!isCancelled && !controller.isClosed) {
        controller.add(null);
      }
    }

    controller = StreamController<void>(
      onListen: () {
        try {
          watchSub = dir.watch().listen(
            (event) {
              if (isCancelled || !matchesTargetFile(event)) {
                return;
              }
              if (debounce <= Duration.zero) {
                emitChange();
                return;
              }
              debounceTimer?.cancel();
              debounceTimer = Timer(debounce, () {
                debounceTimer = null;
                emitChange();
              });
            },
            onError: (Object _) {},
            onDone: () {
              debounceTimer?.cancel();
              debounceTimer = null;
              if (!controller.isClosed) {
                controller.close();
              }
            },
          );
        } catch (_) {
          if (!controller.isClosed) {
            controller.close();
          }
        }
      },
      onCancel: () {
        isCancelled = true;
        debounceTimer?.cancel();
        debounceTimer = null;
        return watchSub?.cancel();
      },
    );

    return controller.stream;
  }
}
