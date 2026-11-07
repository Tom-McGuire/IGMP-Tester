import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/igmp/igmp_query_sniffer.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';

void main() {
  group('IgmpQuerySnifferService Tests', () {
    late IgmpQuerySnifferService sniffer;

    setUp(() {
      sniffer = IgmpQuerySnifferService();
    });

    tearDown(() {
      sniffer.dispose();
    });

    test('initial state has no events, not running, null querier IP', () {
      expect(sniffer.isRunning, isFalse);
      expect(sniffer.events, isEmpty);
      expect(sniffer.lastQueryTime, isNull);
      expect(sniffer.querierIp, isNull);
    });

    test('parseLineForTesting ignores malformed lines with fewer than 4 tokens', () {
      sniffer.parseLineForTesting('');
      sniffer.parseLineForTesting('foo\tbar');
      sniffer.parseLineForTesting('12345.67\t192.168.1.1\t224.0.0.1');

      expect(sniffer.events, isEmpty);
    });

    test('parseLineForTesting accurately decodes IGMP General Query', () async {
      IgmpQueryEvent? receivedEvent;
      final sub = sniffer.queryStream.listen((event) => receivedEvent = event);

      // Format: epoch \t srcIp \t dstIp \t type \t maxRespDeci \t maddr \t ver
      final line = '1700000000.5\t192.168.1.254\t224.0.0.1\t0x11\t100\t0.0.0.0\tv2';
      sniffer.parseLineForTesting(line);

      expect(sniffer.events.length, equals(1));
      final event = sniffer.events.first;
      expect(event.querierIp, equals('192.168.1.254'));
      expect(event.destinationIp, equals('224.0.0.1'));
      expect(event.typeName, equals('General Query'));
      expect(event.maxRespTimeSeconds, equals(10.0));
      expect(event.isGeneralQuery, isTrue);

      expect(sniffer.querierIp, equals('192.168.1.254'));
      expect(sniffer.lastQueryTime, isNotNull);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(receivedEvent?.typeName, equals('General Query'));

      await sub.cancel();
    });

    test('parseLineForTesting decodes Group-Specific Query', () {
      final line = '1700000010.0\t10.0.0.1\t239.255.0.1\t0x11\t10\t239.255.0.1\tv2';
      sniffer.parseLineForTesting(line);

      expect(sniffer.events.length, equals(1));
      final event = sniffer.events.first;
      expect(event.typeName, equals('Group-Specific Query'));
      expect(event.groupAddress, equals('239.255.0.1'));
      expect(event.maxRespTimeSeconds, equals(1.0));
      expect(event.isGeneralQuery, isFalse);
    });

    test('parseLineForTesting decodes IGMP reports and leave types', () {
      // 0x12 = v1 report, 0x16 = v2 report, 0x17 = v2 leave, 0x22 = v3 report
      sniffer.parseLineForTesting('1700000020.0\t192.168.1.10\t239.1.1.1\t0x12\t0\t239.1.1.1\tv1');
      sniffer.parseLineForTesting('1700000021.0\t192.168.1.10\t239.1.1.1\t0x16\t0\t239.1.1.1\tv2');
      sniffer.parseLineForTesting('1700000022.0\t192.168.1.10\t224.0.0.2\t0x17\t0\t239.1.1.1\tv2');
      sniffer.parseLineForTesting('1700000023.0\t192.168.1.10\t224.0.0.22\t0x22\t0\t239.1.1.1\tv3');

      expect(sniffer.events.length, equals(4));
      expect(sniffer.events[3].typeName, equals('IGMPv1 Report'));
      expect(sniffer.events[2].typeName, equals('IGMPv2 Report'));
      expect(sniffer.events[1].typeName, equals('IGMPv2 Leave'));
      expect(sniffer.events[0].typeName, equals('IGMPv3 Report'));
    });

    test('clearEvents clears event list and resets querier info', () {
      sniffer.parseLineForTesting('1700000000.0\t192.168.1.1\t224.0.0.1\t0x11\t100\t0.0.0.0\tv2');
      expect(sniffer.events, isNotEmpty);
      expect(sniffer.querierIp, isNotNull);

      sniffer.clearEvents();

      expect(sniffer.events, isEmpty);
      expect(sniffer.lastQueryTime, isNull);
      expect(sniffer.querierIp, isNull);
    });

    test('custom non-existent tshark path returns null in findTSharkPath', () async {
      final customSniffer = IgmpQuerySnifferService(customTSharkPath: '/invalid/path/to/tshark');
      final path = await customSniffer.findTSharkPath();
      expect(path, isNull);
      customSniffer.dispose();
    });
  });
}
