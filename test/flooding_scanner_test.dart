import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/multicast/flooding_scanner_service.dart';
import 'package:igmp_tester/domain/models/flooded_stream_entry.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';
import 'package:igmp_tester/ui/features/receiver/views/flooded_streams_sheet.dart';
import 'package:igmp_tester/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Uint8List _buildSacnPacket({required int universe, int length = 126}) {
  final bytes = Uint8List(length);
  // 0..1: Preamble Size (0x0010)
  bytes[0] = 0x00;
  bytes[1] = 0x10;
  // 4..12: 'ASC-E1.17'
  const magic = [0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37];
  bytes.setRange(4, 13, magic);
  if (length >= 115) {
    ByteData.sublistView(bytes).setUint16(113, universe, Endian.big);
  }
  return bytes;
}

Uint8List _buildArtNetPacket({required int universe, int length = 18}) {
  final bytes = Uint8List(length);
  // 0..7: 'Art-Net\0'
  const magic = [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00];
  bytes.setRange(0, 8, magic);
  if (length >= 10) {
    // OpDmx (0x5000 little-endian)
    ByteData.sublistView(bytes).setUint16(8, 0x5000, Endian.little);
  }
  if (length >= 16) {
    ByteData.sublistView(bytes).setUint16(14, universe, Endian.little);
  }
  return bytes;
}

Uint8List _buildRtpPacket({
  int firstByte = 0x80,
  int payloadType = 96,
  int sequence = 42,
  int length = 24,
}) {
  final bytes = Uint8List(length);
  bytes[0] = firstByte;
  if (length >= 2) {
    bytes[1] = payloadType & 0x7F;
  }
  if (length >= 4) {
    ByteData.sublistView(bytes).setUint16(2, sequence, Endian.big);
  }
  return bytes;
}

void main() {
  group('FloodedStreamEntry Model Tests', () {
    test('formats rates, bytes, protocolDisplay, endpoint, and copyWith', () {
      final t0 = DateTime(2026, 11, 15, 10, 0, 0);
      final t1 = DateTime(2026, 11, 15, 10, 0, 2);
      final entry = FloodedStreamEntry(
        groupIp: '239.255.0.12',
        destinationPort: 5568,
        sourceIp: '10.201.100.101',
        detectedProtocol: 'sACN',
        protocolDetail: 'Univ 12',
        packetCount: 88,
        bytesReceived: 56144,
        firstSeen: t0,
        lastSeen: t1,
        estimatedBitrateBps: 224576.0,
      );

      expect(entry.endpoint, equals('239.255.0.12:5568'));
      expect(entry.streamKey, equals('10.201.100.101|239.255.0.12|5568'));
      expect(entry.protocolDisplay, equals('sACN Univ 12'));
      expect(entry.formattedBitrate, equals('224.6 kbps'));
      expect(entry.formattedBytes, equals('54.8 KB'));
      expect(entry.observationDuration, equals(const Duration(seconds: 2)));

      final mbpsEntry = entry.copyWith(
        estimatedBitrateBps: 2500000.0,
        bytesReceived: 2 * 1024 * 1024,
      );
      expect(mbpsEntry.formattedBitrate, equals('2.50 Mbps'));
      expect(mbpsEntry.formattedBytes, equals('2.00 MB'));
      expect(mbpsEntry.groupIp, equals('239.255.0.12'));

      final cleared = entry.copyWith(
        clearProtocolDetail: true,
        estimatedBitrateBps: 500.0,
        bytesReceived: 512,
      );
      expect(cleared.protocolDetail, isNull);
      expect(cleared.protocolDisplay, equals('sACN'));
      expect(cleared.formattedBitrate, equals('500 bps'));
      expect(cleared.formattedBytes, equals('512 B'));
    });
  });

  group('FloodingScannerService.identifyProtocol Tests', () {
    test('identifies sACN (E1.31) with ASC-E1.17 signature and universe bytes 113-114', () {
      final sacn1 = _buildSacnPacket(universe: 1);
      final (proto1, detail1) =
          FloodingScannerService.identifyProtocol(sacn1, 5568);
      expect(proto1, equals('sACN'));
      expect(detail1, equals('Univ 1'));

      final sacn300 = _buildSacnPacket(universe: 300);
      final (proto300, detail300) =
          FloodingScannerService.identifyProtocol(sacn300, 5568);
      expect(proto300, equals('sACN'));
      expect(detail300, equals('Univ 300'));

      // Short ACN E1.17 header (< 115 bytes) still identifies sACN
      final shortSacn = _buildSacnPacket(universe: 1, length: 20);
      final (protoShort, detailShort) =
          FloodingScannerService.identifyProtocol(shortSacn, 5568);
      expect(protoShort, equals('sACN'));
      expect(detailShort, equals('E1.31'));
    });

    test('identifies Art-Net header and extracts little-endian universe bytes 14-15', () {
      final artNet5 = _buildArtNetPacket(universe: 5);
      final (proto5, detail5) =
          FloodingScannerService.identifyProtocol(artNet5, 6454);
      expect(proto5, equals('Art-Net'));
      expect(detail5, equals('Univ 5'));

      final artNet258 = _buildArtNetPacket(universe: 258);
      final (proto258, detail258) =
          FloodingScannerService.identifyProtocol(artNet258, 6454);
      expect(proto258, equals('Art-Net'));
      expect(detail258, equals('Univ 258'));

      // Short ArtPoll-like packet (< 16 bytes)
      final shortArtNet = _buildArtNetPacket(universe: 0, length: 14);
      final (protoShort, detailShort) =
          FloodingScannerService.identifyProtocol(shortArtNet, 6454);
      expect(protoShort, equals('Art-Net'));
      expect(detailShort, isNull);
    });

    test('identifies IGMP Tester packets using MulticastPacket.decode', () {
      final encoded = MulticastPacket(
        sessionId: 'flood_test',
        sequenceNumber: 77,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 128,
        destinationGroup: '239.255.10.20',
        destinationPort: 4321,
      ).encode();

      final (proto, detail) =
          FloodingScannerService.identifyProtocol(encoded, 4321);
      expect(proto, equals('IGMP Tester'));
      expect(detail, contains('flood_test'));
      expect(detail, contains('77'));
    });

    test('identifies Dante / RTP with 0x80 RTP header on port 5004 and 4321', () {
      final rtp = _buildRtpPacket(firstByte: 0x80, payloadType: 96, sequence: 42);
      final (proto5004, detail5004) =
          FloodingScannerService.identifyProtocol(rtp, 5004);
      expect(proto5004, equals('Dante / RTP'));
      expect(detail5004, contains('PT 96'));
      expect(detail5004, contains('seq 42'));

      // Minimal 1-byte 0x80 payload on 5004
      final minimalRtp = Uint8List.fromList([0x80]);
      final (protoMin, detailMin) =
          FloodingScannerService.identifyProtocol(minimalRtp, 5004);
      expect(protoMin, equals('Dante / RTP'));
      expect(detailMin, equals('RTP v2'));

      // Port 4321 with RTP v2 extension bit (0x90 & 0xC0 == 0x80)
      final rtp4321 = _buildRtpPacket(firstByte: 0x90, payloadType: 10, sequence: 7);
      final (proto4321, _) =
          FloodingScannerService.identifyProtocol(rtp4321, 4321);
      expect(proto4321, equals('Dante / RTP'));

      // Non-RTP port with 0x80 falls back to Unknown UDP
      final (protoOtherPort, _) =
          FloodingScannerService.identifyProtocol(rtp, 9999);
      expect(protoOtherPort, equals('Unknown UDP'));
    });

    test('falls back to Unknown UDP for unrecognized payloads', () {
      final unknown = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final (proto, detail) =
          FloodingScannerService.identifyProtocol(unknown, 5004);
      expect(proto, equals('Unknown UDP'));
      expect(detail, isNull);
    });
  });

  group('FloodingScannerService.isControlMulticastGroup Tests', () {
    test('returns true for IGMP, mDNS, and 224.0.0.x control groups', () {
      expect(FloodingScannerService.isControlMulticastGroup('224.0.0.1'), isTrue);
      expect(FloodingScannerService.isControlMulticastGroup('224.0.0.2'), isTrue);
      expect(FloodingScannerService.isControlMulticastGroup('224.0.0.22'), isTrue);
      expect(FloodingScannerService.isControlMulticastGroup('224.0.0.251'), isTrue);
      expect(FloodingScannerService.isControlMulticastGroup('224.0.0.13'), isTrue);
    });

    test('returns false for data multicast groups, PTP, unicast, and invalid strings', () {
      expect(FloodingScannerService.isControlMulticastGroup('239.255.0.1'), isFalse);
      expect(FloodingScannerService.isControlMulticastGroup('239.69.1.1'), isFalse);
      expect(FloodingScannerService.isControlMulticastGroup('239.1.1.1'), isFalse);
      expect(FloodingScannerService.isControlMulticastGroup('224.0.1.129'), isFalse);
      expect(FloodingScannerService.isControlMulticastGroup('192.168.1.10'), isFalse);
      expect(FloodingScannerService.isControlMulticastGroup('not-an-ip'), isFalse);
    });
  });

  group('FloodingScannerService Aggregation, Filtering & Lifecycle Tests', () {
    late FloodingScannerService scanner;

    setUp(() {
      scanner = FloodingScannerService();
    });

    tearDown(() {
      scanner.dispose();
    });

    test('processDatagramForTesting aggregates packet counts, bytes, bitrate, and source IP', () {
      final t0 = DateTime(2026, 11, 15, 12, 0, 0);
      final t1 = DateTime(2026, 11, 15, 12, 0, 2);
      final sacnPayload = _buildSacnPacket(universe: 12, length: 638);
      final senderAddr = InternetAddress('10.201.100.101');

      scanner.processDatagramForTesting(
        Datagram(sacnPayload, senderAddr, 5568),
        5568,
        timestamp: t0,
      );
      scanner.processDatagramForTesting(
        Datagram(sacnPayload, senderAddr, 5568),
        5568,
        timestamp: t1,
      );

      expect(scanner.entries.length, equals(1));
      final entry = scanner.entries.first;
      expect(entry.groupIp, equals('239.255.0.12'));
      expect(entry.destinationPort, equals(5568));
      expect(entry.sourceIp, equals('10.201.100.101'));
      expect(entry.detectedProtocol, equals('sACN'));
      expect(entry.protocolDetail, equals('Univ 12'));
      expect(entry.packetCount, equals(2));
      expect(entry.bytesReceived, equals(1276));
      expect(entry.firstSeen, equals(t0));
      expect(entry.lastSeen, equals(t1));
      // 1276 bytes * 8 bits / 2 seconds = 5104 bps
      expect(entry.estimatedBitrateBps, closeTo(5104.0, 0.01));

      // Distinct source IP creates a second entry
      scanner.processDatagramForTesting(
        Datagram(sacnPayload, InternetAddress('10.201.100.102'), 5568),
        5568,
        timestamp: t1,
      );
      expect(scanner.entries.length, equals(2));
      expect(scanner.totalPacketsSeen, equals(3));
    });

    test('ignores control multicast groups and already-joined groups, and resets on clear()', () {
      scanner.configureFiltersForTesting(
        alreadyJoinedGroups: {'239.255.0.5', '239.69.1.1:5004'},
      );

      // Control groups (should be ignored)
      for (final ctrlIp in ['224.0.0.1', '224.0.0.22', '224.0.0.251']) {
        scanner.processDatagramForTesting(
          Datagram(Uint8List.fromList([0x80, 96, 0, 1]), InternetAddress('192.168.1.254'), 5353),
          5004,
          destinationGroup: ctrlIp,
        );
      }
      expect(scanner.ignoredControlPacketCount, equals(3));
      expect(scanner.entries, isEmpty);

      // Already-joined group by IP
      final joinedIgmpTest = MulticastPacket(
        sessionId: 'joined_1',
        sequenceNumber: 1,
        sendTimestampUs: 1000,
        payloadSize: 64,
        destinationGroup: '239.255.0.5',
        destinationPort: 4321,
      ).encode();
      scanner.processDatagramForTesting(
        Datagram(joinedIgmpTest, InternetAddress('192.168.1.50'), 40000),
        4321,
      );

      // Already-joined group by group:port
      scanner.processDatagramForTesting(
        Datagram(_buildRtpPacket(), InternetAddress('192.168.1.51'), 5004),
        5004,
        destinationGroup: '239.69.1.1',
      );
      expect(scanner.ignoredJoinedPacketCount, equals(2));
      expect(scanner.entries, isEmpty);

      // Unjoined flooded group (should be recorded)
      scanner.processDatagramForTesting(
        Datagram(_buildRtpPacket(), InternetAddress('192.168.1.99'), 5004),
        5004,
        destinationGroup: '239.69.2.99',
      );
      expect(scanner.entries.length, equals(1));
      expect(scanner.entries.first.groupIp, equals('239.69.2.99'));
      expect(scanner.entries.first.detectedProtocol, equals('Dante / RTP'));

      // clear() resets everything cleanly
      scanner.clear();
      expect(scanner.entries, isEmpty);
      expect(scanner.ignoredControlPacketCount, equals(0));
      expect(scanner.ignoredJoinedPacketCount, equals(0));
      expect(scanner.hasCompletedScan, isFalse);
      expect(scanner.totalPacketsSeen, equals(0));
    });

    test('startScan handles SocketException per port gracefully without crashing', () async {
      final failingScanner = FloodingScannerService(
        socketBinder: (port) async {
          if (port == 5568) {
            throw const SocketException('Address already in use');
          }
          // Bind a real ephemeral UDP socket for the remaining port (no joinMulticast)
          return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
        },
      );

      await failingScanner.startScan(
        ports: [5568, 6454],
        duration: const Duration(seconds: 5),
      );

      expect(failingScanner.portErrors[5568], contains('Address already in use'));
      expect(failingScanner.boundPorts, equals([6454]));
      expect(failingScanner.isScanning, isTrue);

      await failingScanner.stopScan();
      expect(failingScanner.isScanning, isFalse);
      expect(failingScanner.boundPorts, isEmpty);
      expect(failingScanner.hasCompletedScan, isTrue);

      failingScanner.dispose();
    });

    test('startScan completes immediately with errors when all ports fail to bind', () async {
      final failingScanner = FloodingScannerService(
        socketBinder: (port) async {
          throw const SocketException('Permission denied');
        },
      );

      await failingScanner.startScan(ports: [5568, 6454]);

      expect(failingScanner.isScanning, isFalse);
      expect(failingScanner.hasCompletedScan, isTrue);
      expect(failingScanner.boundPorts, isEmpty);
      expect(failingScanner.portErrors.keys, containsAll([5568, 6454]));

      failingScanner.dispose();
    });

    test('startScan binds live ephemeral UDP socket without IGMP join and receives datagrams', () async {
      // Reserve a free ephemeral port cleanly, close it, then pass it to startScan.
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final freePort = probe.port;
      probe.close();

      await scanner.startScan(
        ports: [freePort],
        duration: const Duration(seconds: 5),
      );

      expect(scanner.isScanning, isTrue);
      expect(scanner.boundPorts, equals([freePort]));

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final testPacket = MulticastPacket(
        sessionId: 'loopback_scan',
        sequenceNumber: 1,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: '239.255.88.1',
        destinationPort: freePort,
      ).encode();
      sender.send(testPacket, InternetAddress.loopbackIPv4, freePort);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      sender.close();
      await scanner.stopScan();

      expect(scanner.isScanning, isFalse);
      expect(scanner.hasCompletedScan, isTrue);
      expect(scanner.entries.length, equals(1));
      expect(scanner.entries.first.groupIp, equals('239.255.88.1'));
      expect(scanner.entries.first.destinationPort, equals(freePort));
      expect(scanner.entries.first.detectedProtocol, equals('IGMP Tester'));
    });
  });

  group('FloodedStreamsSheet Widget Tests', () {
    testWidgets('shows monitored ports and Green Clean Port Banner after clean scan', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scanner = FloodingScannerService();
      addTearDown(scanner.dispose);

      scanner.markScanCompletedForTesting(
        ports: FloodingScannerService.defaultPorts,
        duration: const Duration(seconds: 5),
        elapsed: const Duration(seconds: 5),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: FloodedStreamsSheet(scannerService: scanner),
          ),
        ),
      );

      expect(find.textContaining('5568, 6454, 4321, 5004'), findsOneWidget);
      expect(
        find.text(
          'No unjoined multicast flooding detected — IGMP snooping appears active on this port',
        ),
        findsOneWidget,
      );
      expect(find.text('Rescan'), findsOneWidget);
    });

    testWidgets('shows Flooding Alert Banner, stream row details, and invokes Adopt & Track', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scanner = FloodingScannerService();
      addTearDown(scanner.dispose);

      final t0 = DateTime(2026, 11, 15, 14, 0, 0);
      final t1 = DateTime(2026, 11, 15, 14, 0, 1);
      final sacnPayload = _buildSacnPacket(universe: 1, length: 638);
      scanner.processDatagramForTesting(
        Datagram(sacnPayload, InternetAddress('10.201.100.50'), 5568),
        5568,
        timestamp: t0,
      );
      scanner.processDatagramForTesting(
        Datagram(sacnPayload, InternetAddress('10.201.100.50'), 5568),
        5568,
        timestamp: t1,
      );

      FloodedStreamEntry? adoptedEntry;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: FloodedStreamsSheet(
              scannerService: scanner,
              onAdoptStream: (entry) => adoptedEntry = entry,
            ),
          ),
        ),
      );

      expect(
        find.text('Unregistered Multicast Flooding Detected (1 Stream)'),
        findsOneWidget,
      );
      expect(find.text('239.255.0.1'), findsOneWidget);
      expect(find.text('5568'), findsOneWidget);
      expect(find.text('sACN Univ 1'), findsOneWidget);
      expect(find.text('10.201.100.50'), findsOneWidget);
      expect(find.text('2 pkts'), findsOneWidget);
      expect(find.text('Adopt & Track'), findsOneWidget);

      await tester.tap(find.text('Adopt & Track'));
      await tester.pump();

      expect(adoptedEntry, isNotNull);
      expect(adoptedEntry!.groupIp, equals('239.255.0.1'));
      expect(adoptedEntry!.destinationPort, equals(5568));
      expect(adoptedEntry!.detectedProtocol, equals('sACN'));
    });

    testWidgets('renders cleanly inside showDialog without layout overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scanner = FloodingScannerService();
      addTearDown(scanner.dispose);

      scanner.processDatagramForTesting(
        Datagram(_buildArtNetPacket(universe: 3), InternetAddress('192.168.1.44'), 6454),
        6454,
        destinationGroup: '239.255.0.3',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  FloodedStreamsSheet.showDialogModal(
                    ctx,
                    scannerService: scanner,
                    autoStart: false,
                  );
                },
                child: const Text('Open Scanner'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      expect(find.text('Unjoined Multicast Flooding Scanner'), findsOneWidget);
      expect(find.text('Art-Net Univ 3'), findsOneWidget);
      expect(find.text('239.255.0.3'), findsOneWidget);
    });

    testWidgets('renders compact card layout cleanly inside showModalBottomSheet on narrow viewport', (tester) async {
      tester.view.physicalSize = const Size(520, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final scanner = FloodingScannerService();
      addTearDown(scanner.dispose);

      scanner.processDatagramForTesting(
        Datagram(_buildRtpPacket(payloadType: 96, sequence: 10), InternetAddress('10.1.2.3'), 5004),
        5004,
        destinationGroup: '239.69.1.5',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  FloodedStreamsSheet.showBottomSheetModal(
                    ctx,
                    scannerService: scanner,
                    autoStart: false,
                  );
                },
                child: const Text('Open Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Bottom Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('239.69.1.5:5004'), findsOneWidget);
      expect(find.textContaining('Dante / RTP'), findsOneWidget);
      expect(find.text('Adopt & Track'), findsOneWidget);
    });
  });
}
