import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/data/services/multicast/multicast_receiver_service.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
import 'package:igmp_tester/domain/models/flooded_stream_entry.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';
import 'package:igmp_tester/domain/models/launch_adapter_config.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';
import 'package:igmp_tester/domain/models/multicast_stats.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';
import 'package:igmp_tester/ui/features/dashboard/view_models/igmp_tester_view_model.dart';

class FakeNetworkInterfaceService extends NetworkInterfaceService {
  final List<NetworkInterfaceInfo> fakeInterfaces;
  FakeNetworkInterfaceService(this.fakeInterfaces);

  @override
  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async => fakeInterfaces;
}

class FakeQuerySnifferService extends IgmpQuerySnifferService {
  @override
  Future<String?> findTSharkPath() async => '/usr/bin/tshark';
}

class _StartableFakeSnifferService extends IgmpQuerySnifferService {
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<String?> findTSharkPath() async => '/usr/bin/tshark';

  @override
  Future<bool> start({required NetworkInterfaceInfo? iface}) async {
    _running = true;
    return true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }
}

void main() {
  group('IgmpTesterViewModel Tests', () {
    late IgmpTesterViewModel vm;
    late FakeNetworkInterfaceService fakeIfaces;
    late FakeQuerySnifferService fakeSniffer;
    late IgmpQuerierWatchdog watchdog;

    setUp(() async {
      fakeIfaces = FakeNetworkInterfaceService([
        const NetworkInterfaceInfo(
          name: 'lo',
          ip: '127.0.0.1',
          subnetMask: '255.0.0.0',
          prefixLength: 8,
        ),
        const NetworkInterfaceInfo(
          name: 'eth0',
          ip: '192.168.1.100',
          subnetMask: '255.255.255.0',
          prefixLength: 24,
        ),
      ]);
      fakeSniffer = FakeQuerySnifferService();
      watchdog = IgmpQuerierWatchdog();

      vm = IgmpTesterViewModel(
        interfaceService: fakeIfaces,
        snifferService: fakeSniffer,
        watchdog: watchdog,
      );

      // Wait for async init() to complete
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() {
      vm.dispose();
    });

    test('initializes and selects preferred non-loopback network interface', () {
      expect(vm.interfaces.length, equals(2));
      expect(vm.selectedInterface?.name, equals('eth0'));
      expect(vm.selectedInterface?.ip, equals('192.168.1.100'));
      expect(vm.senderConfig.interface?.ip, equals('192.168.1.100'));
      expect(vm.receiverConfig.interface?.ip, equals('192.168.1.100'));
    });

    test('selectInterface updates selected adapter across sender and receiver configs', () {
      const newIface = NetworkInterfaceInfo(
        name: 'wlan0',
        ip: '10.0.0.45',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );

      vm.selectInterface(newIface);

      expect(vm.selectedInterface?.name, equals('wlan0'));
      expect(vm.senderConfig.interface?.name, equals('wlan0'));
      expect(vm.receiverConfig.interface?.name, equals('wlan0'));
    });

    test('addSenderStream, updateSenderStream, and removeSenderStream', () {
      const newStream = MulticastStreamConfig(
        id: 'tx_custom_1',
        name: 'Dante Audio Test',
        groupAddress: '239.69.0.1',
        port: 5004,
        packetsPerSecond: 1000,
      );

      vm.addSenderStream(newStream);
      expect(vm.senderConfig.streams.any((s) => s.id == 'tx_custom_1'), isTrue);

      final updatedStream = newStream.copyWith(packetsPerSecond: 2000);
      vm.updateSenderStream(updatedStream);
      expect(
        vm.senderConfig.streams.firstWhere((s) => s.id == 'tx_custom_1').packetsPerSecond,
        equals(2000),
      );

      vm.removeSenderStream('tx_custom_1');
      expect(vm.senderConfig.streams.any((s) => s.id == 'tx_custom_1'), isFalse);
    });

    test('batchGenerateSenderStreams creates sequential multicast groups', () {
      vm.batchGenerateSenderStreams(
        count: 5,
        startingIp: '239.255.1.1',
        basePort: 5004,
        pps: 100,
        packetSize: 512,
        incrementPort: true,
      );

      expect(vm.senderConfig.streams.length, equals(5));
      expect(vm.senderConfig.streams[0].groupAddress, equals('239.255.1.1'));
      expect(vm.senderConfig.streams[0].port, equals(5004));

      expect(vm.senderConfig.streams[1].groupAddress, equals('239.255.1.2'));
      expect(vm.senderConfig.streams[1].port, equals(5005));

      expect(vm.senderConfig.streams[4].groupAddress, equals('239.255.1.5'));
      expect(vm.senderConfig.streams[4].port, equals(5008));
    });

    test('addReceiverStream, updateReceiverStream, and removeReceiverStream', () {
      const rxGroup = MulticastReceiverStreamConfig(
        id: 'rx_group_test',
        name: 'NDI Video Feed',
        groupAddress: '239.255.10.1',
        port: 5960,
      );

      vm.addReceiverStream(rxGroup);
      expect(vm.receiverConfig.streams.any((s) => s.id == 'rx_group_test'), isTrue);

      final updatedGroup = rxGroup.copyWith(name: 'NDI Master');
      vm.updateReceiverStream(updatedGroup);
      expect(
        vm.receiverConfig.streams.firstWhere((s) => s.id == 'rx_group_test').name,
        equals('NDI Master'),
      );

      vm.removeReceiverStream('rx_group_test');
      expect(vm.receiverConfig.streams.any((s) => s.id == 'rx_group_test'), isFalse);
    });

    test('batchGenerateReceiverStreams creates multiple receiver configurations', () {
      vm.batchGenerateReceiverStreams(
        count: 10,
        startingIp: '239.1.1.1',
        basePort: 5004,
        incrementPort: false,
      );

      expect(vm.receiverConfig.streams.length, equals(10));
      expect(vm.receiverConfig.streams[0].groupAddress, equals('239.1.1.1'));
      expect(vm.receiverConfig.streams[9].groupAddress, equals('239.1.1.10'));
      expect(vm.receiverConfig.streams[9].port, equals(5004));
    });

    test('loopback toggles update config settings', () {
      expect(vm.senderConfig.enableLoopback, isTrue);
      vm.updateSenderLoopback(false);
      expect(vm.senderConfig.enableLoopback, isFalse);

      expect(vm.receiverConfig.enableLoopback, isTrue);
      vm.updateReceiverLoopback(false);
      expect(vm.receiverConfig.enableLoopback, isFalse);
    });

    test('setGapFilter filters gaps dynamically by IP, stream, or sequence range', () {
      vm.clearGaps();
      expect(vm.filteredGaps, isEmpty);

      // Test filter query updates
      vm.setGapFilter('lighting');
      expect(vm.gapFilter, equals('lighting'));

      vm.setGapFilter('239.255.0.1');
      expect(vm.gapFilter, equals('239.255.0.1'));

      vm.setGapFilter('');
      expect(vm.gapFilter, isEmpty);
    });

    test('dismissError clears the active error message', () {
      expect(vm.errorMessage, isNull);

      // Trigger dismiss on null
      vm.dismissError();
      expect(vm.errorMessage, isNull);
    });

    test('generateGapsCsvContent produces valid CSV headers and summary', () {
      final csv = vm.generateGapsCsvContent();
      expect(csv, contains('Gap_ID,Stream_Name,Group_Address,UDP_Port'));
      expect(csv, contains('# IGMP Multicast Tester Report'));
      expect(csv, contains('# Packets Lost'));
    });

    test('stopAll terminates active services safely', () async {
      await vm.stopAll();
      expect(vm.isSenderRunning, isFalse);
      expect(vm.isReceiverRunning, isFalse);
      expect(vm.isSnifferRunning, isFalse);
    });

    test('SSM mismatch warning triggers on IGMPv1/v2 querier, clears on IGMPv3, and supports dismiss', () async {
      vm.addReceiverStream(
        const MulticastReceiverStreamConfig(
          id: 'rx_ssm_warn',
          name: 'SSM Feed',
          groupAddress: '232.1.1.1',
          port: 5004,
          joinMode: IgmpJoinMode.ssm,
          sourceFilterIp: '10.0.0.10',
        ),
      );

      // Simulate IGMPv2 General Query
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
          interfaceName: 'eth0',
          rawSummary: 'IGMPv2 General Query',
        ),
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(vm.querierStatus.displayBadge, equals('IGMPv2'));
      expect(vm.ssmCompatibilityWarning, contains('IGMPv2'));
      expect(vm.diagnosticWarning, contains('SSM (S, G) Compatibility Warning'));

      // Dismiss hides banner while warning stays unchanged
      vm.dismissDiagnosticWarning();
      expect(vm.diagnosticWarning, isNull);

      // IGMPv3 query clears SSM compatibility mismatch
      watchdog.recordQuery(
        IgmpQueryEvent(
          timestamp: DateTime.now(),
          querierIp: '192.168.1.1',
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
      await Future.delayed(const Duration(milliseconds: 20));
      expect(vm.querierStatus.displayBadge, equals('IGMPv3'));
      expect(vm.ssmCompatibilityWarning, isNull);

      // Re-entering IGMPv1 displays warning again since previous dismissal cleared
      watchdog.recordQuery(
        IgmpQueryEvent(
          timestamp: DateTime.now(),
          querierIp: '192.168.1.1',
          destinationIp: '224.0.0.1',
          typeHex: '0x11',
          typeName: 'Membership Query',
          groupAddress: '0.0.0.0',
          version: 'IGMPv1',
          maxRespTimeSeconds: 0.0,
          interfaceName: 'eth0',
          rawSummary: 'IGMPv1 General Query',
        ),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(vm.diagnosticWarning, contains('IGMPv1'));
    });

    test('adoptFloodedStream adds group and avoids duplicates', () async {
      final now = DateTime.now();
      final entry = FloodedStreamEntry(
        groupIp: '239.255.88.1',
        destinationPort: 5568,
        sourceIp: '192.168.1.50',
        detectedProtocol: 'sACN',
        packetCount: 42,
        bytesReceived: 26880,
        firstSeen: now,
        lastSeen: now,
      );

      final initialCount = vm.receiverConfig.streams.length;
      await vm.adoptFloodedStream(entry, autoJoinAndStart: false);
      expect(vm.receiverConfig.streams.length, equals(initialCount + 1));
      expect(
        vm.receiverConfig.streams.any((s) => s.groupAddress == '239.255.88.1' && s.port == 5568),
        isTrue,
      );

      // Calling adoptFloodedStream again for same endpoint should not duplicate
      await vm.adoptFloodedStream(entry, autoJoinAndStart: false);
      expect(vm.receiverConfig.streams.length, equals(initialCount + 1));
    });

    test('adoptFloodedStream rejects Unknown Group without throwing or adding invalid stream', () async {
      final now = DateTime.now();
      final entry = FloodedStreamEntry(
        groupIp: 'Unknown Group',
        destinationPort: 5004,
        sourceIp: '192.168.1.50',
        detectedProtocol: 'Dante / RTP',
        protocolDetail: 'RTP v2 PT 96 · seq 10',
        packetCount: 15,
        bytesReceived: 3000,
        firstSeen: now,
        lastSeen: now,
      );

      final initialCount = vm.receiverConfig.streams.length;
      await vm.adoptFloodedStream(entry, autoJoinAndStart: true);

      expect(vm.errorMessage, isNotNull);
      expect(vm.errorMessage, contains('Unknown Group'));
      expect(vm.errorMessage, contains('not a valid IPv4 multicast group'));
      expect(vm.receiverConfig.streams.length, equals(initialCount));
      expect(
        vm.receiverConfig.streams.any((s) => s.groupAddress == 'Unknown Group'),
        isFalse,
      );
    });

    test('IgmpQuerierWatchdog resumes ticking and evaluating health after stopAll() followed by startAll() or toggleSniffer()', () async {
      final localWatchdog = IgmpQuerierWatchdog();
      final localSniffer = _StartableFakeSnifferService();
      final localVm = IgmpTesterViewModel(
        interfaceService: fakeIfaces,
        snifferService: localSniffer,
        watchdog: localWatchdog,
      );
      addTearDown(localVm.dispose);
      await Future.delayed(const Duration(milliseconds: 50));

      // Disable default streams so startAll() starts without binding real multicast sockets
      localVm.batchGenerateSenderStreams(
        count: 1,
        startingIp: '239.255.0.1',
        basePort: 5004,
        pps: 10,
        packetSize: 64,
      );
      localVm.updateSenderStream(
        localVm.senderConfig.streams.first.copyWith(enabled: false),
      );
      localVm.batchGenerateReceiverStreams(
        count: 1,
        startingIp: '239.255.0.1',
        basePort: 5004,
      );
      localVm.updateReceiverStream(
        localVm.receiverConfig.streams.first.copyWith(enabled: false),
      );

      IgmpQueryEvent staleBoundaryQuery() => IgmpQueryEvent(
            timestamp: DateTime.now().subtract(const Duration(seconds: 125)),
            querierIp: '192.168.1.1',
            destinationIp: '224.0.0.1',
            typeHex: '0x11',
            typeName: 'Membership Query',
            groupAddress: '0.0.0.0',
            version: 'IGMPv3',
            protocolVersion: IgmpProtocolVersion.igmpv3,
            maxRespTimeSeconds: 10.0,
            interfaceName: 'eth0',
            rawSummary: 'IGMPv3 General Query',
          );

      // 1. stopAll() resets watchdog without killing its periodic ticks, and startAll() ensures it is running
      await localVm.stopAll();
      expect(localVm.querierStatus.health, equals(QuerierHealth.idle));

      await localVm.startAll();
      localWatchdog.recordQuery(staleBoundaryQuery());
      await Future.delayed(const Duration(milliseconds: 20));
      expect(localVm.querierStatus.health, equals(QuerierHealth.active));

      // Within ~1.2s the 1s periodic timer ticks and transitions active -> warning (>= 126s)
      await Future.delayed(const Duration(milliseconds: 1250));
      expect(localVm.querierStatus.health, equals(QuerierHealth.warning));
      expect(localVm.querierStatus.secondsSinceLastQuery, greaterThanOrEqualTo(126));

      // 2. stopAll() followed by toggleSniffer() also ticks and evaluates health
      await localVm.stopAll();
      expect(localVm.querierStatus.health, equals(QuerierHealth.idle));

      await localVm.toggleSniffer();
      expect(localVm.isSnifferRunning, isTrue);

      localWatchdog.recordQuery(staleBoundaryQuery());
      await Future.delayed(const Duration(milliseconds: 20));
      expect(localVm.querierStatus.health, equals(QuerierHealth.active));

      await Future.delayed(const Duration(milliseconds: 1250));
      expect(localVm.querierStatus.health, equals(QuerierHealth.warning));
      expect(localVm.querierStatus.secondsSinceLastQuery, greaterThanOrEqualTo(126));
    });

    test('Fast-Leave mode supports measurement, double-click abort, and clear', () async {
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final freePort = probe.port;
      probe.close();

      vm.updateMeasureFastLeave(true);
      expect(vm.measureFastLeave, isTrue);
      vm.batchGenerateReceiverStreams(
        count: 1,
        startingIp: '239.255.77.1',
        basePort: freePort,
      );

      await vm.toggleReceiver();
      expect(vm.isReceiverRunning, isTrue);

      // First toggleReceiver initiates Fast-Leave drain window
      final leaveFuture = vm.toggleReceiver();
      expect(vm.isMeasuringLeave, isTrue);

      // Second toggleReceiver during measurement immediately aborts
      await vm.toggleReceiver();
      await leaveFuture;
      expect(vm.isMeasuringLeave, isFalse);
      expect(vm.lastLeaveLatency?.aborted, isTrue);
      expect(vm.lastLeaveLatency?.status, equals(FastLeaveStatus.aborted));

      vm.clearLeaveLatencyResults();
      expect(vm.lastLeaveLatency, isNull);
    });

    test('DSCP QoS preset generation and transit stripping alert trigger diagnosticWarning', () async {
      final receiverService = MulticastReceiverService();
      final localSniffer = FakeQuerySnifferService();
      final localWatchdog = IgmpQuerierWatchdog();
      final vmWithRx = IgmpTesterViewModel(
        interfaceService: fakeIfaces,
        snifferService: localSniffer,
        watchdog: localWatchdog,
        receiverService: receiverService,
      );
      addTearDown(vmWithRx.dispose);
      await Future.delayed(const Duration(milliseconds: 50));

      vmWithRx.batchGenerateSenderStreams(
        count: 2,
        startingIp: '239.255.10.1',
        basePort: 5004,
        pps: 50,
        packetSize: 256,
        dscpPreset: DscpPreset.ef,
      );
      expect(vmWithRx.senderConfig.streams.first.dscpPreset, equals(DscpPreset.ef));

      const qosStream = MulticastReceiverStreamConfig(
        id: 'rx_qos_alert',
        name: 'EF Voice',
        groupAddress: '239.255.10.1',
        port: 5004,
        expectedDscp: DscpPreset.ef,
      );
      vmWithRx.addReceiverStream(qosStream);
      receiverService.addStreamForTesting(qosStream);

      final packet = MulticastPacket(
        sessionId: 'qos_vm',
        sequenceNumber: 1,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: '239.255.10.1',
        destinationPort: 5004,
        dscpValue: DscpPreset.ef.dscpValue,
      );
      receiverService.processDatagramForTesting(
        Datagram(packet.encode(), InternetAddress('192.168.1.50'), 40000),
        5004,
        receivedTosByte: 0x00, // Stripped!
      );
      receiverService.recalculateStatsForTesting();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(vmWithRx.dscpPolicyWarning, contains('QoS Stripped'));
      expect(vmWithRx.dscpPolicyWarning, isNot(contains('(In-Band Sender Tag)')));
      expect(vmWithRx.diagnosticWarning, contains('QoS Policy Alert'));

      // Now simulate live OS socket path (receivedTosByte omitted) where in-band sender tag mismatches expectedDscp
      final inBandMismatchPacket = MulticastPacket(
        sessionId: 'qos_vm_inband',
        sequenceNumber: 1,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: '239.255.10.1',
        destinationPort: 5004,
        dscpValue: DscpPreset.bestEffort.dscpValue,
      );
      receiverService.processDatagramForTesting(
        Datagram(inBandMismatchPacket.encode(), InternetAddress('192.168.1.50'), 40000),
        5004,
      );
      receiverService.recalculateStatsForTesting();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(vmWithRx.dscpPolicyWarning, contains('QoS Stripped'));
      expect(vmWithRx.dscpPolicyWarning, contains('(In-Band Sender Tag)'));
    });

    test('Issue #1: LaunchAdapterConfig selects by IPv4 priority, name fallback, default fallback, and preserves manual selection', () async {
      final multiIfaces = FakeNetworkInterfaceService([
        const NetworkInterfaceInfo(
          name: 'lo',
          ip: '127.0.0.1',
          subnetMask: '255.0.0.0',
          prefixLength: 8,
        ),
        const NetworkInterfaceInfo(
          name: 'eth0',
          ip: '192.168.1.100',
          subnetMask: '255.255.255.0',
          prefixLength: 24,
        ),
        const NetworkInterfaceInfo(
          name: 'wlan0',
          ip: '10.10.20.5',
          subnetMask: '255.255.255.0',
          prefixLength: 24,
        ),
      ]);

      // 1. Exact IPv4 match takes priority over adapterName
      final vmByIp = IgmpTesterViewModel(
        interfaceService: multiIfaces,
        snifferService: FakeQuerySnifferService(),
        launchAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '10.10.20.5',
          adapterName: 'eth0',
        ),
      );
      addTearDown(vmByIp.dispose);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(vmByIp.selectedInterface?.name, equals('wlan0'));
      expect(vmByIp.selectedInterface?.ip, equals('10.10.20.5'));
      expect(vmByIp.senderConfig.interface?.ip, equals('10.10.20.5'));
      expect(vmByIp.receiverConfig.interface?.ip, equals('10.10.20.5'));

      // Manual selectInterface + subsequent refreshInterfaces does NOT re-apply CLI override
      const manualChoice = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '192.168.1.100',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );
      vmByIp.selectInterface(manualChoice);
      await vmByIp.refreshInterfaces();
      expect(vmByIp.selectedInterface?.name, equals('eth0'));
      expect(vmByIp.selectedInterface?.ip, equals('192.168.1.100'));
      expect(vmByIp.senderConfig.interface?.ip, equals('192.168.1.100'));
      expect(vmByIp.receiverConfig.interface?.ip, equals('192.168.1.100'));

      // 2. Name fallback when IP is absent or unmatched
      final vmByName = IgmpTesterViewModel(
        interfaceService: multiIfaces,
        snifferService: FakeQuerySnifferService(),
        launchAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '172.16.99.99',
          adapterName: 'WLAN',
        ),
      );
      addTearDown(vmByName.dispose);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(vmByName.selectedInterface?.name, equals('wlan0'));
      expect(vmByName.selectedInterface?.ip, equals('10.10.20.5'));

      // 3. Default fallback when neither IP nor name matches
      final vmFallback = IgmpTesterViewModel(
        interfaceService: multiIfaces,
        snifferService: FakeQuerySnifferService(),
        launchAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '172.16.99.99',
          adapterName: 'nonexistent0',
        ),
      );
      addTearDown(vmFallback.dispose);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(vmFallback.selectedInterface?.name, equals('eth0'));
      expect(vmFallback.selectedInterface?.ip, equals('192.168.1.100'));
    });

    test('Issue #2: startDemoWalkthrough loads 10 Tx/Rx streams & IGMP events, and endDemoWalkthrough clears all state', () async {
      final receiverService = MulticastReceiverService();
      final localWatchdog = IgmpQuerierWatchdog();
      final demoVm = IgmpTesterViewModel(
        interfaceService: fakeIfaces,
        snifferService: FakeQuerySnifferService(),
        watchdog: localWatchdog,
        receiverService: receiverService,
      );
      addTearDown(demoVm.dispose);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(demoVm.isDemoMode, isFalse);

      demoVm.startDemoWalkthrough();

      expect(demoVm.isDemoMode, isTrue);
      expect(demoVm.senderConfig.streams.length, equals(10));
      expect(demoVm.receiverConfig.streams.length, equals(10));
      expect(demoVm.igmpEvents.length, equals(4));
      expect(demoVm.querierStatus.health, equals(QuerierHealth.active));
      expect(demoVm.querierStatus.querierVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(demoVm.querierStatus.querierIp, equals('192.168.10.1'));

      // Inject a synthetic gap to verify endDemoWalkthrough clears gaps too
      const rxStream = MulticastReceiverStreamConfig(
        id: 'rx_gap_demo',
        name: 'Gap Demo',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      receiverService.addStreamForTesting(rxStream);
      final p1 = MulticastPacket(
        sessionId: 'demo_gap',
        sequenceNumber: 1,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: '239.255.0.1',
        destinationPort: 5004,
      );
      final p3 = MulticastPacket(
        sessionId: 'demo_gap',
        sequenceNumber: 3,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: '239.255.0.1',
        destinationPort: 5004,
      );
      receiverService.processDatagramForTesting(
        Datagram(p1.encode(), InternetAddress('192.168.1.50'), 40000),
        5004,
      );
      receiverService.processDatagramForTesting(
        Datagram(p3.encode(), InternetAddress('192.168.1.50'), 40000),
        5004,
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(demoVm.gaps, isNotEmpty);

      demoVm.endDemoWalkthrough();

      expect(demoVm.isDemoMode, isFalse);
      expect(demoVm.senderConfig.streams, isEmpty);
      expect(demoVm.receiverConfig.streams, isEmpty);
      expect(demoVm.igmpEvents, isEmpty);
      expect(demoVm.gaps, isEmpty);
      expect(demoVm.unsubscribedStreams, isEmpty);
      expect(demoVm.lastLeaveLatency, isNull);
      expect(demoVm.querierStatus.health, equals(QuerierHealth.idle));
      expect(demoVm.querierStatus.querierVersion, equals(IgmpProtocolVersion.unknown));
      expect(demoVm.querierStatus.querierIp, isNull);
    });
  });
}
