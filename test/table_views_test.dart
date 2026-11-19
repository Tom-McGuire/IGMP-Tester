import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';
import 'package:igmp_tester/ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'package:igmp_tester/ui/features/dashboard/views/global_error_banner.dart';
import 'package:igmp_tester/ui/features/dashboard/views/top_control_bar.dart';
import 'package:igmp_tester/ui/features/gaps/views/gap_analysis_table.dart';
import 'package:igmp_tester/ui/features/igmp_monitor/views/igmp_query_log_table.dart';
import 'package:igmp_tester/ui/features/sender/views/sender_panel.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';

class _FakeIfaceService extends NetworkInterfaceService {
  @override
  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async => const [
    NetworkInterfaceInfo(
      name: 'eth0',
      ip: '192.168.1.100',
      subnetMask: '255.255.255.0',
      prefixLength: 24,
    ),
  ];
}

class _FakeSnifferService extends IgmpQuerySnifferService {
  @override
  Future<String?> findTSharkPath() async => null;
}

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

    testWidgets('renders warning banner variant with warning_amber icon and dismiss', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalErrorBanner(
              errorMessage: 'SSM (S, G) Compatibility Warning',
              isWarning: true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('SSM (S, G) Compatibility Warning'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
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

  group('Phase 2 TopControlBar & SenderPanel Widget Tests', () {
    testWidgets('TopControlBar shows Querier Version pill and updates from Unknown to IGMPv3 without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final watchdog = IgmpQuerierWatchdog();
      final vm = IgmpTesterViewModel(
        interfaceService: _FakeIfaceService(),
        snifferService: _FakeSnifferService(),
        watchdog: watchdog,
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: TopControlBar()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Querier: Idle'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);

      watchdog.recordQuery(
        IgmpQueryEvent(
          timestamp: DateTime.now(),
          querierIp: '10.0.0.1',
          destinationIp: '224.0.0.1',
          typeHex: '0x11',
          typeName: 'Membership Query',
          groupAddress: '0.0.0.0',
          version: 'IGMPv3',
          maxRespTimeSeconds: 10.0,
          interfaceName: 'eth0',
          rawSummary: 'IGMPv3 General Query',
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Querier: 10.0.0.1'), findsOneWidget);
      expect(find.text('IGMPv3'), findsOneWidget);
    });

    testWidgets('SenderPanel allows configuring QoS DSCP Tag in Add Stream dialog and shows DSCP badge', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final vm = IgmpTesterViewModel(
        interfaceService: _FakeIfaceService(),
        snifferService: _FakeSnifferService(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: SenderPanel()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('QoS / DSCP'), findsOneWidget);
      expect(find.text('BE (0)'), findsOneWidget);

      await tester.tap(find.text('Add Stream'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Add Multicast Stream'), findsOneWidget);
      await tester.tap(find.text(DscpPreset.bestEffort.dropdownLabel));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text(DscpPreset.ef.dropdownLabel).last);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Stream').last);
      await tester.pump(const Duration(milliseconds: 100));

      expect(vm.senderConfig.streams.last.dscpPreset, equals(DscpPreset.ef));
      expect(find.text('EF (46)'), findsOneWidget);
    });

    testWidgets('TopControlBar renders in Dark and Light themes and toggles Load Demo / Exit Demo cleanly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => AppTheme.isDark = true);

      final vm = IgmpTesterViewModel(
        interfaceService: _FakeIfaceService(),
        snifferService: _FakeSnifferService(),
      );
      addTearDown(vm.dispose);

      // Dark theme check
      AppTheme.isDark = true;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: TopControlBar()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('IGMP & Multicast Tester'), findsOneWidget);
      expect(find.text('Load Demo'), findsOneWidget);
      expect(find.text('Exit Demo'), findsNothing);

      await tester.tap(find.text('Load Demo'));
      await tester.pump();

      expect(vm.isDemoMode, isTrue);
      expect(find.text('Exit Demo'), findsOneWidget);
      expect(find.text('Load Demo'), findsNothing);
      expect(find.text('Querier: 192.168.10.1'), findsOneWidget);
      expect(find.text('IGMPv3'), findsOneWidget);

      await tester.tap(find.text('Exit Demo'));
      await tester.pump();

      expect(vm.isDemoMode, isFalse);
      expect(find.text('Load Demo'), findsOneWidget);
      expect(find.text('Querier: Idle'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);

      // Light theme check
      AppTheme.isDark = false;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: const Scaffold(body: TopControlBar()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('IGMP & Multicast Tester'), findsOneWidget);
      expect(find.text('Load Demo'), findsOneWidget);

      await tester.tap(find.text('Load Demo'));
      await tester.pump();
      expect(vm.isDemoMode, isTrue);
      expect(find.text('Exit Demo'), findsOneWidget);

      await tester.tap(find.text('Exit Demo'));
      await tester.pump();
      expect(vm.isDemoMode, isFalse);
      expect(find.text('Load Demo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TopControlBar Export menu includes Copy IGMP Log as JSON and copies serialized events', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>;
          clipboardText = args['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final vm = IgmpTesterViewModel(
        interfaceService: _FakeIfaceService(),
        snifferService: _FakeSnifferService(),
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: TopControlBar()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Load demo events so Export is enabled and igmpEvents is non-empty
      await tester.tap(find.text('Load Demo'));
      await tester.pump();

      await tester.ensureVisible(find.text('Export'));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.text('Export Gaps as CSV...'), findsOneWidget);
      expect(find.text('Copy Gaps CSV to Clipboard'), findsOneWidget);
      expect(find.text('Copy IGMP Log as JSON'), findsOneWidget);

      await tester.tap(find.text('Copy IGMP Log as JSON'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      final decoded = jsonDecode(clipboardText!) as List<dynamic>;
      expect(decoded.length, equals(4));
      expect((decoded.first as Map<String, dynamic>)['querierIp'], equals('192.168.10.1'));
      expect(find.text('Copied 4 IGMP log event(s) as JSON'), findsOneWidget);
    });
  });
}
