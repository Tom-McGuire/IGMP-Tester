import 'dart:io';
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

    test('IPv4 multicast validation checks Class D addresses (224.0.0.0 to 239.255.255.255)', () {
      expect(MulticastStreamConfig.isValidMulticastIpv4('239.255.0.1'), isTrue);
      expect(MulticastStreamConfig.isValidMulticastIpv4('224.0.0.1'), isTrue);
      expect(MulticastStreamConfig.isValidMulticastIpv4('239.192.0.1'), isTrue);
      expect(MulticastStreamConfig.isValidMulticastIpv4('239.255.255.255'), isTrue);

      // Invalid / Unicast / Class E / Malformed
      expect(MulticastStreamConfig.isValidMulticastIpv4('192.168.1.1'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('10.0.0.1'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('127.0.0.1'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('240.0.0.1'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('223.255.255.255'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('999.0.0.1'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4('not-an-ip'), isFalse);
      expect(MulticastStreamConfig.isValidMulticastIpv4(''), isFalse);
    });

    test('IP increment utility increments class D multicast addresses and clamps bounds', () {
      expect(MulticastStreamConfig.incrementIp('239.255.0.1', 1), equals('239.255.0.2'));
      expect(MulticastStreamConfig.incrementIp('239.255.0.1', 10), equals('239.255.0.11'));
      expect(MulticastStreamConfig.incrementIp('239.255.0.255', 1), equals('239.255.1.0'));

      // Overflow clamping
      expect(MulticastStreamConfig.incrementIp('239.255.255.255', 1), equals('239.255.255.255'));
    });

    test('CSV Export sanitizes formula triggers and handles quotes', () {
      final service = CsvExportService();
      final now = DateTime.now();
      final gaps = [
        MulticastGapEvent(
          id: 1,
          sessionId: 'sess-1',
          streamName: '=cmd|"/C calc"!A0', // Formula trigger
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
        MulticastGapEvent(
          id: 2,
          sessionId: '+inject',
          streamName: 'Stream "Special, Name"',
          groupAddress: '239.255.0.2',
          port: 5004,
          timestamp: now,
          startSeq: 20,
          endSeq: 21,
          missingPackets: 2,
          gapDuration: const Duration(milliseconds: 40),
          lastPacketTime: now.subtract(const Duration(milliseconds: 40)),
          resumedTime: now,
        ),
      ];

      final stats = const ReceiverStats(
        packetsReceived: 96,
        expectedPackets: 100,
        packetsLost: 4,
        lossRatePercent: 4.0,
        totalGaps: 2,
        maxGapPackets: 4,
        maxGapDurationMs: 80.0,
        avgGapDurationMs: 60.0,
        activeStreamsCount: 2,
      );

      final csv = service.generateGapsCsv(gaps: gaps, stats: stats);

      // Check summary
      expect(csv, contains('# Packets Received,96'));
      expect(csv, contains('# Average Gap Duration (ms),60.00'));

      // Check formula injection sanitization: leading = or + is prefixed with '
      expect(csv, contains("'=cmd|"));
      expect(csv, contains("'+inject"));

      // Check RFC 4180 quotes escaping
      expect(csv, contains('""Special, Name""'));
    });

    test('saveCsvToFile writes content correctly to filesystem', () async {
      final service = CsvExportService();
      final tempDir = await Directory.systemTemp.createTemp('igmp_csv_test_');
      final targetFile = '${tempDir.path}/test_report.csv';

      try {
        await service.saveCsvToFile(targetFile, 'col1,col2\nval1,val2\n');
        final file = File(targetFile);
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('col1,col2\nval1,val2\n'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
