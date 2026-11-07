import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_stats.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';

void main() {
  group('NetworkInterfaceInfo Tests', () {
    test('displayName formats interface name and IP', () {
      const iface = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '192.168.10.50',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );
      expect(iface.displayName, equals('eth0 (192.168.10.50)'));
    });

    test('prefixToSubnetMask converts CIDR prefixes accurately', () {
      expect(NetworkInterfaceInfo.prefixToSubnetMask(8), equals('255.0.0.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(16), equals('255.255.0.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(24), equals('255.255.255.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(28), equals('255.255.255.240'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(32), equals('255.255.255.255'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(0), equals('0.0.0.0'));
      // Invalid bounds fall back to /24
      expect(NetworkInterfaceInfo.prefixToSubnetMask(-1), equals('255.255.255.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(33), equals('255.255.255.0'));
    });

    test('equality and hashCode match by name and ip', () {
      const iface1 = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '10.0.0.1',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );
      const iface2 = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '10.0.0.1',
        subnetMask: '255.0.0.0',
        prefixLength: 8,
      );
      const iface3 = NetworkInterfaceInfo(
        name: 'wlan0',
        ip: '10.0.0.1',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );

      expect(iface1, equals(iface2));
      expect(iface1.hashCode, equals(iface2.hashCode));
      expect(iface1, isNot(equals(iface3)));
    });
  });

  group('IgmpQueryEvent Tests', () {
    test('isQuery and isGeneralQuery logic', () {
      final generalQuery = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'General Query',
      );

      expect(generalQuery.isQuery, isTrue);
      expect(generalQuery.isGeneralQuery, isTrue);

      final groupSpecificQuery = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.1',
        destinationIp: '239.255.0.1',
        typeHex: '0x11',
        typeName: 'Group-Specific Query',
        groupAddress: '239.255.0.1',
        maxRespTimeSeconds: 1.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'Specific Query',
      );

      expect(groupSpecificQuery.isQuery, isTrue);
      expect(groupSpecificQuery.isGeneralQuery, isFalse);

      final reportEvent = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.50',
        destinationIp: '239.255.0.1',
        typeHex: '0x16',
        typeName: 'V2 Membership Report',
        groupAddress: '239.255.0.1',
        maxRespTimeSeconds: 0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'Join',
      );

      expect(reportEvent.isQuery, isFalse);
      expect(reportEvent.isGeneralQuery, isFalse);
    });

    test('toMap serialization returns all fields', () {
      final now = DateTime.now();
      final event = IgmpQueryEvent(
        timestamp: now,
        querierIp: '10.0.0.254',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'General Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv3',
        interfaceName: 'enp3s0',
        rawSummary: 'Summary text',
      );

      final map = event.toMap();
      expect(map['timestamp'], equals(now.toIso8601String()));
      expect(map['querierIp'], equals('10.0.0.254'));
      expect(map['destinationIp'], equals('224.0.0.1'));
      expect(map['typeHex'], equals('0x11'));
      expect(map['version'], equals('IGMPv3'));
      expect(map['interfaceName'], equals('enp3s0'));
    });
  });

  group('SenderStats and ReceiverStats Tests', () {
    test('SenderStats copyWith preserves fields correctly', () {
      const stats = SenderStats(
        streamId: 's1',
        streamName: 'Stream 1',
        packetsSent: 100,
        currentBitrateMbps: 4.5,
      );

      final updated = stats.copyWith(
        packetsSent: 200,
        currentBitrateMbps: 8.0,
        bytesSent: 102400,
      );

      expect(updated.streamId, equals('s1'));
      expect(updated.streamName, equals('Stream 1'));
      expect(updated.packetsSent, equals(200));
      expect(updated.currentBitrateMbps, equals(8.0));
      expect(updated.bytesSent, equals(102400));
    });

    test('ReceiverStats copyWith preserves fields correctly', () {
      const stats = ReceiverStats(
        streamId: 'r1',
        streamName: 'Group 1',
        packetsReceived: 950,
        expectedPackets: 1000,
        packetsLost: 50,
        lossRatePercent: 5.0,
      );

      final updated = stats.copyWith(
        packetsReceived: 1000,
        lossRatePercent: 0.0,
        jitterMs: 1.25,
      );

      expect(updated.streamId, equals('r1'));
      expect(updated.streamName, equals('Group 1'));
      expect(updated.packetsReceived, equals(1000));
      expect(updated.lossRatePercent, equals(0.0));
      expect(updated.jitterMs, equals(1.25));
    });
  });

  group('MulticastConfig Tests', () {
    test('MulticastStreamConfig properties and endpoint calculation', () {
      const stream = MulticastStreamConfig(
        id: 'tx_1',
        name: 'Test Stream',
        groupAddress: '239.255.0.1',
        port: 5004,
        packetsPerSecond: 100,
        packetSizeBytes: 1250,
        ttl: 16,
      );

      expect(stream.endpoint, equals('239.255.0.1:5004'));
      expect(stream.ttl, equals(16));

      final updated = stream.copyWith(port: 5005, packetsPerSecond: 200);
      expect(updated.port, equals(5005));
      expect(updated.packetsPerSecond, equals(200));
      expect(updated.endpoint, equals('239.255.0.1:5005'));
    });

    test('MulticastSenderConfig and MulticastReceiverConfig defaults', () {
      const txConfig = MulticastSenderConfig();
      expect(txConfig.streams, isNotEmpty);
      expect(txConfig.enableLoopback, isTrue);
      expect(txConfig.streams.first.ttl, equals(64));

      const rxConfig = MulticastReceiverConfig();
      expect(rxConfig.streams, isNotEmpty);
      expect(rxConfig.enableLoopback, isTrue);
    });
  });
}
