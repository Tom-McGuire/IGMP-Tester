import 'dart:async';
import 'dart:io';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';

class _ReceiverStreamContext {
  final MulticastReceiverStreamConfig config;
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
  ReceiverStats stats;

  _ReceiverStreamContext({
    required this.config,
    required this.startTime,
    required this.lastSnapshotTime,
    required this.stats,
  });
}

class MulticastReceiverService {
  final Map<int, RawDatagramSocket> _socketsByPort = {};
  final Map<String, _ReceiverStreamContext> _streams = {}; // streamId -> context
  final Map<String, String> _sessionToStreamId = {}; // sessionId -> streamId
  final List<MulticastGapEvent> _allGaps = [];
  Timer? _statsTimer;
  NetworkInterface? _rawInterface;

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

    // Get or create socket for this port
    RawDatagramSocket? socket = _socketsByPort[port];
    if (socket == null) {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      socket.multicastLoopback = enableLoopback;
      _socketsByPort[port] = socket;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final datagram = socket?.receive();
            if (datagram == null) break;
            _processDatagram(datagram, port);
          }
        }
      });
    }

    // Join multicast group on this socket
    try {
      socket.joinMulticast(targetGroup, rawInterface);
    } catch (_) {
      try {
        socket.joinMulticast(targetGroup);
      } catch (_) {}
    }

    final now = DateTime.now();
    final ctx = _ReceiverStreamContext(
      config: streamConfig,
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

    // Match stream context by sessionId or find candidate stream listening on this port
    _ReceiverStreamContext? ctx;
    final mappedStreamId = _sessionToStreamId[packet.sessionId];
    if (mappedStreamId != null) {
      ctx = _streams[mappedStreamId];
    }

    if (ctx == null) {
      // Find candidate stream on this port
      for (final candidate in _streams.values) {
        if (candidate.config.port == port &&
            (candidate.activeSessionId == null || candidate.activeSessionId == packet.sessionId)) {
          ctx = candidate;
          _sessionToStreamId[packet.sessionId] = candidate.config.id;
          break;
        }
      }
      ctx ??= _streams.values.firstWhere((s) => s.config.port == port, orElse: () => _streams.values.first);
    }

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
      _allGaps.add(gapEvent);
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
      final port = ctx.config.port;
      final targetGroup = InternetAddress(ctx.config.groupAddress);
      final socket = _socketsByPort[port];

      if (socket != null) {
        try {
          socket.leaveMulticast(targetGroup, _rawInterface);
        } catch (_) {}

        // If no more streams on this port, close socket
        final otherStreamsOnPort = _streams.values.any((s) => s.config.port == port);
        if (!otherStreamsOnPort) {
          _socketsByPort.remove(port);
          try {
            socket.close();
          } catch (_) {}
        }
      }
    }

    _recalculateStats();
    if (_streams.isEmpty) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  Future<void> stop() async {
    for (final ctx in _streams.values) {
      final socket = _socketsByPort[ctx.config.port];
      if (socket != null) {
        try {
          socket.leaveMulticast(InternetAddress(ctx.config.groupAddress), _rawInterface);
        } catch (_) {}
      }
    }
    for (final s in _socketsByPort.values) {
      try {
        s.close();
      } catch (_) {}
    }
    _socketsByPort.clear();
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

      int sMaxGapPkts = 0;
      double sMaxGapMs = 0.0;
      double sTotalGapMs = 0.0;

      for (final g in ctx.gaps) {
        if (g.missingPackets > sMaxGapPkts) sMaxGapPkts = g.missingPackets;
        if (g.gapDurationMs > sMaxGapMs) sMaxGapMs = g.gapDurationMs;
        sTotalGapMs += g.gapDurationMs;
      }
      final sAvgGapMs = ctx.gaps.isNotEmpty ? (sTotalGapMs / ctx.gaps.length) : 0.0;
      final duration = now.difference(ctx.startTime);

      final sStats = ctx.stats.copyWith(
        packetsReceived: ctx.packetsReceived,
        expectedPackets: expected,
        packetsLost: ctx.packetsLost,
        lossRatePercent: lossPct,
        outOfOrderPackets: ctx.outOfOrderPackets,
        duplicatePackets: ctx.duplicatePackets,
        totalGaps: ctx.gaps.length,
        maxGapPackets: sMaxGapPkts,
        maxGapDurationMs: sMaxGapMs,
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
      totalGaps += ctx.gaps.length;
      if (sMaxGapPkts > maxGapPkts) maxGapPkts = sMaxGapPkts;
      if (sMaxGapMs > maxGapMs) maxGapMs = sMaxGapMs;
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
      ctx.packetsLost = 0;
      ctx.outOfOrderPackets = 0;
      ctx.duplicatePackets = 0;
    }
    _recalculateStats();
  }

  void dispose() {
    stop();
    _statsController.close();
    _streamStatsController.close();
    _gapController.close();
  }
}
