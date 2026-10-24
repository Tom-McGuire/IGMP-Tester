import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';
import 'package:igmp_tester/data/services/multicast/multicast_receiver_service.dart';

void main() {
  group('MulticastReceiverService Demux & Reliability Tests', () {
    late MulticastReceiverService receiverService;

    setUp(() {
      receiverService = MulticastReceiverService();
    });

    tearDown(() {
      receiverService.dispose();
    });

    Datagram createDatagram({
      required String destinationGroup,
      required int destinationPort,
      required String sessionId,
      required int seq,
    }) {
      final packet = MulticastPacket(
        sessionId: sessionId,
        sequenceNumber: seq,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: destinationGroup,
        destinationPort: destinationPort,
      );
      return Datagram(
        packet.encode(),
        InternetAddress('192.168.1.100'), // Sender source IP
        54321,
      );
    }

    test('demuxes multiple streams on shared UDP port 5004 accurately by destination group', () {
      final group1 = const MulticastReceiverStreamConfig(
        id: 'rx_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      final group2 = const MulticastReceiverStreamConfig(
        id: 'rx_2',
        name: 'Group 2',
        groupAddress: '239.255.0.2',
        port: 5004,
      );

      receiverService.addStreamForTesting(group1);
      receiverService.addStreamForTesting(group2);

      // Packet for Group 2 arrives FIRST
      final dGroup2 = createDatagram(
        destinationGroup: '239.255.0.2',
        destinationPort: 5004,
        sessionId: 'sess_g2_1',
        seq: 1,
      );
      receiverService.processDatagramForTesting(dGroup2, 5004);

      // Packet for Group 1 arrives SECOND
      final dGroup1 = createDatagram(
        destinationGroup: '239.255.0.1',
        destinationPort: 5004,
        sessionId: 'sess_g1_1',
        seq: 1,
      );
      receiverService.processDatagramForTesting(dGroup1, 5004);

      receiverService.recalculateStatsForTesting();
      final stats = receiverService.currentStreamStats;

      expect(stats['rx_1']?.packetsReceived, equals(1));
      expect(stats['rx_1']?.groupAddress, equals('239.255.0.1'));
      expect(stats['rx_2']?.packetsReceived, equals(1));
      expect(stats['rx_2']?.groupAddress, equals('239.255.0.2'));
    });

    test('sender restart with new session ID does not misattribute or corrupt streams', () {
      final group1 = const MulticastReceiverStreamConfig(
        id: 'rx_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      final group2 = const MulticastReceiverStreamConfig(
        id: 'rx_2',
        name: 'Group 2',
        groupAddress: '239.255.0.2',
        port: 5004,
      );

      receiverService.addStreamForTesting(group1);
      receiverService.addStreamForTesting(group2);

      // Send initial packets
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'run_1', seq: 1),
        5004,
      );
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.2', destinationPort: 5004, sessionId: 'run_1', seq: 1),
        5004,
      );

      // Sender stopped and restarted with new sessionId 'run_2'
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.2', destinationPort: 5004, sessionId: 'run_2', seq: 1),
        5004,
      );
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'run_2', seq: 1),
        5004,
      );

      receiverService.recalculateStatsForTesting();
      final stats = receiverService.currentStreamStats;

      expect(stats['rx_1']?.packetsReceived, equals(2));
      expect(stats['rx_2']?.packetsReceived, equals(2));
      // No false-positive gaps created due to restart
      expect(stats['rx_1']?.totalGaps, equals(0));
      expect(stats['rx_2']?.totalGaps, equals(0));
    });

    test('drops datagrams for unsubscribed multicast groups on shared port', () {
      final group1 = const MulticastReceiverStreamConfig(
        id: 'rx_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      receiverService.addStreamForTesting(group1);

      // Datagram for unsubscribed group 239.255.99.99
      final unsubscribed = createDatagram(
        destinationGroup: '239.255.99.99',
        destinationPort: 5004,
        sessionId: 'rogue',
        seq: 1,
      );
      receiverService.processDatagramForTesting(unsubscribed, 5004);

      receiverService.recalculateStatsForTesting();
      final stats = receiverService.currentStreamStats;

      expect(stats['rx_1']?.packetsReceived, equals(0));
    });

    test('gaps list is capped at maxRetainedGaps (5000) and slides', () {
      final group1 = const MulticastReceiverStreamConfig(
        id: 'rx_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      receiverService.addStreamForTesting(group1);

      // First packet
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'stress', seq: 1),
        5004,
      );

      // Trigger 5050 gaps by jumping seq numbers
      int currentSeq = 1;
      for (int i = 0; i < 5050; i++) {
        currentSeq += 2; // missing 1 packet each time
        receiverService.processDatagramForTesting(
          createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'stress', seq: currentSeq),
          5004,
        );
      }

      expect(receiverService.gaps.length, equals(5000));
      receiverService.recalculateStatsForTesting();
      final stats = receiverService.currentStats;
      expect(stats.totalGaps, equals(5050)); // Total count tracked accurately
    });

    test('aggregate avgGapDurationMs calculates weighted average across all streams', () {
      final group1 = const MulticastReceiverStreamConfig(
        id: 'rx_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
      );
      receiverService.addStreamForTesting(group1);

      // Send packet 1, then packet 5 (gap of 3 packets)
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'avg_test', seq: 1),
        5004,
      );
      receiverService.processDatagramForTesting(
        createDatagram(destinationGroup: '239.255.0.1', destinationPort: 5004, sessionId: 'avg_test', seq: 5),
        5004,
      );

      receiverService.recalculateStatsForTesting();
      final stats = receiverService.currentStats;

      expect(stats.totalGaps, equals(1));
      expect(stats.packetsLost, equals(3));
      expect(stats.maxGapPackets, equals(3));
      expect(stats.avgGapDurationMs, isNotNull);
    });
  });
}
