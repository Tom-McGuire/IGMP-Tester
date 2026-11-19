import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:igmp_tester/domain/models/multicast_packet.dart';
import 'package:igmp_tester/domain/models/multicast_stats.dart';
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

    test('drops datagrams for unsubscribed multicast groups on shared port and records them as unsubscribed traffic', () {
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
      expect(receiverService.unsubscribedStreams.length, equals(1));
      expect(receiverService.unsubscribedStreams.first.groupAddress, equals('239.255.99.99'));
      expect(receiverService.unsubscribedStreams.first.port, equals(5004));
      expect(receiverService.unsubscribedStreams.first.packetsReceived, equals(1));
      expect(receiverService.currentStats.unsubscribedStreamsCount, equals(1));
      expect(receiverService.currentStats.unsubscribedPacketsReceived, equals(1));

      receiverService.clearUnsubscribedStreams();
      expect(receiverService.unsubscribedStreams, isEmpty);
      expect(receiverService.currentStats.unsubscribedStreamsCount, equals(0));
    });

    test('passive no-join stream records arriving packets as unsubscribed flood traffic', () {
      final passiveStream = const MulticastReceiverStreamConfig(
        id: 'rx_passive',
        name: 'Passive Group',
        groupAddress: '239.255.0.50',
        port: 5004,
        joinGroup: false,
      );
      receiverService.addStreamForTesting(passiveStream);

      expect(receiverService.isStreamJoined('rx_passive'), isFalse);

      final floodedDatagram = createDatagram(
        destinationGroup: '239.255.0.50',
        destinationPort: 5004,
        sessionId: 'flood_sess',
        seq: 1,
      );
      receiverService.processDatagramForTesting(floodedDatagram, 5004);
      receiverService.recalculateStatsForTesting();

      // Tracked both in the stream row and in the unsubscribed flood list
      expect(receiverService.currentStreamStats['rx_passive']?.packetsReceived, equals(1));
      expect(receiverService.unsubscribedStreams.length, equals(1));
      expect(receiverService.unsubscribedStreams.first.groupAddress, equals('239.255.0.50'));
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

  group('Issue #4, #5, #7 Receiver Integration Tests', () {
    Datagram buildDatagram({
      required String groupIp,
      required int port,
      required String sourceIp,
      required String sessionId,
      required int seq,
      int? dscpValue,
    }) {
      final packet = MulticastPacket(
        sessionId: sessionId,
        sequenceNumber: seq,
        sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
        payloadSize: 64,
        destinationGroup: groupIp,
        destinationPort: port,
        dscpValue: dscpValue,
      );
      return Datagram(packet.encode(), InternetAddress(sourceIp), 40000);
    }

    test('Fast-Leave reports 0ms Fast-Leave Active after silence window with zero trailing packets', () async {
      DateTime fakeNow = DateTime(2026, 3, 1, 12, 0, 0);
      final service = MulticastReceiverService(clock: () => fakeNow);
      addTearDown(service.dispose);

      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_fl_0',
          name: 'FastLeave 0',
          groupAddress: '239.255.1.1',
          port: 5004,
        ),
      );

      // Simulate active pre-leave traffic so Fast-Leave measurement is valid.
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.1.1',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'fl0',
          seq: 1,
        ),
        5004,
        timestamp: fakeNow,
      );

      final result = await service.leaveStreamWithMeasurement(
        'rx_fl_0',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 25),
      );

      expect(result, isNotNull);
      expect(result!.leaveLatencyMs, equals(0));
      expect(result.trailingPacketsReceived, equals(0));
      expect(result.status, equals(FastLeaveStatus.fastLeaveActive));
      expect(result.aborted, isFalse);
      expect(service.isMeasuringLeave, isFalse);
      expect(service.lastLeaveLatency?.status, equals(FastLeaveStatus.fastLeaveActive));
    });

    test('Fast-Leave returns inconclusive on idle streams and stale streams (>5s without prior packets)', () async {
      final t0 = DateTime(2026, 3, 1, 12, 0, 0);
      DateTime fakeNow = t0;
      final service = MulticastReceiverService(clock: () => fakeNow);
      addTearDown(service.dispose);

      // 1) Idle stream with 0 prior packets and 0 trailing packets
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_idle',
          name: 'Idle Stream',
          groupAddress: '239.255.1.10',
          port: 5004,
        ),
      );

      final idleResult = await service.leaveStreamWithMeasurement(
        'rx_idle',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 25),
      );
      expect(idleResult, isNotNull);
      expect(idleResult!.leaveLatencyMs, equals(0));
      expect(idleResult.trailingPacketsReceived, equals(0));
      expect(idleResult.status, equals(FastLeaveStatus.inconclusive));
      expect(idleResult.aborted, isFalse);

      // 2) Stale stream: last packet > 5 seconds before leave, 0 trailing packets
      fakeNow = t0;
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_stale',
          name: 'Stale Stream',
          groupAddress: '239.255.1.11',
          port: 5004,
        ),
      );
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.1.11',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'stale_sess',
          seq: 1,
        ),
        5004,
        timestamp: t0,
      );
      fakeNow = t0.add(const Duration(seconds: 6));

      final staleResult = await service.leaveStreamWithMeasurement(
        'rx_stale',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 25),
      );
      expect(staleResult, isNotNull);
      expect(staleResult!.leaveLatencyMs, equals(0));
      expect(staleResult.trailingPacketsReceived, equals(0));
      expect(staleResult.status, equals(FastLeaveStatus.inconclusive));

      // 3) Boundary: last packet exactly 5s before leave still counts as active
      fakeNow = t0;
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_fresh_edge',
          name: 'Fresh Edge Stream',
          groupAddress: '239.255.1.12',
          port: 5004,
        ),
      );
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.1.12',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'edge_sess',
          seq: 1,
        ),
        5004,
        timestamp: t0,
      );
      fakeNow = t0.add(MulticastReceiverService.defaultPriorTrafficFreshness);

      final edgeResult = await service.leaveStreamWithMeasurement(
        'rx_fresh_edge',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 25),
      );
      expect(edgeResult, isNotNull);
      expect(edgeResult!.status, equals(FastLeaveStatus.fastLeaveActive));
    });

    test('Fast-Leave classifies 0-50ms, 51-500ms, and >500ms trailing packets and excludes them from flooding', () async {
      final t0 = DateTime(2026, 3, 1, 12, 0, 0);
      DateTime fakeNow = t0;
      final service = MulticastReceiverService(clock: () => fakeNow);
      addTearDown(service.dispose);

      // 1) 25 ms -> Fast-Leave Active
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_fast',
          name: 'Fast',
          groupAddress: '239.255.1.2',
          port: 5004,
        ),
      );
      final fastFuture = service.leaveStreamWithMeasurement(
        'rx_fast',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 30),
      );
      expect(service.isStreamMeasuringLeave('rx_fast'), isTrue);
      service.processDatagramForTesting(
        buildDatagram(groupIp: '239.255.1.2', port: 5004, sourceIp: '10.0.0.1', sessionId: 'fl1', seq: 10),
        5004,
        timestamp: t0.add(const Duration(milliseconds: 15)),
      );
      service.processDatagramForTesting(
        buildDatagram(groupIp: '239.255.1.2', port: 5004, sourceIp: '10.0.0.1', sessionId: 'fl1', seq: 11),
        5004,
        timestamp: t0.add(const Duration(milliseconds: 25)),
      );
      fakeNow = t0.add(const Duration(milliseconds: 55));
      final fastResult = await fastFuture;
      expect(fastResult!.leaveLatencyMs, equals(25));
      expect(fastResult.trailingPacketsReceived, equals(2));
      expect(fastResult.status, equals(FastLeaveStatus.fastLeaveActive));
      expect(service.unsubscribedStreams, isEmpty);

      // 2) 240 ms -> Delayed Prune
      fakeNow = t0;
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_delay',
          name: 'Delayed',
          groupAddress: '239.255.1.3',
          port: 5004,
        ),
      );
      final delayFuture = service.leaveStreamWithMeasurement(
        'rx_delay',
        maxDrainDuration: const Duration(milliseconds: 500),
        silenceTimeout: const Duration(milliseconds: 30),
      );
      service.processDatagramForTesting(
        buildDatagram(groupIp: '239.255.1.3', port: 5004, sourceIp: '10.0.0.1', sessionId: 'fl2', seq: 1),
        5004,
        timestamp: t0.add(const Duration(milliseconds: 240)),
      );
      final delayResult = await delayFuture;
      expect(delayResult!.leaveLatencyMs, equals(240));
      expect(delayResult.status, equals(FastLeaveStatus.delayedPrune));

      // 3) 800 ms -> No Fast-Leave (hit maxDrainTimer cap)
      fakeNow = t0;
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_slow',
          name: 'Slow',
          groupAddress: '239.255.1.4',
          port: 5004,
        ),
      );
      final slowFuture = service.leaveStreamWithMeasurement(
        'rx_slow',
        maxDrainDuration: const Duration(milliseconds: 45),
        silenceTimeout: const Duration(milliseconds: 40),
      );
      service.processDatagramForTesting(
        buildDatagram(groupIp: '239.255.1.4', port: 5004, sourceIp: '10.0.0.1', sessionId: 'fl3', seq: 1),
        5004,
        timestamp: t0.add(const Duration(milliseconds: 800)),
      );
      final slowResult = await slowFuture;
      expect(slowResult!.leaveLatencyMs, equals(800));
      expect(slowResult.status, equals(FastLeaveStatus.noFastLeave));
    });

    test('Fast-Leave abortLeaveMeasurement ends drain immediately with aborted status', () async {
      final service = MulticastReceiverService();
      addTearDown(service.dispose);

      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_abort',
          name: 'Abort Test',
          groupAddress: '239.255.1.5',
          port: 5004,
        ),
      );

      final drainFuture = service.leaveStreamWithMeasurement(
        'rx_abort',
        maxDrainDuration: const Duration(seconds: 3),
        silenceTimeout: const Duration(milliseconds: 500),
      );
      expect(service.isMeasuringLeave, isTrue);
      expect(service.lastLeaveLatency?.status, equals(FastLeaveStatus.measuring));

      service.abortLeaveMeasurement('rx_abort');
      final abortedResult = await drainFuture;

      expect(abortedResult!.aborted, isTrue);
      expect(abortedResult.status, equals(FastLeaveStatus.aborted));
      expect(service.isMeasuringLeave, isFalse);
    });

    test('SSM (S, G) filters datagrams by sourceFilterIp cleanly without polluting unsubscribed list', () async {
      final service = MulticastReceiverService();
      addTearDown(service.dispose);

      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_ssm_only',
          name: 'SSM Stream',
          groupAddress: '232.1.1.10',
          port: 5004,
          joinMode: IgmpJoinMode.ssm,
          sourceFilterIp: '10.0.0.10',
        ),
      );

      // Rejected unauthorized source
      service.processDatagramForTesting(
        buildDatagram(groupIp: '232.1.1.10', port: 5004, sourceIp: '10.0.0.99', sessionId: 'bad_src', seq: 1),
        5004,
      );
      // Accepted authorized source
      service.processDatagramForTesting(
        buildDatagram(groupIp: '232.1.1.10', port: 5004, sourceIp: '10.0.0.10', sessionId: 'good_src', seq: 1),
        5004,
      );
      service.recalculateStatsForTesting();

      expect(service.currentStreamStats['rx_ssm_only']?.packetsReceived, equals(1));
      expect(service.unsubscribedStreams, isEmpty);

      // Also verify live loopback SSM start/stop handles OS fallback safely
      final portProbe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final freePort = portProbe.port;
      portProbe.close();

      await service.startStream(
        streamConfig: MulticastReceiverStreamConfig(
          id: 'rx_ssm_live',
          name: 'SSM Live',
          groupAddress: '232.1.1.20',
          port: freePort,
          joinMode: IgmpJoinMode.ssm,
          sourceFilterIp: '127.0.0.1',
        ),
        enableLoopback: true,
      );
      expect(service.isStreamRunning('rx_ssm_live'), isTrue);
      await service.stopStream('rx_ssm_live');
      expect(service.isStreamRunning('rx_ssm_live'), isFalse);
    });

    test('DSCP transit verification handles preserved, remarkedToZero, remarkedOrStripped, and unverified OS TOS', () {
      final service = MulticastReceiverService();
      addTearDown(service.dispose);

      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_dscp',
          name: 'QoS Stream',
          groupAddress: '239.255.9.9',
          port: 5004,
          expectedDscp: DscpPreset.ef,
        ),
      );

      // 1) No OS TOS metadata -> remains unverified while packet hint is recorded
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.9',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'dscp1',
          seq: 1,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      expect(service.currentStreamStats['rx_dscp']?.dscpTransitStatus, equals(DscpTransitStatus.unverified));
      expect(service.currentStreamStats['rx_dscp']?.senderDscpPreset, equals(DscpPreset.ef));

      // 2) Preserved EF (TOS 0xB8 = 184)
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.9',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'dscp1',
          seq: 2,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
        receivedTosByte: DscpPreset.ef.tosByte,
      );
      service.recalculateStatsForTesting();
      expect(service.currentStreamStats['rx_dscp']?.dscpTransitStatus, equals(DscpTransitStatus.preserved));
      expect(service.currentStreamStats['rx_dscp']?.receivedDscp, equals(46));

      // 3) Stripped to Best Effort (0x00)
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.9',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'dscp1',
          seq: 3,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
        receivedTosByte: 0x00,
      );
      service.recalculateStatsForTesting();
      expect(service.currentStreamStats['rx_dscp']?.dscpTransitStatus, equals(DscpTransitStatus.remarkedToZero));
      expect(service.currentStats.dscpTransitStatus, equals(DscpTransitStatus.remarkedToZero));

      // 4) Remarked to CS3 (0x60 = 96)
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.9',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'dscp1',
          seq: 4,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
        receivedTosByte: DscpPreset.cs3.tosByte,
      );
      service.recalculateStatsForTesting();
      expect(service.currentStreamStats['rx_dscp']?.dscpTransitStatus, equals(DscpTransitStatus.remarkedOrStripped));
      expect(service.currentStreamStats['rx_dscp']?.receivedDscp, equals(24));
    });

    test('Priority 1.4: live DSCP sender tag mismatch surfaces alert without OS TOS and tracks dscpVerifiedByOsTos', () {
      final service = MulticastReceiverService();
      addTearDown(service.dispose);

      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_live_qos',
          name: 'Live QoS',
          groupAddress: '239.255.9.10',
          port: 5004,
          expectedDscp: DscpPreset.ef,
        ),
      );

      // 1) Matching hint EF (46) without OS TOS -> stays unverified, dscpVerifiedByOsTos == false
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 1,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      var sStats = service.currentStreamStats['rx_live_qos']!;
      expect(sStats.dscpTransitStatus, equals(DscpTransitStatus.unverified));
      expect(sStats.dscpVerifiedByOsTos, isFalse);
      expect(sStats.receivedDscp, isNull);
      expect(sStats.receivedTosByte, isNull);
      expect(service.currentStats.dscpVerifiedByOsTos, isFalse);

      // 2) Mismatched hint AF41 (34) without OS TOS -> remarkedOrStripped, dscpVerifiedByOsTos == false
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 2,
          dscpValue: DscpPreset.af41.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      sStats = service.currentStreamStats['rx_live_qos']!;
      expect(sStats.dscpTransitStatus, equals(DscpTransitStatus.remarkedOrStripped));
      expect(sStats.dscpVerifiedByOsTos, isFalse);
      expect(sStats.receivedDscp, equals(DscpPreset.af41.dscpValue));
      expect(sStats.receivedTosByte, isNull);
      expect(service.currentStats.dscpTransitStatus, equals(DscpTransitStatus.remarkedOrStripped));
      expect(service.currentStats.dscpVerifiedByOsTos, isFalse);

      // 3) Mismatched hint BE (0) without OS TOS -> remarkedToZero, dscpVerifiedByOsTos == false
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 3,
          dscpValue: DscpPreset.bestEffort.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      sStats = service.currentStreamStats['rx_live_qos']!;
      expect(sStats.dscpTransitStatus, equals(DscpTransitStatus.remarkedToZero));
      expect(sStats.dscpVerifiedByOsTos, isFalse);
      expect(sStats.receivedDscp, equals(0));
      expect(sStats.receivedTosByte, isNull);

      // 4) Real OS TOS EF (0xB8) -> preserved and dscpVerifiedByOsTos == true
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 4,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
        receivedTosByte: DscpPreset.ef.tosByte,
      );
      service.recalculateStatsForTesting();
      sStats = service.currentStreamStats['rx_live_qos']!;
      expect(sStats.dscpTransitStatus, equals(DscpTransitStatus.preserved));
      expect(sStats.dscpVerifiedByOsTos, isTrue);
      expect(sStats.receivedDscp, equals(DscpPreset.ef.dscpValue));
      expect(sStats.receivedTosByte, equals(DscpPreset.ef.tosByte));
      expect(service.currentStats.dscpTransitStatus, equals(DscpTransitStatus.preserved));
      expect(service.currentStats.dscpVerifiedByOsTos, isTrue);

      // 5) Subsequent matching packet without OS TOS clears OS verification & stale TOS fields
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 5,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      sStats = service.currentStreamStats['rx_live_qos']!;
      expect(sStats.dscpTransitStatus, equals(DscpTransitStatus.unverified));
      expect(sStats.dscpVerifiedByOsTos, isFalse);
      expect(sStats.receivedDscp, isNull);
      expect(sStats.receivedTosByte, isNull);
      expect(service.currentStats.dscpVerifiedByOsTos, isFalse);

      // 6) Multi-stream aggregate consistency: alert stream metadata stays coherent
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_alert_qos',
          name: 'Alert QoS',
          groupAddress: '239.255.9.11',
          port: 5004,
          expectedDscp: DscpPreset.af41,
        ),
      );
      // Put rx_live_qos back to preserved (OS TOS verified)
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.10',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'live_qos',
          seq: 6,
          dscpValue: DscpPreset.ef.dscpValue,
        ),
        5004,
        receivedTosByte: DscpPreset.ef.tosByte,
      );
      // rx_alert_qos sees in-band BE mismatch without OS TOS
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.9.11',
          port: 5004,
          sourceIp: '10.0.0.2',
          sessionId: 'alert_qos',
          seq: 1,
          dscpValue: DscpPreset.bestEffort.dscpValue,
        ),
        5004,
      );
      service.recalculateStatsForTesting();
      expect(service.currentStats.dscpTransitStatus, equals(DscpTransitStatus.remarkedToZero));
      expect(service.currentStats.dscpVerifiedByOsTos, isFalse);
      expect(service.currentStats.expectedDscp, equals(DscpPreset.af41));
      expect(service.currentStats.receivedDscp, equals(0));
    });

    test('Priority 1.6: stopping ASM stream on shared pooled socket drops (*, G) while preserving OS-filtered SSM (S, G)', () async {
      final service = MulticastReceiverService();
      addTearDown(service.dispose);
      final spySocket = _SpyRawDatagramSocket();

      const ssmConfig = MulticastReceiverStreamConfig(
        id: 'rx_ssm_os',
        name: 'SSM OS Filtered',
        groupAddress: '232.1.1.10',
        port: 5004,
        joinMode: IgmpJoinMode.ssm,
        sourceFilterIp: '10.0.0.10',
      );
      const asmConfig = MulticastReceiverStreamConfig(
        id: 'rx_asm_shared',
        name: 'ASM Shared Group',
        groupAddress: '232.1.1.10',
        port: 5004,
        joinMode: IgmpJoinMode.asm,
      );

      service.addStreamForTesting(
        ssmConfig,
        ssmOsFilterApplied: true,
        socket: spySocket,
      );
      service.addStreamForTesting(
        asmConfig,
        ssmOsFilterApplied: false,
        socket: spySocket,
      );

      expect(service.joinedSsmKeysForTesting(5004), equals({'232.1.1.10|10.0.0.10'}));
      expect(service.joinedGroupsForTesting(5004), equals({'232.1.1.10'}));

      await service.stopStream('rx_asm_shared');

      expect(service.joinedGroupsForTesting(5004), isEmpty);
      expect(spySocket.leftGroups, equals(['232.1.1.10']));
      expect(service.joinedSsmKeysForTesting(5004), equals({'232.1.1.10|10.0.0.10'}));
      expect(spySocket.rawOptions, isEmpty);
      expect(spySocket.closed, isFalse);

      await service.stopStream('rx_ssm_os');

      expect(service.joinedSsmKeysForTesting(5004), isEmpty);
      expect(spySocket.closed, isTrue);

      // Conversely, when SSM fell back to (*, G) (ssmOsFilterApplied == false),
      // stopping ASM must keep (*, G) active until fallback SSM also stops.
      final fallbackSpy = _SpyRawDatagramSocket();
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_ssm_fallback',
          name: 'SSM Fallback',
          groupAddress: '239.255.2.20',
          port: 5005,
          joinMode: IgmpJoinMode.ssm,
          sourceFilterIp: '10.0.0.20',
        ),
        ssmOsFilterApplied: false,
        socket: fallbackSpy,
      );
      service.addStreamForTesting(
        const MulticastReceiverStreamConfig(
          id: 'rx_asm_fallback',
          name: 'ASM Same Group',
          groupAddress: '239.255.2.20',
          port: 5005,
          joinMode: IgmpJoinMode.asm,
        ),
        ssmOsFilterApplied: false,
        socket: fallbackSpy,
      );

      await service.stopStream('rx_asm_fallback');
      expect(service.joinedGroupsForTesting(5005), equals({'239.255.2.20'}));
      expect(fallbackSpy.leftGroups, isEmpty);

      await service.stopStream('rx_ssm_fallback');
      expect(service.joinedGroupsForTesting(5005), isEmpty);
      expect(fallbackSpy.leftGroups, equals(['239.255.2.20']));
      expect(fallbackSpy.closed, isTrue);
    });

    test('Priority 2.3: unsubscribed streams map caps at maxUnsubscribedStreams and evicts oldest lastSeen', () {
      final t0 = DateTime(2026, 3, 1, 12, 0, 0);
      DateTime fakeNow = t0;
      final service = MulticastReceiverService(
        clock: () => fakeNow,
        maxUnsubscribedStreams: 3,
      );
      addTearDown(service.dispose);

      expect(MulticastReceiverService.defaultMaxUnsubscribedStreams, equals(500));

      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.20.1',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'u1',
          seq: 1,
        ),
        5004,
        timestamp: t0,
      );
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.20.2',
          port: 5004,
          sourceIp: '10.0.0.2',
          sessionId: 'u2',
          seq: 1,
        ),
        5004,
        timestamp: t0.add(const Duration(seconds: 1)),
      );
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.20.3',
          port: 5004,
          sourceIp: '10.0.0.3',
          sessionId: 'u3',
          seq: 1,
        ),
        5004,
        timestamp: t0.add(const Duration(seconds: 2)),
      );

      // Refresh .1 so .2 becomes the oldest lastSeen entry.
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.20.1',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'u1',
          seq: 2,
        ),
        5004,
        timestamp: t0.add(const Duration(seconds: 3)),
      );

      // Insert a 4th unsubscribed stream -> must evict 239.255.20.2.
      service.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.20.4',
          port: 5004,
          sourceIp: '10.0.0.4',
          sessionId: 'u4',
          seq: 1,
        ),
        5004,
        timestamp: t0.add(const Duration(seconds: 4)),
      );

      service.recalculateStatsForTesting();
      final groups = service.unsubscribedStreams.map((s) => s.groupAddress).toSet();
      expect(service.unsubscribedStreams.length, equals(3));
      expect(service.currentStats.unsubscribedStreamsCount, equals(3));
      expect(
        groups,
        equals({'239.255.20.1', '239.255.20.3', '239.255.20.4'}),
      );

      // Verify invalid cap <= 0 clamps cleanly to 1.
      final clampedService = MulticastReceiverService(
        clock: () => fakeNow,
        maxUnsubscribedStreams: 0,
      );
      addTearDown(clampedService.dispose);
      clampedService.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.30.1',
          port: 5004,
          sourceIp: '10.0.0.1',
          sessionId: 'c1',
          seq: 1,
        ),
        5004,
        timestamp: t0,
      );
      clampedService.processDatagramForTesting(
        buildDatagram(
          groupIp: '239.255.30.2',
          port: 5004,
          sourceIp: '10.0.0.2',
          sessionId: 'c2',
          seq: 1,
        ),
        5004,
        timestamp: t0.add(const Duration(seconds: 1)),
      );
      clampedService.recalculateStatsForTesting();
      expect(clampedService.unsubscribedStreams.length, equals(1));
      expect(clampedService.unsubscribedStreams.first.groupAddress, equals('239.255.30.2'));
    });
  });
}

class _SpyRawDatagramSocket implements RawDatagramSocket {
  final List<String> leftGroups = [];
  final List<RawSocketOption> rawOptions = [];
  bool closed = false;

  @override
  void leaveMulticast(InternetAddress group, [NetworkInterface? interface]) {
    leftGroups.add(group.address);
  }

  @override
  void setRawOption(RawSocketOption option) {
    rawOptions.add(option);
  }

  @override
  void close() {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
