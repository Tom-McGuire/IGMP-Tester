import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';

void main() {
  group('MulticastPacket Codec Tests', () {
    test('encode and decode matches original data', () {
      final original = MulticastPacket(
        version: 1,
        flags: 0,
        sessionId: 'test-session-123',
        sequenceNumber: 4242,
        sendTimestampUs: 1729724400000000,
        configuredIntervalUs: 20000,
        payloadSize: 128,
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
    });

    test('enforces minimum header size of 50 bytes', () {
      final packet = MulticastPacket(
        sessionId: 'short',
        sequenceNumber: 1,
        sendTimestampUs: 100,
        payloadSize: 20, // smaller than minHeaderSize 50
      );

      final bytes = packet.encode();
      expect(bytes.length, equals(50));

      final decoded = MulticastPacket.decode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.sequenceNumber, equals(1));
    });

    test('rejects packet with invalid magic header', () {
      final data = Uint8List(60);
      data.setRange(0, 8, [1, 2, 3, 4, 5, 6, 7, 8]); // Not 'IGMPTEST'

      final decoded = MulticastPacket.decode(data);
      expect(decoded, isNull);
    });

    test('rejects packet smaller than minHeaderSize', () {
      final data = Uint8List(30);
      final decoded = MulticastPacket.decode(data);
      expect(decoded, isNull);
    });
  });
}
