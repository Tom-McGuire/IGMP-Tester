import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/multicast/multicast_sender_service.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';

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

    test('startStream records configured DSCP preset in SenderStats and encodes DSCP hint in packets', () async {
      final rxSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      final completer = Completer<MulticastPacket>();
      try {
        rxSocket.multicastLoopback = true;
        rxSocket.joinMulticast(InternetAddress('239.255.44.55'));
        rxSocket.listen((event) {
          if (event == RawSocketEvent.read && !completer.isCompleted) {
            final d = rxSocket.receive();
            if (d != null) {
              final decoded = MulticastPacket.decode(d.data);
              if (decoded != null) completer.complete(decoded);
            }
          }
        });

        final stream = MulticastStreamConfig(
          id: 'tx_dscp_ef',
          name: 'Dante EF Stream',
          groupAddress: '239.255.44.55',
          port: rxSocket.port,
          packetsPerSecond: 50,
          packetSizeBytes: 128,
          ttl: 1,
          dscpPreset: DscpPreset.ef,
        );

        await senderService.startStream(
          streamConfig: stream,
          enableLoopback: true,
        );

        expect(senderService.currentStats.dscpPreset, equals(DscpPreset.ef));
        expect(senderService.currentStreamStats['tx_dscp_ef']?.dscpPreset, equals(DscpPreset.ef));

        final received = await completer.future.timeout(const Duration(seconds: 2));
        expect(received.encodedDscp, equals(DscpPreset.ef.dscpValue));
        expect(received.encodedDscpPreset, equals(DscpPreset.ef));
      } finally {
        rxSocket.close();
      }
    });

    test('computePacketsDue produces exact packet totals over 1.0s at 10ms steps', () {
      for (final targetPps in [44, 60, 128, 1000]) {
        var sent = 0;
        for (var tick = 1; tick <= 100; tick++) {
          final elapsedUs = tick * 10000;
          final due = MulticastSenderService.computePacketsDue(
            elapsedUs: elapsedUs,
            pps: targetPps,
            alreadySent: sent,
          );
          expect(due, greaterThanOrEqualTo(0));
          expect(due, lessThanOrEqualTo(64));
          sent += due;
        }
        expect(
          sent,
          equals(targetPps),
          reason: 'Expected exact total $targetPps packets over 1.0s at 10ms steps',
        );
      }

      // Edge-case guards
      expect(
        MulticastSenderService.computePacketsDue(
          elapsedUs: -1,
          pps: 50,
          alreadySent: 0,
        ),
        equals(0),
      );
      expect(
        MulticastSenderService.computePacketsDue(
          elapsedUs: 100000,
          pps: 0,
          alreadySent: 0,
        ),
        equals(0),
      );
      expect(
        MulticastSenderService.computePacketsDue(
          elapsedUs: 5000000,
          pps: 1000,
          alreadySent: 0,
          maxBurstPerTick: 64,
        ),
        equals(64),
      );
    });

    test('buildMulticastIfOption encodes IPPROTO_IP and OS-specific IP_MULTICAST_IF', () {
      final ipv4 = InternetAddress('192.168.10.25');
      final expectedBytes = Uint8List.fromList([192, 168, 10, 25]);

      final linuxOpt = MulticastSenderService.buildMulticastIfOption(
        ipv4,
        operatingSystemOverride: 'linux',
      );
      expect(linuxOpt, isNotNull);
      expect(linuxOpt!.level, equals(RawSocketOption.levelIPv4));
      expect(linuxOpt.level, equals(0));
      expect(linuxOpt.option, equals(32));
      expect(linuxOpt.value, equals(expectedBytes));

      final macosOpt = MulticastSenderService.buildMulticastIfOption(
        ipv4,
        operatingSystemOverride: 'macos',
      );
      expect(macosOpt, isNotNull);
      expect(macosOpt!.level, equals(RawSocketOption.levelIPv4));
      expect(macosOpt.option, equals(32));
      expect(macosOpt.value, equals(expectedBytes));

      final windowsOpt = MulticastSenderService.buildMulticastIfOption(
        ipv4,
        operatingSystemOverride: 'windows',
      );
      expect(windowsOpt, isNotNull);
      expect(windowsOpt!.level, equals(RawSocketOption.levelIPv4));
      expect(windowsOpt.option, equals(9));
      expect(windowsOpt.value, equals(expectedBytes));

      // IPv6 / non-IPv4 must return null
      expect(
        MulticastSenderService.buildMulticastIfOption(
          InternetAddress('::1'),
          operatingSystemOverride: 'linux',
        ),
        isNull,
      );
      expect(
        MulticastSenderService.buildMulticastIfOption(
          InternetAddress('fe80::1'),
          operatingSystemOverride: 'windows',
        ),
        isNull,
      );
    });

    test('buildMulticastIfOption applies cleanly to live loopback RawDatagramSocket', () async {
      final loopback = InternetAddress.loopbackIPv4;
      final socket = await RawDatagramSocket.bind(loopback, 0);
      try {
        final opt = MulticastSenderService.buildMulticastIfOption(loopback);
        expect(opt, isNotNull);
        socket.setRawOption(opt!);
        if (Platform.isLinux) {
          final probe = RawSocketOption(
            RawSocketOption.levelIPv4,
            opt.option,
            Uint8List(4),
          );
          final actual = socket.getRawOption(probe);
          expect(actual, equals(Uint8List.fromList([127, 0, 0, 1])));
        }
      } finally {
        socket.close();
      }
    });

    Future<void> verifyLivePacing({
      required int targetPps,
      required String groupAddress,
    }) async {
      final interfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );
      NetworkInterface? loopbackIface;
      for (final iface in interfaces) {
        if (iface.addresses.any((a) => a.address == '127.0.0.1')) {
          loopbackIface = iface;
          break;
        }
      }

      final rxSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      final receivedPackets = <MulticastPacket>[];
      try {
        rxSocket.multicastLoopback = true;
        final group = InternetAddress(groupAddress);
        if (loopbackIface != null) {
          rxSocket.joinMulticast(group, loopbackIface);
        } else {
          rxSocket.joinMulticast(group);
        }
        rxSocket.listen((event) {
          if (event == RawSocketEvent.read) {
            while (true) {
              final d = rxSocket.receive();
              if (d == null) break;
              final decoded = MulticastPacket.decode(d.data);
              if (decoded != null && decoded.destinationGroup == groupAddress) {
                receivedPackets.add(decoded);
              }
            }
          }
        });

        final stream = MulticastStreamConfig(
          id: 'pacing_$targetPps',
          name: 'Pacing $targetPps pps',
          groupAddress: groupAddress,
          port: rxSocket.port,
          packetsPerSecond: targetPps,
          packetSizeBytes: 128,
          ttl: 1,
        );

        final stopwatch = Stopwatch()..start();
        await senderService.startStream(
          streamConfig: stream,
          rawInterface: loopbackIface,
          enableLoopback: true,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await senderService.stopStream(stream.id);
        stopwatch.stop();

        // Allow any already-queued loopback datagrams to drain
        await Future.delayed(const Duration(milliseconds: 25));

        final elapsedSec = stopwatch.elapsedMicroseconds / 1000000.0;
        final actualRate = receivedPackets.length / elapsedSec;

        expect(
          receivedPackets.length,
          greaterThan(0),
          reason: 'Expected packets at $targetPps pps',
        );
        expect(
          actualRate,
          inInclusiveRange(targetPps * 0.80, targetPps * 1.20),
          reason:
              'Observed rate ${actualRate.toStringAsFixed(1)} pps '
              '(${receivedPackets.length} pkts in ${(elapsedSec * 1000).toStringAsFixed(1)} ms) '
              'should track $targetPps pps',
        );

        // Verify strictly increasing per-packet sendTimestampUs across bursts
        for (var i = 1; i < receivedPackets.length; i++) {
          expect(
            receivedPackets[i].sendTimestampUs,
            greaterThan(receivedPackets[i - 1].sendTimestampUs),
            reason:
                'Packet $i timestamp (${receivedPackets[i].sendTimestampUs}) '
                'must strictly exceed previous (${receivedPackets[i - 1].sendTimestampUs})',
          );
        }
      } finally {
        rxSocket.close();
      }
    }

    test('live loopback pacing accuracy at 44 pps (sACN)', () async {
      await verifyLivePacing(targetPps: 44, groupAddress: '239.255.144.44');
    });

    test('live loopback pacing accuracy at 60 pps (non-divisor of 100)', () async {
      await verifyLivePacing(targetPps: 60, groupAddress: '239.255.144.60');
    });

    test('live loopback pacing accuracy at 128 pps (PTP)', () async {
      await verifyLivePacing(targetPps: 128, groupAddress: '239.255.144.128');
    });
  });
}
