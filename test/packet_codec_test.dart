import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';

void main() {
  group('MulticastPacket Codec Tests', () {
    test('encode and decode matches original data with destination group and port', () {
      final original = MulticastPacket(
        version: 1,
        flags: 0,
        sessionId: 'test-session-123',
        sequenceNumber: 4242,
        sendTimestampUs: 1729724400000000,
        configuredIntervalUs: 20000,
        payloadSize: 128,
        destinationGroup: '239.255.10.20',
        destinationPort: 5005,
      );

      final bytes = original.encode();
      expect(bytes.length, equals(128));

      final decoded = MulticastPacket.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.version, equals(1));
      expect(decoded.flags, equals(0));
      expect(decoded.sessionId, equals('test-session-123'));
      expect(decoded.sequenceNumber, equals(4242));
      expect(decoded.sendTimestampUs, equals(1729724400000000));
      expect(decoded.configuredIntervalUs, equals(20000));
      expect(decoded.payloadSize, equals(128));
      expect(decoded.destinationGroup, equals('239.255.10.20'));
      expect(decoded.destinationPort, equals(5005));
    });

    test('enforces minimum header size of 56 bytes', () {
      final packet = MulticastPacket(
        sessionId: 'short',
        sequenceNumber: 1,
        sendTimestampUs: 100,
        payloadSize: 20, // smaller than minHeaderSize 56
        destinationGroup: '239.1.2.3',
        destinationPort: 5004,
      );

      final bytes = packet.encode();
      expect(bytes.length, equals(56));

      final decoded = MulticastPacket.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.sequenceNumber, equals(1));
      expect(decoded.destinationGroup, equals('239.1.2.3'));
      expect(decoded.destinationPort, equals(5004));
    });

    test('updateSequenceAndTimestamp modifies buffer in-place accurately', () {
      final packet = MulticastPacket(
        sessionId: 'fast-update',
        sequenceNumber: 1,
        sendTimestampUs: 1000,
        payloadSize: 64,
        destinationGroup: '239.255.0.1',
        destinationPort: 5004,
      );

      final buffer = packet.encode();
      MulticastPacket.updateSequenceAndTimestamp(buffer, 9999, 5000000);

      final decoded = MulticastPacket.decode(buffer);
      expect(decoded, isNotNull);
      expect(decoded!.sequenceNumber, equals(9999));
      expect(decoded.sendTimestampUs, equals(5000000));
      expect(decoded.sessionId, equals('fast-update'));
      expect(decoded.destinationGroup, equals('239.255.0.1'));
    });

    test('sanitizes session ID to strip non-alphanumeric chars', () {
      final sanitized = MulticastPacket.sanitizeSessionId('sess=1+2;drop-table!');
      expect(sanitized, equals('sess12drop-table'));
    });

    test('rejects packet with invalid magic header', () {
      final data = Uint8List(60);
      data.setRange(0, 8, [1, 2, 3, 4, 5, 6, 7, 8]); // Not 'IGMPTEST'

      final decoded = MulticastPacket.decode(data);
      expect(decoded, isNull);
    });

    test('rejects packet smaller than minHeaderSize (56 bytes)', () {
      final data = Uint8List(55);
      final decoded = MulticastPacket.decode(data);
      expect(decoded, isNull);
    });
  });
}
