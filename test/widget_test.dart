import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/data/services/multicast/flooding_scanner_service.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_stats.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';
import 'package:igmp_tester/main.dart';
import 'package:igmp_tester/ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'package:igmp_tester/ui/features/dashboard/views/igmp_tester_home_screen.dart';
import 'package:igmp_tester/ui/features/igmp_monitor/views/igmp_query_log_table.dart';
import 'package:igmp_tester/ui/features/receiver/views/flooded_streams_sheet.dart';
import 'package:igmp_tester/ui/features/receiver/views/receiver_panel.dart';
import 'package:igmp_tester/ui/features/sender/views/sender_panel.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';
import 'package:igmp_tester/ui/widgets/guided_tour_overlay.dart';

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
    String? interfaceName,
    String? tsharkPath,
    Set<String> alreadyJoinedGroups = const {},
    bool ignoreControlGroups = true,
    bool ignoreUnicast = true,
    bool ignoreAlreadyJoinedGroups = true,
  }) async {
    markScanCompletedForTesting(ports: ports, duration: duration);
  }
}

class _StubReceiverTelemetryVm extends IgmpTesterViewModel {
  LeaveLatencyResult? stubLeaveLatency;
  ReceiverStats stubReceiverStats = const ReceiverStats();

  _StubReceiverTelemetryVm()
      : super(
          interfaceService: _TestIfaceService(),
          snifferService: _TestSnifferService(),
        );

  @override
  LeaveLatencyResult? get lastLeaveLatency => stubLeaveLatency;

  @override
  ReceiverStats get receiverStats => stubReceiverStats;
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

  testWidgets('Issue #2 desktop walkthrough: Load Demo steps 1..5, Finish & Clear, and Exit Demo clear demo data', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => AppTheme.isDark = true);

    final vm = IgmpTesterViewModel(
      interfaceService: _TestIfaceService(),
      snifferService: _TestSnifferService(),
    );
    addTearDown(vm.dispose);

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

    expect(vm.isDemoMode, isFalse);
    expect(find.text('Load Demo'), findsOneWidget);
    expect(find.byType(GuidedTourOverlay), findsOneWidget);
    expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);

    // Start walkthrough via Load Demo
    await tester.tap(find.text('Load Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(vm.isDemoMode, isTrue);
    expect(vm.senderConfig.streams.length, equals(10));
    expect(vm.receiverConfig.streams.length, equals(10));
    expect(vm.igmpEvents.length, equals(4));
    expect(find.text('Exit Demo'), findsOneWidget);
    expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
    expect(find.text('Zone 2: Multicast Bind Interface'), findsOneWidget);

    // Step 2
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);
    expect(find.text('Zone 3: Master Multicast Start/Stop'), findsOneWidget);

    // Step 3 (Tab 0: SenderPanel)
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 5'), findsOneWidget);
    expect(find.text('Multicast Stream Configuration Panel'), findsOneWidget);
    expect(find.byType(SenderPanel), findsOneWidget);

    // Step 4 (Tab 1: ReceiverPanel)
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);
    expect(find.text('Active Streams & Telemetry Table'), findsOneWidget);
    expect(find.byType(ReceiverPanel), findsOneWidget);

    // Step 5 (Tab 3: IgmpQueryLogTable)
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('DEMO WALKTHROUGH • STEP 5 OF 5'), findsOneWidget);
    expect(find.text('IGMP Query Sniffer & Event Log'), findsOneWidget);
    expect(find.byType(IgmpQueryLogTable), findsOneWidget);
    expect(find.text('Finish & Clear'), findsOneWidget);

    // Finish & Clear closes overlay and clears demo data
    await tester.tap(find.text('Finish & Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(vm.isDemoMode, isFalse);
    expect(vm.senderConfig.streams, isEmpty);
    expect(vm.receiverConfig.streams, isEmpty);
    expect(vm.igmpEvents, isEmpty);
    expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);
    expect(find.text('Load Demo'), findsOneWidget);

    // Re-enter demo and verify TopControlBar Exit Demo clears demo mode and data
    await tester.tap(find.text('Load Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(vm.isDemoMode, isTrue);
    expect(vm.senderConfig.streams.length, equals(10));

    final exitDemoButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Exit Demo'),
        matching: find.byType(OutlinedButton),
      ),
    );
    exitDemoButton.onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(vm.isDemoMode, isFalse);
    expect(vm.senderConfig.streams, isEmpty);
    expect(vm.receiverConfig.streams, isEmpty);
    expect(vm.igmpEvents, isEmpty);
    expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);
    expect(find.text('Load Demo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Issue #3 theme sync: IgmpTesterApp switches live from dark to light mode cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => AppTheme.isDark = true);

    AppTheme.isDark = true;
    var activeMode = 'dark';
    final themeChanges = StreamController<void>.broadcast();
    addTearDown(themeChanges.close);

    final vm = IgmpTesterViewModel(
      interfaceService: _TestIfaceService(),
      snifferService: _TestSnifferService(),
    );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      IgmpTesterApp(
        viewModel: vm,
        themeModeLoader: () async => activeMode,
        themeChangeStream: themeChanges.stream,
        enableExternalThemeWatch: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      Theme.of(tester.element(find.byType(IgmpTesterHomeScreen))).brightness,
      Brightness.dark,
    );
    expect(AppTheme.isDark, isTrue);

    activeMode = 'light';
    themeChanges.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      Theme.of(tester.element(find.byType(IgmpTesterHomeScreen))).brightness,
      Brightness.light,
    );
    expect(AppTheme.isDark, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Passive port dialog validates invalid ports inline and saves valid port cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final vm = IgmpTesterViewModel(
      interfaceService: _TestIfaceService(),
      snifferService: _TestSnifferService(),
    );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: ReceiverPanel()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(vm.receiverConfig.passiveListenPort, equals(5004));
    expect(find.text('Port: 5004'), findsOneWidget);

    // Open _PassivePortDialog
    await tester.tap(find.text('Port: 5004'));
    await tester.pumpAndSettle();

    expect(find.text('Configure No-Subscription Server Port'), findsOneWidget);
    final portField = find.widgetWithText(TextField, 'Passive Listener UDP Port');
    expect(portField, findsOneWidget);

    // Reject '0'
    await tester.enterText(portField, '0');
    await tester.tap(find.text('Save Port'));
    await tester.pump();

    expect(find.text('Enter a valid UDP port (1–65535)'), findsOneWidget);
    expect(find.text('Configure No-Subscription Server Port'), findsOneWidget);
    expect(vm.receiverConfig.passiveListenPort, equals(5004));

    // Reject '99999'
    await tester.enterText(portField, '99999');
    await tester.tap(find.text('Save Port'));
    await tester.pump();

    expect(find.text('Enter a valid UDP port (1–65535)'), findsOneWidget);
    expect(find.text('Configure No-Subscription Server Port'), findsOneWidget);
    expect(vm.receiverConfig.passiveListenPort, equals(5004));

    // Save valid port '5568'
    await tester.enterText(portField, '5568');
    await tester.tap(find.text('Save Port'));
    await tester.pumpAndSettle();

    expect(find.text('Configure No-Subscription Server Port'), findsNothing);
    expect(vm.receiverConfig.passiveListenPort, equals(5568));
    expect(find.text('Port: 5568'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ReceiverPanel renders inconclusive Fast-Leave pill and in-band Sender Tag QoS pills cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final vm = _StubReceiverTelemetryVm()
      ..stubLeaveLatency = LeaveLatencyResult(
        groupIp: '239.255.0.1',
        port: 5004,
        leaveIssuedAt: DateTime.now(),
        leaveLatencyMs: 0,
        status: FastLeaveStatus.inconclusive,
      )
      ..stubReceiverStats = const ReceiverStats(
        senderDscpPreset: DscpPreset.ef,
        dscpTransitStatus: DscpTransitStatus.unverified,
        dscpVerifiedByOsTos: false,
      );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<IgmpTesterViewModel>.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: ReceiverPanel()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No Traffic Before Leave (Inconclusive)'), findsOneWidget);
    expect(find.text('Sender Tag: EF (46) · OS TOS Unverified'), findsOneWidget);

    vm.stubReceiverStats = const ReceiverStats(
      expectedDscp: DscpPreset.ef,
      receivedDscp: 0,
      dscpTransitStatus: DscpTransitStatus.remarkedToZero,
      dscpVerifiedByOsTos: false,
    );
    // Trigger rebuild via notifyListeners-equivalent state update
    await tester.pumpWidget(
      ChangeNotifierProvider<IgmpTesterViewModel>.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(key: ValueKey('rebuilt'), body: ReceiverPanel()),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('QoS Stripped · Sent EF (46) -> Received BE (0) · Sender Tag'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
