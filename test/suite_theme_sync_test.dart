import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/storage/suite_theme_sync_service.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  tearDown(() {
    AppTheme.isDark = true;
  });

  group('AppTheme dynamic tokens', () {
    test('returns dark palette for all tokens when isDark is true', () {
      AppTheme.isDark = true;
      expect(AppTheme.themeMode, 'dark');
      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceAlt, const Color(0xFF1A1A1A));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.surfaceElevated, const Color(0xFF2D2D2D));
      expect(AppTheme.border, const Color(0xFF2C2C2C));
      expect(AppTheme.borderStrong, const Color(0xFF3E3E42));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));
      expect(AppTheme.textSecondary, const Color(0xFF9E9E9E));
      expect(AppTheme.textMuted, const Color(0xFF6E6E6E));
      expect(AppTheme.accent, const Color(0xFF007ACC));
      expect(AppTheme.success, const Color(0xFF10B981));
      expect(AppTheme.error, const Color(0xFFEF4444));
      expect(AppTheme.warning, const Color(0xFFF59E0B));
      expect(AppTheme.info, const Color(0xFF3B82F6));
    });

    test('returns light palette for all tokens when isDark is false', () {
      AppTheme.isDark = false;
      expect(AppTheme.themeMode, 'light');
      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceAlt, const Color(0xFFF9FAFB));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.surfaceElevated, const Color(0xFFFFFFFF));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.borderStrong, const Color(0xFFD1D5DB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
      expect(AppTheme.accent, const Color(0xFF0284C7));
      expect(AppTheme.success, const Color(0xFF059669));
      expect(AppTheme.error, const Color(0xFFDC2626));
      expect(AppTheme.warning, const Color(0xFFD97706));
      expect(AppTheme.info, const Color(0xFF2563EB));
    });

    test('applyThemeMode updates isDark and themeMode', () {
      AppTheme.applyThemeMode('light');
      expect(AppTheme.isDark, isFalse);
      expect(AppTheme.themeMode, 'light');

      AppTheme.applyThemeMode('dark');
      expect(AppTheme.isDark, isTrue);
      expect(AppTheme.themeMode, 'dark');

      AppTheme.applyThemeMode('unexpected');
      expect(AppTheme.isDark, isTrue);
      expect(AppTheme.themeMode, 'dark');
    });

    test('darkTheme and lightTheme do not mutate AppTheme.isDark', () {
      AppTheme.isDark = false;
      final dark = AppTheme.darkTheme();
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF141414));
      expect(dark.colorScheme.surface, const Color(0xFF1E1E1E));
      expect(dark.colorScheme.surfaceContainerLow, const Color(0xFF1A1A1A));
      expect(dark.colorScheme.surfaceContainerHigh, const Color(0xFF282828));
      expect(dark.visualDensity, VisualDensity.compact);
      expect(AppTheme.isDark, isFalse);

      AppTheme.isDark = true;
      final light = AppTheme.lightTheme();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
      expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
      expect(light.colorScheme.surfaceContainerLow, const Color(0xFFF9FAFB));
      expect(light.colorScheme.surfaceContainerHigh, const Color(0xFFF9FAFB));
      expect(light.visualDensity, VisualDensity.compact);
      expect(AppTheme.isDark, isTrue);
    });

    test('currentTheme tracks isDark', () {
      AppTheme.isDark = true;
      expect(AppTheme.currentTheme.brightness, Brightness.dark);
      AppTheme.isDark = false;
      expect(AppTheme.currentTheme.brightness, Brightness.light);
    });
  });

  group('SuiteThemeSyncService.getThemeMode', () {
    test('returns dark for non-existent path and :memory:', () async {
      final dir = Directory.systemTemp.createTempSync('igmp_theme_missing_');
      try {
        final missingPath = p.join(dir.path, 'does_not_exist.db');
        expect(
          await SuiteThemeSyncService.getThemeMode(dbPath: missingPath),
          'dark',
        );
        expect(
          await SuiteThemeSyncService.getThemeMode(dbPath: ':memory:'),
          'dark',
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'returns dark when suite_settings table is missing, and reads stored modes',
      () async {
        final dir = Directory.systemTemp.createTempSync('igmp_theme_db_');
        try {
          final dbPath = p.join(dir.path, 'shared_devices.db');

          // DB without suite_settings table -> 'dark'
          final db = sqlite3.open(dbPath);
          db.execute('CREATE TABLE unrelated (id INTEGER PRIMARY KEY);');
          db.close();
          expect(
            await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
            'dark',
          );

          // Add suite_settings without theme_mode row -> 'dark'
          final dbWithTable = sqlite3.open(dbPath);
          dbWithTable.execute(
            'CREATE TABLE suite_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);',
          );
          expect(
            await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
            'dark',
          );

          // 'light' -> 'light'
          dbWithTable.execute(
            "INSERT OR REPLACE INTO suite_settings (key, value, updated_at) VALUES ('theme_mode', 'light', '2026-11-19T00:00:00Z');",
          );
          expect(
            await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
            'light',
          );

          // 'dark' -> 'dark'
          dbWithTable.execute(
            "INSERT OR REPLACE INTO suite_settings (key, value, updated_at) VALUES ('theme_mode', 'dark', '2026-11-19T00:01:00Z');",
          );
          expect(
            await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
            'dark',
          );

          // Unknown value -> 'dark'
          dbWithTable.execute(
            "INSERT OR REPLACE INTO suite_settings (key, value, updated_at) VALUES ('theme_mode', 'sepia', '2026-11-19T00:02:00Z');",
          );
          dbWithTable.close();
          expect(
            await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
            'dark',
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  });

  group('SuiteThemeSyncService.watchExternalChanges', () {
    test('returns empty stream for :memory: and missing directories', () async {
      expect(
        await SuiteThemeSyncService.watchExternalChanges(
          dbPath: ':memory:',
        ).isEmpty,
        isTrue,
      );
      expect(
        await SuiteThemeSyncService.watchExternalChanges(
          dbPath: p.join(
            Directory.systemTemp.path,
            'nonexistent_igmp_suite_dir_${DateTime.now().microsecondsSinceEpoch}',
            'shared_devices.db',
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('emits when target database or sidecar files change', () async {
      final dir = Directory.systemTemp.createTempSync('igmp_theme_watch_');
      final dbPath = p.join(dir.path, 'shared_devices.db');
      final walPath = '$dbPath-wal';
      final unrelatedPath = p.join(dir.path, 'unrelated.txt');

      final completer = Completer<void>();
      final sub = SuiteThemeSyncService.watchExternalChanges(
        dbPath: dbPath,
      ).listen((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      try {
        // Unrelated file should not trigger before target file changes.
        File(unrelatedPath).writeAsStringSync('ignore');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(completer.isCompleted, isFalse);

        // Writing a -wal sidecar file should trigger an event.
        File(walPath).writeAsStringSync('wal-update');
        await completer.future.timeout(const Duration(seconds: 3));
        expect(completer.isCompleted, isTrue);
      } finally {
        await sub.cancel();
        dir.deleteSync(recursive: true);
      }
    });
  });
}
