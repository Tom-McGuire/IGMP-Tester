import 'dart:typed_data';
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
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.unknown));
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
      const line = '1700000000.5\t192.168.1.254\t224.0.0.1\t0x11\t100\t0.0.0.0\tv2';
      sniffer.parseLineForTesting(line);

      expect(sniffer.events.length, equals(1));
      final event = sniffer.events.first;
      expect(event.querierIp, equals('192.168.1.254'));
      expect(event.destinationIp, equals('224.0.0.1'));
      expect(event.typeName, equals('General Query'));
      expect(event.maxRespTimeSeconds, equals(10.0));
      expect(event.isGeneralQuery, isTrue);
      expect(event.protocolVersion, equals(IgmpProtocolVersion.igmpv2));

      expect(sniffer.querierIp, equals('192.168.1.254'));
      expect(sniffer.lastQueryTime, isNotNull);
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.igmpv2));

      await Future.delayed(const Duration(milliseconds: 10));
      expect(receivedEvent?.typeName, equals('General Query'));

      await sub.cancel();
    });

    test('parseLineForTesting decodes Group-Specific Query', () {
      const line = '1700000010.0\t10.0.0.1\t239.255.0.1\t0x11\t10\t239.255.0.1\tv2';
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
      expect(sniffer.events[3].protocolVersion, equals(IgmpProtocolVersion.igmpv1));
      expect(sniffer.events[2].typeName, equals('IGMPv2 Report'));
      expect(sniffer.events[2].protocolVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(sniffer.events[1].typeName, equals('IGMPv2 Leave'));
      expect(sniffer.events[0].typeName, equals('IGMPv3 Report'));
      expect(sniffer.events[0].protocolVersion, equals(IgmpProtocolVersion.igmpv3));
    });

    test('clearEvents clears event list and resets querier info', () {
      sniffer.parseLineForTesting('1700000000.0\t192.168.1.1\t224.0.0.1\t0x11\t100\t0.0.0.0\tv2');
      expect(sniffer.events, isNotEmpty);
      expect(sniffer.querierIp, isNotNull);
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.igmpv2));

      sniffer.clearEvents();

      expect(sniffer.events, isEmpty);
      expect(sniffer.lastQueryTime, isNull);
      expect(sniffer.querierIp, isNull);
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.unknown));
    });

    test('custom non-existent tshark path returns null in findTSharkPath', () async {
      final customSniffer = IgmpQuerySnifferService(customTSharkPath: '/invalid/path/to/tshark');
      final path = await customSniffer.findTSharkPath();
      expect(path, isNull);
      customSniffer.dispose();
    });

    test('parseLineForTesting decodes IGMPv1 and IGMPv2 lines with numeric or omitted version', () {
      // Explicit numeric v1 query (maxResp == 0)
      sniffer.parseLineForTesting('1700000030.0\t10.0.0.1\t224.0.0.1\t0x11\t0\t0.0.0.0\t1\t\t\t\t');
      expect(sniffer.events.first.protocolVersion, equals(IgmpProtocolVersion.igmpv1));
      expect(sniffer.events.first.version, equals('IGMPv1'));
      expect(sniffer.events.first.maxRespTimeSeconds, equals(0.0));

      // Inferred v1 when version column empty and maxResp == 0
      sniffer.parseLineForTesting('1700000031.0\t10.0.0.2\t224.0.0.1\t0x11\t0\t0.0.0.0\t');
      expect(sniffer.events.first.protocolVersion, equals(IgmpProtocolVersion.igmpv1));

      // Inferred v2 when version column empty and maxResp > 0
      sniffer.parseLineForTesting('1700000032.0\t10.0.0.3\t224.0.0.1\t0x11\t100\t0.0.0.0\t');
      expect(sniffer.events.first.protocolVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(sniffer.events.first.maxRespTimeSeconds, equals(10.0));
    });

    test('parseLineForTesting decodes enriched IGMPv3 query fields (QRV, QQIC, S-flag, sources)', () {
      // max_resp=129 (0x81 -> 13.6s), qrv=2, qqic=129 (0x81 -> 136s), s=1, two source IPs
      const v3Line =
          '1700000040.0\t10.201.100.1\t232.10.20.30\t0x11\t129\t232.10.20.30\t3\t2\t129\t1\t10.1.1.10,10.1.1.11';
      sniffer.parseLineForTesting(v3Line);

      final event = sniffer.events.first;
      expect(event.protocolVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(event.version, equals('IGMPv3'));
      expect(event.typeName, equals('Group-and-Source-Specific Query'));
      expect(event.maxRespTimeSeconds, equals(13.6));
      expect(event.qrv, equals(2));
      expect(event.qqicSeconds, equals(136));
      expect(event.suppressRouterProcessing, isTrue);
      expect(event.sourceAddresses, equals(['10.1.1.10', '10.1.1.11']));
      expect(event.isGeneralQuery, isFalse);
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.igmpv3));
    });

    test('parseRawPayloadForTesting records and emits parsed IGMPv3 query', () async {
      final payload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x64, // Max Resp Code: 100 -> 10.0s
        0x00, 0x00, // Checksum
        0x00, 0x00, 0x00, 0x00, // Group: 0.0.0.0
        0x02, // Resv=0, S=0, QRV=2
        0x7D, // QQIC=125 -> 125s
        0x00, 0x00, // Num Sources = 0
      ]);

      final event = sniffer.parseRawPayloadForTesting(
        payload,
        querierIp: '10.201.100.1',
        destinationIp: '224.0.0.1',
        interfaceName: 'eth0',
      );

      expect(event, isNotNull);
      expect(sniffer.events.length, equals(1));
      expect(sniffer.querierIp, equals('10.201.100.1'));
      expect(sniffer.querierVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(event!.qqicSeconds, equals(125));
      expect(event.qrv, equals(2));
    });
  });

  group('IGMP Wire Decoders and Raw Byte Parsing Tests', () {
    test('decodeQqic handles direct (<128) and floating-point (>=128) encodings', () {
      expect(IgmpQueryEvent.decodeQqic(0), equals(0));
      expect(IgmpQueryEvent.decodeQqic(60), equals(60));
      expect(IgmpQueryEvent.decodeQqic(125), equals(125));
      expect(IgmpQueryEvent.decodeQqic(127), equals(127));

      // 0x80: exp=0, mant=0 -> (0x10) << 3 = 128
      expect(IgmpQueryEvent.decodeQqic(0x80), equals(128));
      // 0x81: exp=0, mant=1 -> (0x11) << 3 = 136
      expect(IgmpQueryEvent.decodeQqic(0x81), equals(136));
      // 0x90: exp=1, mant=0 -> (0x10) << 4 = 256
      expect(IgmpQueryEvent.decodeQqic(0x90), equals(256));
      // 0xFF: exp=7, mant=15 -> (0x1F) << 10 = 31744
      expect(IgmpQueryEvent.decodeQqic(0xFF), equals(31744));
    });

    test('decodeMaxRespSeconds handles IGMPv2 linear tenths and IGMPv3 float exponent', () {
      // IGMPv2: always raw / 10.0
      expect(IgmpQueryEvent.decodeMaxRespSeconds(0, isV3: false), equals(0.0));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(100, isV3: false), equals(10.0));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(128, isV3: false), equals(12.8));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(255, isV3: false), equals(25.5));

      // IGMPv3 < 128: raw / 10.0
      expect(IgmpQueryEvent.decodeMaxRespSeconds(10, isV3: true), equals(1.0));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(100, isV3: true), equals(10.0));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(127, isV3: true), equals(12.7));

      // IGMPv3 >= 128: ((mant | 0x10) << (exp + 3)) / 10.0
      expect(IgmpQueryEvent.decodeMaxRespSeconds(0x80, isV3: true), equals(12.8));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(0x81, isV3: true), equals(13.6));
      expect(IgmpQueryEvent.decodeMaxRespSeconds(0xFF, isV3: true), equals(3174.4));
    });

    test('fromRawIgmpBytes parses 8-byte IGMPv1 Query (Max Resp == 0)', () {
      final payload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x00, // Max Resp Code == 0 -> IGMPv1
        0xEE, 0xFF, // Checksum
        0x00, 0x00, 0x00, 0x00, // Group: 0.0.0.0
      ]);

      final event = IgmpQueryEvent.fromRawIgmpBytes(
        payload,
        querierIp: '192.168.1.1',
      );

      expect(event, isNotNull);
      expect(event!.protocolVersion, equals(IgmpProtocolVersion.igmpv1));
      expect(event.version, equals('IGMPv1'));
      expect(event.typeHex, equals('0x11'));
      expect(event.typeName, equals('General Query'));
      expect(event.groupAddress, equals('0.0.0.0'));
      expect(event.maxRespTimeSeconds, equals(0.0));
      expect(event.isGeneralQuery, isTrue);
      expect(event.qrv, isNull);
      expect(event.qqicSeconds, isNull);
      expect(event.suppressRouterProcessing, isFalse);
      expect(event.sourceAddresses, isEmpty);
    });

    test('fromRawIgmpBytes parses 8-byte IGMPv2 General and Group-Specific Queries (Max Resp > 0)', () {
      final generalPayload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x64, // Max Resp Code = 100 -> 10.0s -> IGMPv2
        0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, // 0.0.0.0
      ]);

      final general = IgmpQueryEvent.fromRawIgmpBytes(
        generalPayload,
        querierIp: '10.0.0.1',
      );
      expect(general, isNotNull);
      expect(general!.protocolVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(general.version, equals('IGMPv2'));
      expect(general.typeName, equals('General Query'));
      expect(general.maxRespTimeSeconds, equals(10.0));
      expect(general.isGeneralQuery, isTrue);

      final specificPayload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x0A, // Max Resp Code = 10 -> 1.0s
        0x00, 0x00,
        239, 255, 0, 1, // Group: 239.255.0.1
      ]);

      final specific = IgmpQueryEvent.fromRawIgmpBytes(
        specificPayload,
        querierIp: '10.0.0.1',
      );
      expect(specific, isNotNull);
      expect(specific!.protocolVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(specific.typeName, equals('Group-Specific Query'));
      expect(specific.groupAddress, equals('239.255.0.1'));
      expect(specific.maxRespTimeSeconds, equals(1.0));
      expect(specific.isGeneralQuery, isFalse);
    });

    test('fromRawIgmpBytes parses 12-byte IGMPv3 General Query with S-flag, QRV, and QQIC', () {
      final payload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x81, // Max Resp Code = 129 -> 13.6s
        0x00, 0x00, // Checksum
        0x00, 0x00, 0x00, 0x00, // Group: 0.0.0.0
        0x0A, // Resv=0, S=1 (0x08), QRV=2 (0x02)
        0x7D, // QQIC = 125 -> 125s
        0x00, 0x00, // Num Sources = 0
      ]);

      final event = IgmpQueryEvent.fromRawIgmpBytes(
        payload,
        querierIp: '10.201.100.1',
      );

      expect(event, isNotNull);
      expect(event!.protocolVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(event.version, equals('IGMPv3'));
      expect(event.typeName, equals('General Query'));
      expect(event.maxRespTimeSeconds, equals(13.6));
      expect(event.suppressRouterProcessing, isTrue);
      expect(event.qrv, equals(2));
      expect(event.qqicSeconds, equals(125));
      expect(event.sourceAddresses, isEmpty);
      expect(event.isGeneralQuery, isTrue);

      final map = event.toMap();
      expect(map['protocolVersion'], equals('igmpv3'));
      expect(map['qrv'], equals(2));
      expect(map['qqicSeconds'], equals(125));
      expect(map['suppressRouterProcessing'], isTrue);
      expect(map['sourceAddresses'], isEmpty);
    });

    test('fromRawIgmpBytes parses IGMPv3 Group-and-Source-Specific Query with float QQIC and sources', () {
      final payload = Uint8List.fromList([
        0x11, // Type: Membership Query
        0x14, // Max Resp Code = 20 -> 2.0s
        0x00, 0x00, // Checksum
        232, 1, 2, 3, // Group: 232.1.2.3 (SSM)
        0x03, // Resv=0, S=0, QRV=3
        0x81, // QQIC = 0x81 -> 136s
        0x00, 0x02, // Num Sources = 2
        10, 1, 2, 3, // Source 1: 10.1.2.3
        10, 1, 2, 4, // Source 2: 10.1.2.4
      ]);

      final event = IgmpQueryEvent.fromRawIgmpBytes(
        payload,
        querierIp: '172.16.0.1',
      );

      expect(event, isNotNull);
      expect(event!.protocolVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(event.typeName, equals('Group-and-Source-Specific Query'));
      expect(event.groupAddress, equals('232.1.2.3'));
      expect(event.maxRespTimeSeconds, equals(2.0));
      expect(event.suppressRouterProcessing, isFalse);
      expect(event.qrv, equals(3));
      expect(event.qqicSeconds, equals(136));
      expect(event.sourceAddresses, equals(['10.1.2.3', '10.1.2.4']));
      expect(event.isGeneralQuery, isFalse);
    });

    test('fromRawIgmpBytes safely handles truncated payloads and bounded source counts', () {
      // Too short (< 8 bytes)
      expect(IgmpQueryEvent.fromRawIgmpBytes(Uint8List.fromList([0x11, 0x64, 0x00])), isNull);

      // Invalid query length between 8 and 12 bytes
      expect(
        IgmpQueryEvent.fromRawIgmpBytes(Uint8List.fromList(List.filled(10, 0x11))),
        isNull,
      );

      // Header claims num_src = 5, but payload only contains 1 full IPv4 source
      final truncatedSourcesPayload = Uint8List.fromList([
        0x11, 0x0A, 0x00, 0x00,
        232, 0, 0, 1,
        0x02, 0x7D,
        0x00, 0x05, // Claims 5 sources
        192, 168, 50, 10, // Only 1 complete source
        192, 168, // Incomplete trailing bytes
      ]);
      final event = IgmpQueryEvent.fromRawIgmpBytes(truncatedSourcesPayload);
      expect(event, isNotNull);
      expect(event!.sourceAddresses, equals(['192.168.50.10']));
    });
  });
}
