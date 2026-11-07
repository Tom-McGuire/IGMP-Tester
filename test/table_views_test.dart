import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:igmp_tester/ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'package:igmp_tester/ui/features/dashboard/views/global_error_banner.dart';
import 'package:igmp_tester/ui/features/gaps/views/gap_analysis_table.dart';
import 'package:igmp_tester/ui/features/igmp_monitor/views/igmp_query_log_table.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';

void main() {
  group('GlobalErrorBanner Widget Tests', () {
    testWidgets('renders error text and triggers onDismiss callback', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalErrorBanner(
              errorMessage: 'Failed to bind raw socket on eth0',
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('Failed to bind raw socket on eth0'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });

  group('GapAnalysisTable and IgmpQueryLogTable Widget Tests', () {
    testWidgets('GapAnalysisTable renders search filter, badges, and reacts to input', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = IgmpTesterViewModel();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: GapAnalysisTable(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Filter by stream, group, or sequence...'), findsOneWidget);
      expect(find.text('Total Gaps: '), findsOneWidget);
      expect(find.text('Packets Dropped: '), findsOneWidget);
      expect(find.text('Max Gap Duration: '), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);

      // Enter search text
      await tester.enterText(find.byType(TextField), '239.255.0.1');
      await tester.pump();

      expect(vm.gapFilter, equals('239.255.0.1'));
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Tap clear icon
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(vm.gapFilter, isEmpty);

      vm.dispose();
    });

    testWidgets('IgmpQueryLogTable renders querier status and sniffer controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = IgmpTesterViewModel();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: IgmpQueryLogTable(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Listening for Queries...'), findsOneWidget);
      expect(find.text('Clear Log'), findsOneWidget);

      vm.dispose();
    });
  });
}
