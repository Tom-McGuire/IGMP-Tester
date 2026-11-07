import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/multicast/multicast_sender_service.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';

void main() {
  group('MulticastSenderService Tests', () {
    late MulticastSenderService senderService;

    setUp(() {
      senderService = MulticastSenderService();
    });

    tearDown(() async {
      await senderService.stop();
      senderService.dispose();
    });

    test('initial state has no running streams and zero stats', () {
      expect(senderService.isRunning, isFalse);
      expect(senderService.isStreamRunning('test_stream'), isFalse);
      expect(senderService.currentStats.packetsSent, equals(0));
      expect(senderService.currentStreamStats, isEmpty);
    });

    test('startStream starts a multicast stream and sends packets', () async {
      const stream = MulticastStreamConfig(
        id: 'test_tx_1',
        name: 'Tx Stream 1',
        groupAddress: '239.255.0.1',
        port: 5004,
        packetsPerSecond: 50,
        packetSizeBytes: 256,
        ttl: 1,
      );

      await senderService.startStream(
        streamConfig: stream,
        enableLoopback: true,
      );

      expect(senderService.isRunning, isTrue);
      expect(senderService.isStreamRunning('test_tx_1'), isTrue);

      // Wait 600ms for periodic send timer (10ms) and aggregate stats timer (500ms) to update
      await Future.delayed(const Duration(milliseconds: 600));

      final stats = senderService.currentStats;
      expect(stats.activeStreamsCount, equals(1));
      expect(stats.packetsSent, greaterThan(0));
      expect(stats.bytesSent, greaterThan(0));

      await senderService.stopStream('test_tx_1');
      expect(senderService.isStreamRunning('test_tx_1'), isFalse);
      expect(senderService.isRunning, isFalse);
    });

    test('startAll starts all enabled streams and stop halts everything', () async {
      const config = MulticastSenderConfig(
        enableLoopback: true,
        streams: [
          MulticastStreamConfig(
            id: 'stream_a',
            name: 'Stream A',
            groupAddress: '239.255.0.10',
            port: 5004,
            packetsPerSecond: 20,
            enabled: true,
          ),
          MulticastStreamConfig(
            id: 'stream_b',
            name: 'Stream B',
            groupAddress: '239.255.0.11',
            port: 5005,
            packetsPerSecond: 20,
            enabled: true,
          ),
          MulticastStreamConfig(
            id: 'stream_c',
            name: 'Stream C',
            groupAddress: '239.255.0.12',
            port: 5006,
            packetsPerSecond: 20,
            enabled: false, // Disabled
          ),
        ],
      );

      await senderService.startAll(config: config);

      expect(senderService.isStreamRunning('stream_a'), isTrue);
      expect(senderService.isStreamRunning('stream_b'), isTrue);
      expect(senderService.isStreamRunning('stream_c'), isFalse);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(senderService.currentStats.activeStreamsCount, equals(2));

      await senderService.stop();
      expect(senderService.isRunning, isFalse);
      expect(senderService.isStreamRunning('stream_a'), isFalse);
      expect(senderService.isStreamRunning('stream_b'), isFalse);
    });
  });
}
