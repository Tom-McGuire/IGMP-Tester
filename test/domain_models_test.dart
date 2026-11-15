import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
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

    test('MulticastStreamConfig dscpPreset and MulticastReceiverStreamConfig SSM/DSCP helpers', () {
      const tx = MulticastStreamConfig(
        id: 'tx_qos',
        name: 'EF Audio',
        dscpPreset: DscpPreset.ef,
      );
      expect(tx.dscpPreset, equals(DscpPreset.ef));
      expect(tx.copyWith(dscpPreset: DscpPreset.af41).dscpPreset, equals(DscpPreset.af41));

      expect(IgmpJoinMode.asm.isAsm, isTrue);
      expect(IgmpJoinMode.ssm.isSsm, isTrue);
      expect(MulticastReceiverStreamConfig.isSsmGroupIpv4('232.1.2.3'), isTrue);
      expect(MulticastReceiverStreamConfig.isSsmGroupIpv4('239.1.2.3'), isFalse);
      expect(MulticastReceiverStreamConfig.isValidUnicastSourceIp('10.0.0.10'), isTrue);
      expect(MulticastReceiverStreamConfig.isValidUnicastSourceIp('239.0.0.1'), isFalse);
      expect(MulticastReceiverStreamConfig.isValidUnicastSourceIp('0.0.0.0'), isFalse);

      const rx = MulticastReceiverStreamConfig(
        id: 'rx_ssm',
        name: 'SSM Feed',
        groupAddress: '232.1.1.1',
        joinMode: IgmpJoinMode.ssm,
        sourceFilterIp: ' 10.0.0.10 ',
        expectedDscp: DscpPreset.ef,
      );
      expect(rx.isSsm, isTrue);
      expect(rx.normalizedSourceIp, equals('10.0.0.10'));
      expect(rx.expectedDscp, equals(DscpPreset.ef));

      final cleared = rx.copyWith(
        joinMode: IgmpJoinMode.asm,
        clearSourceFilterIp: true,
        clearExpectedDscp: true,
      );
      expect(cleared.isSsm, isFalse);
      expect(cleared.sourceFilterIp, isNull);
      expect(cleared.expectedDscp, isNull);
    });
  });

  group('FastLeaveStatus & LeaveLatencyResult Tests', () {
    test('classifyLatency maps 0-50ms, 51-500ms, and >500ms boundaries accurately', () {
      expect(FastLeaveStatus.classifyLatency(0), equals(FastLeaveStatus.fastLeaveActive));
      expect(FastLeaveStatus.classifyLatency(50), equals(FastLeaveStatus.fastLeaveActive));
      expect(FastLeaveStatus.classifyLatency(51), equals(FastLeaveStatus.delayedPrune));
      expect(FastLeaveStatus.classifyLatency(500), equals(FastLeaveStatus.delayedPrune));
      expect(FastLeaveStatus.classifyLatency(501), equals(FastLeaveStatus.noFastLeave));
      expect(FastLeaveStatus.fastLeaveActive.isComplete, isTrue);
      expect(FastLeaveStatus.measuring.isComplete, isFalse);
      expect(FastLeaveStatus.aborted.isComplete, isFalse);
    });

    test('LeaveLatencyResult copyWith and streamKey preserve metadata', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final result = LeaveLatencyResult(
        streamId: 'rx_1',
        streamName: 'Audio 1',
        groupIp: '239.255.0.1',
        port: 5004,
        leaveIssuedAt: t0,
        leaveLatencyMs: 25,
        trailingPacketsReceived: 2,
        status: FastLeaveStatus.fastLeaveActive,
      );
      expect(result.endpoint, equals('239.255.0.1:5004'));
      expect(result.streamKey, equals('rx_1'));

      final updated = result.copyWith(leaveLatencyMs: 600, status: FastLeaveStatus.noFastLeave);
      expect(updated.leaveLatencyMs, equals(600));
      expect(updated.status, equals(FastLeaveStatus.noFastLeave));
      expect(updated.trailingPacketsReceived, equals(2));
    });
  });
}
