import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_gap_event.dart';
import 'package:igmp_tester/domain/models/multicast_stats.dart';
import 'package:igmp_tester/data/services/export/csv_export_service.dart';

void main() {
  group('Multicast Gap Event & CSV Tests', () {
    test('MulticastGapEvent properties and calculations', () {
      final now = DateTime.now();
      final lastTime = now.subtract(const Duration(milliseconds: 150));

      final gap = MulticastGapEvent(
        id: 1,
        sessionId: 'sess-abc',
        streamName: 'Stream 1',
        groupAddress: '239.255.0.1',
        port: 5004,
        timestamp: now,
        startSeq: 101,
        endSeq: 110,
        missingPackets: 10,
        gapDuration: const Duration(milliseconds: 150),
        lastPacketTime: lastTime,
        resumedTime: now,
      );

      expect(gap.id, equals(1));
      expect(gap.sessionId, equals('sess-abc'));
      expect(gap.streamName, equals('Stream 1'));
      expect(gap.groupAddress, equals('239.255.0.1'));
      expect(gap.port, equals(5004));
      expect(gap.startSeq, equals(101));
      expect(gap.endSeq, equals(110));
      expect(gap.missingPackets, equals(10));
      expect(gap.gapDurationMs, equals(150.0));
      expect(gap.sequenceRange, equals('#101 – #110'));
      expect(gap.endpoint, equals('239.255.0.1:5004'));
    });

    test('Single packet gap range formatting', () {
      final now = DateTime.now();
      final gap = MulticastGapEvent(
        id: 2,
        sessionId: 'sess-abc',
        timestamp: now,
        startSeq: 42,
        endSeq: 42,
        missingPackets: 1,
        gapDuration: const Duration(milliseconds: 20),
        lastPacketTime: now.subtract(const Duration(milliseconds: 20)),
        resumedTime: now,
      );

      expect(gap.sequenceRange, equals('#42'));
    });

    test('IP increment utility increments class D multicast addresses', () {
      expect(MulticastStreamConfig.incrementIp('239.255.0.1', 1), equals('239.255.0.2'));
      expect(MulticastStreamConfig.incrementIp('239.255.0.1', 10), equals('239.255.0.11'));
      expect(MulticastStreamConfig.incrementIp('239.255.0.255', 1), equals('239.255.1.0'));
    });

    test('CSV Export contains header and gap rows with stream info', () {
      final service = CsvExportService();
      final now = DateTime.now();
      final gaps = [
        MulticastGapEvent(
          id: 1,
          sessionId: 'sess-1',
          streamName: 'Stream 1',
          groupAddress: '239.255.0.1',
          port: 5004,
          timestamp: now,
          startSeq: 15,
          endSeq: 18,
          missingPackets: 4,
          gapDuration: const Duration(milliseconds: 80),
          lastPacketTime: now.subtract(const Duration(milliseconds: 80)),
          resumedTime: now,
        ),
      ];

      final stats = const ReceiverStats(
        packetsReceived: 96,
        expectedPackets: 100,
        packetsLost: 4,
        lossRatePercent: 4.0,
        totalGaps: 1,
        maxGapPackets: 4,
        maxGapDurationMs: 80.0,
        avgGapDurationMs: 80.0,
        activeSessionId: 'sess-1',
        activeStreamsCount: 1,
      );

      final csv = service.generateGapsCsv(gaps: gaps, stats: stats);

      expect(csv, contains('# Packets Received,96'));
      expect(csv, contains('# Packets Lost,4'));
      expect(csv, contains('# Loss Rate %,4.00%'));
      expect(csv, contains('Gap_ID,Stream_Name,Group_Address,UDP_Port,Session_ID'));
      expect(csv, contains('1,"Stream 1",239.255.0.1,5004,sess-1'));
      expect(csv, contains('15,18,4,80.000'));
    });
  });
}
