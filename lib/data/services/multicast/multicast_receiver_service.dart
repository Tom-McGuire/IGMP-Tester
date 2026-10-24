import 'dart:async';
import 'dart:io';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';

class _PooledSocket {
  final RawDatagramSocket? socket;
  final int port;
  final Set<String> joinedGroups = {};

  _PooledSocket({this.socket, required this.port});
}

class _ReceiverStreamContext {
  final MulticastReceiverStreamConfig config;
  final _PooledSocket pooledSocket;
  final DateTime startTime;
  String? activeSessionId;
  int? firstSeq;
  int? lastSeq;
  DateTime? lastPacketTime;
  int packetsReceived = 0;
  int packetsLost = 0;
  int outOfOrderPackets = 0;
  int duplicatePackets = 0;
  double jitterUs = 0.0;
  int? lastTransitUs;
  int lastPacketsSnapshot = 0;
  int bytesSinceSnapshot = 0;
  DateTime lastSnapshotTime;
  final List<MulticastGapEvent> gaps = [];
  int totalGapsCount = 0;
  int maxGapPackets = 0;
  double maxGapDurationMs = 0.0;
  double sumGapDurationMs = 0.0;
  ReceiverStats stats;

  _ReceiverStreamContext({
    required this.config,
    required this.pooledSocket,
    required this.startTime,
    required this.lastSnapshotTime,
    required this.stats,
  });
}

class MulticastReceiverService {
  final Map<int, List<_PooledSocket>> _socketPoolByPort = {};
  final Map<String, _ReceiverStreamContext> _streams = {}; // streamId -> context
  final Map<String, String> _sessionToStreamId = {}; // sessionId -> streamId
  final List<MulticastGapEvent> _allGaps = [];
  Timer? _statsTimer;
  NetworkInterface? _rawInterface;

  static const int maxMembershipsPerSocket = 16;
  static const int maxRetainedGaps = 5000;

  final _statsController = StreamController<ReceiverStats>.broadcast();
  Stream<ReceiverStats> get statsStream => _statsController.stream;

  final _streamStatsController = StreamController<Map<String, ReceiverStats>>.broadcast();
  Stream<Map<String, ReceiverStats>> get streamStatsStream => _streamStatsController.stream;

  final _gapController = StreamController<MulticastGapEvent>.broadcast();
  Stream<MulticastGapEvent> get gapStream => _gapController.stream;

  List<MulticastGapEvent> get gaps => List.unmodifiable(_allGaps);

  ReceiverStats _aggregateStats = const ReceiverStats();
  ReceiverStats get currentStats => _aggregateStats;

  Map<String, ReceiverStats> _streamStats = {};
  Map<String, ReceiverStats> get currentStreamStats => Map.unmodifiable(_streamStats);

  bool get isRunning => _streams.isNotEmpty;
  bool isStreamRunning(String streamId) => _streams.containsKey(streamId);

  Future<void> startStream({
    required MulticastReceiverStreamConfig streamConfig,
    NetworkInterface? rawInterface,
    bool enableLoopback = true,
  }) async {
    if (_streams.containsKey(streamConfig.id)) {
      await stopStream(streamConfig.id);
    }

    _rawInterface = rawInterface;

    final targetGroup = InternetAddress(streamConfig.groupAddress);
    final port = streamConfig.port;

    // Get or allocate a pooled socket on this port that has space for another membership (< 16)
    final pool = _socketPoolByPort.putIfAbsent(port, () => []);
    _PooledSocket? pooled;

    for (final p in pool) {
      if (p.joinedGroups.contains(streamConfig.groupAddress) ||
          p.joinedGroups.length < maxMembershipsPerSocket) {
        pooled = p;
        break;
      }
    }

    if (pooled == null) {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      socket.multicastLoopback = enableLoopback;
      pooled = _PooledSocket(socket: socket, port: port);
      pool.add(pooled);

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final datagram = socket.receive();
            if (datagram == null) break;
            _processDatagram(datagram, port);
          }
        }
      });
    }

    // Join multicast group on this socket - do not silently swallow exceptions
    if (!pooled.joinedGroups.contains(streamConfig.groupAddress)) {
      try {
        pooled.socket?.joinMulticast(targetGroup, rawInterface);
      } catch (e) {
        try {
          pooled.socket?.joinMulticast(targetGroup);
        } catch (e2) {
          throw Exception(
            'Failed to join multicast group ${streamConfig.groupAddress} on port $port: $e2',
          );
        }
      }
      pooled.joinedGroups.add(streamConfig.groupAddress);
    }

    final now = DateTime.now();
    final ctx = _ReceiverStreamContext(
      config: streamConfig,
      pooledSocket: pooled,
      startTime: now,
      lastSnapshotTime: now,
      stats: ReceiverStats(
        streamId: streamConfig.id,
        streamName: streamConfig.name,
        groupAddress: streamConfig.groupAddress,
        port: streamConfig.port,
        duration: Duration.zero,
      ),
    );

    _streams[streamConfig.id] = ctx;

    _ensureStatsTimer();
    _recalculateStats();
  }

  Future<void> startAll({
    required MulticastReceiverConfig config,
    NetworkInterface? rawInterface,
  }) async {
    _rawInterface = rawInterface;

    for (final s in config.streams) {
      if (s.enabled) {
        await startStream(
          streamConfig: s,
          rawInterface: rawInterface,
          enableLoopback: config.enableLoopback,
        );
      }
    }
  }

  void _processDatagram(Datagram datagram, int port) {
    final packet = MulticastPacket.decode(datagram.data);
    if (packet == null) return;

    // Match stream context deterministically by destination group and destination port
    _ReceiverStreamContext? ctx;
    final mappedStreamId = _sessionToStreamId[packet.sessionId];
    if (mappedStreamId != null) {
      final mappedCtx = _streams[mappedStreamId];
      if (mappedCtx != null &&
          mappedCtx.config.groupAddress == packet.destinationGroup &&
          mappedCtx.config.port == packet.destinationPort) {
        ctx = mappedCtx;
      }
    }

    if (ctx == null) {
      // Find candidate stream explicitly matching destination group and port
      for (final candidate in _streams.values) {
        if (candidate.config.groupAddress == packet.destinationGroup &&
            candidate.config.port == packet.destinationPort) {
          ctx = candidate;
          _sessionToStreamId[packet.sessionId] = candidate.config.id;
          break;
        }
      }
    }

    // If no subscribed stream matches the packet's destination group and port, drop packet
    if (ctx == null) return;

    ctx.bytesSinceSnapshot += datagram.data.length;
    final now = DateTime.now();
    final nowUs = now.microsecondsSinceEpoch;

    // Jitter RFC 3550
    final transitUs = nowUs - packet.sendTimestampUs;
    if (ctx.lastTransitUs != null) {
      final d = (transitUs - ctx.lastTransitUs!).abs();
      ctx.jitterUs += (d - ctx.jitterUs) / 16.0;
    }
    ctx.lastTransitUs = transitUs;

    // Check session
    if (ctx.activeSessionId == null || ctx.activeSessionId != packet.sessionId) {
      ctx.activeSessionId = packet.sessionId;
      ctx.firstSeq = packet.sequenceNumber;
      ctx.lastSeq = packet.sequenceNumber;
      ctx.lastPacketTime = now;
      ctx.packetsReceived++;
      return;
    }

    final seq = packet.sequenceNumber;
    final last = ctx.lastSeq!;

    if (seq == last + 1) {
      // Consecutive
      ctx.packetsReceived++;
      ctx.lastSeq = seq;
      ctx.lastPacketTime = now;
    } else if (seq > last + 1) {
      // GAP DETECTED
      final missingCount = (seq - last - 1);
      final gapDuration = ctx.lastPacketTime != null
          ? now.difference(ctx.lastPacketTime!)
          : Duration.zero;
      final gapDurationMs = gapDuration.inMicroseconds / 1000.0;

      // Maintain incremental gap metrics
      ctx.totalGapsCount++;
      if (missingCount > ctx.maxGapPackets) ctx.maxGapPackets = missingCount;
      if (gapDurationMs > ctx.maxGapDurationMs) ctx.maxGapDurationMs = gapDurationMs;
      ctx.sumGapDurationMs += gapDurationMs;

      final gapEvent = MulticastGapEvent(
        id: _allGaps.length + 1,
        sessionId: packet.sessionId,
        streamName: ctx.config.name,
        groupAddress: ctx.config.groupAddress,
        port: ctx.config.port,
        timestamp: now,
        startSeq: last + 1,
        endSeq: seq - 1,
        missingPackets: missingCount,
        gapDuration: gapDuration,
        lastPacketTime: ctx.lastPacketTime ?? now,
        resumedTime: now,
      );

      ctx.gaps.add(gapEvent);
      if (ctx.gaps.length > maxRetainedGaps) {
        ctx.gaps.removeAt(0);
      }

      _allGaps.add(gapEvent);
      if (_allGaps.length > maxRetainedGaps) {
        _allGaps.removeAt(0);
      }

      _gapController.add(gapEvent);

      ctx.packetsLost += missingCount;
      ctx.packetsReceived++;
      ctx.lastSeq = seq;
      ctx.lastPacketTime = now;
    } else {
      if (seq == last) {
        ctx.duplicatePackets++;
      } else {
        ctx.outOfOrderPackets++;
      }
      ctx.packetsReceived++;
    }
  }

  Future<void> stopStream(String streamId) async {
    final ctx = _streams.remove(streamId);
    if (ctx != null) {
      // Clean up session ID mapping
      _sessionToStreamId.removeWhere((_, id) => id == streamId);

      final port = ctx.config.port;
      final targetGroup = InternetAddress(ctx.config.groupAddress);
      final pooled = ctx.pooledSocket;

      // Check if any remaining streams on this pooled socket use the same group
      final groupStillUsed = _streams.values.any(
        (s) => s.pooledSocket == pooled && s.config.groupAddress == ctx.config.groupAddress,
      );

      if (!groupStillUsed) {
        pooled.joinedGroups.remove(ctx.config.groupAddress);
        try {
          pooled.socket?.leaveMulticast(targetGroup, _rawInterface);
        } catch (_) {
          try {
            pooled.socket?.leaveMulticast(targetGroup);
          } catch (_) {}
        }
      }

      // If no streams remain on this pooled socket, close and remove it
      final socketStillUsed = _streams.values.any((s) => s.pooledSocket == pooled);
      if (!socketStillUsed) {
        _socketPoolByPort[port]?.remove(pooled);
        if (_socketPoolByPort[port]?.isEmpty ?? false) {
          _socketPoolByPort.remove(port);
        }
        try {
          pooled.socket?.close();
        } catch (_) {}
      }
    }

    _recalculateStats();
    if (_streams.isEmpty) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  Future<void> stop() async {
    for (final pool in _socketPoolByPort.values) {
      for (final p in pool) {
        for (final group in p.joinedGroups) {
          try {
            p.socket?.leaveMulticast(InternetAddress(group), _rawInterface);
          } catch (_) {
            try {
              p.socket?.leaveMulticast(InternetAddress(group));
            } catch (_) {}
          }
        }
        try {
          p.socket?.close();
        } catch (_) {}
      }
    }
    _socketPoolByPort.clear();
    _streams.clear();
    _sessionToStreamId.clear();
    _statsTimer?.cancel();
    _statsTimer = null;
    _recalculateStats();
  }

  void _ensureStatsTimer() {
    _statsTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      _recalculateStats();
    });
  }

  void _recalculateStats() {
    final now = DateTime.now();
    int totalRx = 0;
    int totalExp = 0;
    int totalLost = 0;
    int totalOoO = 0;
    int totalDup = 0;
    int totalGaps = 0;
    int maxGapPkts = 0;
    double maxGapMs = 0.0;
    double globalSumGapDurationMs = 0.0;
    double totalPps = 0.0;
    double totalMbps = 0.0;
    double sumJitter = 0.0;

    final updatedStreamStats = <String, ReceiverStats>{};

    for (final entry in _streams.entries) {
      final ctx = entry.value;
      final elapsedSec = (now.difference(ctx.lastSnapshotTime).inMicroseconds / 1000000.0);
      final validSec = elapsedSec > 0 ? elapsedSec : 0.5;

      final ppsDelta = (ctx.packetsReceived - ctx.lastPacketsSnapshot) / validSec;
      final bytesDelta = ctx.bytesSinceSnapshot / validSec;
      final mbps = (bytesDelta * 8.0) / 1000000.0;

      ctx.lastPacketsSnapshot = ctx.packetsReceived;
      ctx.bytesSinceSnapshot = 0;
      ctx.lastSnapshotTime = now;

      final expected = ctx.firstSeq != null && ctx.lastSeq != null
          ? (ctx.lastSeq! - ctx.firstSeq! + 1)
          : ctx.packetsReceived;

      final lossPct = expected > 0
          ? ((ctx.packetsLost / expected) * 100.0).clamp(0.0, 100.0)
          : 0.0;

      final sAvgGapMs = ctx.totalGapsCount > 0 ? (ctx.sumGapDurationMs / ctx.totalGapsCount) : 0.0;
      final duration = now.difference(ctx.startTime);

      final sStats = ctx.stats.copyWith(
        packetsReceived: ctx.packetsReceived,
        expectedPackets: expected,
        packetsLost: ctx.packetsLost,
        lossRatePercent: lossPct,
        outOfOrderPackets: ctx.outOfOrderPackets,
        duplicatePackets: ctx.duplicatePackets,
        totalGaps: ctx.totalGapsCount,
        maxGapPackets: ctx.maxGapPackets,
        maxGapDurationMs: ctx.maxGapDurationMs,
        avgGapDurationMs: sAvgGapMs,
        currentPps: ppsDelta,
        currentBitrateMbps: mbps,
        jitterMs: ctx.jitterUs / 1000.0,
        firstSeq: ctx.firstSeq,
        lastSeq: ctx.lastSeq,
        activeSessionId: ctx.activeSessionId,
        duration: duration,
        activeStreamsCount: 1,
      );
      ctx.stats = sStats;
      updatedStreamStats[entry.key] = sStats;

      totalRx += ctx.packetsReceived;
      totalExp += expected;
      totalLost += ctx.packetsLost;
      totalOoO += ctx.outOfOrderPackets;
      totalDup += ctx.duplicatePackets;
      totalGaps += ctx.totalGapsCount;
      globalSumGapDurationMs += ctx.sumGapDurationMs;
      if (ctx.maxGapPackets > maxGapPkts) maxGapPkts = ctx.maxGapPackets;
      if (ctx.maxGapDurationMs > maxGapMs) maxGapMs = ctx.maxGapDurationMs;
      totalPps += ppsDelta;
      totalMbps += mbps;
      sumJitter += (ctx.jitterUs / 1000.0);
    }

    _streamStats = updatedStreamStats;
    _streamStatsController.add(_streamStats);

    final globalLossPct = totalExp > 0
        ? ((totalLost / totalExp) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final avgJitter = _streams.isNotEmpty ? (sumJitter / _streams.length) : 0.0;
    final globalAvgGapMs = totalGaps > 0 ? (globalSumGapDurationMs / totalGaps) : 0.0;

    _aggregateStats = ReceiverStats(
      packetsReceived: totalRx,
      expectedPackets: totalExp,
      packetsLost: totalLost,
      lossRatePercent: globalLossPct,
      outOfOrderPackets: totalOoO,
      duplicatePackets: totalDup,
      totalGaps: totalGaps,
      maxGapPackets: maxGapPkts,
      maxGapDurationMs: maxGapMs,
      avgGapDurationMs: globalAvgGapMs,
      currentPps: totalPps,
      currentBitrateMbps: totalMbps,
      jitterMs: avgJitter,
      activeStreamsCount: _streams.length,
    );
    _statsController.add(_aggregateStats);
  }

  void clearGaps() {
    _allGaps.clear();
    for (final ctx in _streams.values) {
      ctx.gaps.clear();
      ctx.totalGapsCount = 0;
      ctx.maxGapPackets = 0;
      ctx.maxGapDurationMs = 0.0;
      ctx.sumGapDurationMs = 0.0;
      ctx.packetsLost = 0;
      ctx.outOfOrderPackets = 0;
      ctx.duplicatePackets = 0;
    }
    _recalculateStats();
  }

  // Testing hooks
  void addStreamForTesting(MulticastReceiverStreamConfig streamConfig) {
    final now = DateTime.now();
    _streams[streamConfig.id] = _ReceiverStreamContext(
      config: streamConfig,
      pooledSocket: _PooledSocket(socket: null, port: streamConfig.port),
      startTime: now,
      lastSnapshotTime: now,
      stats: ReceiverStats(
        streamId: streamConfig.id,
        streamName: streamConfig.name,
        groupAddress: streamConfig.groupAddress,
        port: streamConfig.port,
        duration: Duration.zero,
      ),
    );
  }

  void processDatagramForTesting(Datagram datagram, int port) {
    _processDatagram(datagram, port);
  }

  void recalculateStatsForTesting() {
    _recalculateStats();
  }

  void dispose() {
    stop();
    _statsController.close();
    _streamStatsController.close();
    _gapController.close();
  }
}
