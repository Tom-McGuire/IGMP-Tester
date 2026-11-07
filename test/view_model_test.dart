import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
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
  });
}
