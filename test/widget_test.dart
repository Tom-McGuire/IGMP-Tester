import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/data/services/multicast/flooding_scanner_service.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';
import 'package:igmp_tester/main.dart';
import 'package:igmp_tester/ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'package:igmp_tester/ui/features/dashboard/views/igmp_tester_home_screen.dart';
import 'package:igmp_tester/ui/features/receiver/views/flooded_streams_sheet.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';

class _TestIfaceService extends NetworkInterfaceService {
  @override
  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async => const [
    NetworkInterfaceInfo(
      name: 'lo',
      ip: '127.0.0.1',
      subnetMask: '255.0.0.0',
      prefixLength: 8,
    ),
  ];
}

class _TestSnifferService extends IgmpQuerySnifferService {
  @override
  Future<String?> findTSharkPath() async => null;
}

class _TestFloodingScannerService extends FloodingScannerService {
  @override
  Future<void> startScan({
    List<int> ports = FloodingScannerService.defaultPorts,
    Duration duration = const Duration(seconds: 10),
    InternetAddress? interfaceAddress,
    Set<String> alreadyJoinedGroups = const {},
    bool ignoreControlGroups = true,
    bool ignoreUnicast = true,
    bool ignoreAlreadyJoinedGroups = true,
  }) async {
    markScanCompletedForTesting(ports: ports, duration: duration);
  }
}

void main() {
  testWidgets('IgmpTesterApp desktop smoke test and multi-stream tab rendering', (WidgetTester tester) async {
    // Set standard desktop window dimensions
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const IgmpTesterApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Verify app title and tab labels
    expect(find.text('IGMP & Multicast Tester'), findsOneWidget);
    expect(find.text('Transmitter (Tx)'), findsOneWidget);
    expect(find.text('Receiver (Rx)'), findsOneWidget);
    expect(find.text('START TRANSMITTING ALL STREAMS (1)'), findsOneWidget);
    expect(find.text('Batch Generator'), findsOneWidget);

    // Switch to Receiver Tab
    await tester.tap(find.text('Receiver (Rx)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('JOIN ALL MULTICAST GROUPS (1) & START RECEIVING'), findsOneWidget);
    expect(find.text('Subscribed Groups'), findsOneWidget);
    expect(find.text('Packets Received'), findsOneWidget);
  });

  testWidgets('Phase 2 desktop integration: SSM dialog, Flooding scanner, Fast-Leave probe & warning banner', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final freePort = probe.port;
    probe.close();

    final watchdog = IgmpQuerierWatchdog();
    final vm = IgmpTesterViewModel(
      interfaceService: _TestIfaceService(),
      snifferService: _TestSnifferService(),
      watchdog: watchdog,
      floodingScannerService: _TestFloodingScannerService(),
    );
    addTearDown(vm.dispose);

    vm.batchGenerateReceiverStreams(
      count: 1,
      startingIp: '239.255.55.1',
      basePort: freePort,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const IgmpTesterHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Switch to Receiver tab
    await tester.tap(find.text('Receiver (Rx)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 1. Add an SSM (S, G) stream via UI dialog
    await tester.tap(find.text('Add Group'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(IgmpJoinMode.asm.label));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(IgmpJoinMode.ssm.label).last);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
      find.widgetWithText(TextField, 'Multicast Group IP'),
      '232.1.1.1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Source IP (SSM Filter)'),
      '10.0.0.10',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Group').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('SSM (S, G)'), findsOneWidget);
    expect(find.text('src: 10.0.0.10'), findsOneWidget);

    // 2. IGMPv2 Querier triggers non-blocking SSM Compatibility warning banner
    watchdog.recordQuery(
      IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        version: 'IGMPv2',
        maxRespTimeSeconds: 10.0,
        interfaceName: 'lo',
        rawSummary: 'IGMPv2 General Query',
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('IGMPv2'), findsOneWidget);
    expect(find.textContaining('SSM (S, G) Compatibility Warning'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('SSM (S, G) Compatibility Warning'), findsNothing);

    // 3. Scan Unjoined Traffic opens FloodedStreamsSheet cleanly
    expect(find.text('Scan Unjoined Traffic'), findsOneWidget);
    await tester.tap(find.text('Scan Unjoined Traffic'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloodedStreamsSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Close').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FloodedStreamsSheet), findsNothing);

    // 4. Enable Fast-Leave Probe, start receiving, measure leave -> 'Measuring Leave...' -> click again to abort
    final fastLeaveSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Fast-Leave Probe:'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );
    await tester.tap(fastLeaveSwitch);
    await tester.pump(const Duration(milliseconds: 50));
    expect(vm.measureFastLeave, isTrue);

    await tester.tap(find.text('JOIN ALL MULTICAST GROUPS (2) & START RECEIVING'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('LEAVE ALL MULTICAST GROUPS & STOP RECEIVERS'), findsOneWidget);

    await tester.tap(find.text('LEAVE ALL MULTICAST GROUPS & STOP RECEIVERS'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Measuring Leave...'), findsOneWidget);

    // Second click aborts immediately
    await tester.tap(find.text('Measuring Leave...'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Leave Measurement Aborted'), findsOneWidget);
  });
}
