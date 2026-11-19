import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../domain/models/dscp_preset.dart';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';
import 'dscp_socket_helper.dart';

class _PooledSocket {
  final RawDatagramSocket? socket;
  final int port;
  final Set<String> joinedGroups = {};
  final Set<String> joinedSsmKeys = {}; // "group|sourceIp" when OS SSM succeeded

  _PooledSocket({this.socket, required this.port});
}

class _ReceiverStreamContext {
  final MulticastReceiverStreamConfig config;
  final _PooledSocket pooledSocket;
  final bool isJoined;
  final bool ssmOsFilterApplied;
  final String? ssmDiagnosticNote;
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
  int? lastReceivedDscp;
  int? lastReceivedTosByte;
  int? lastPacketHintDscp;
  DscpPreset? senderDscpPreset;
  DscpTransitStatus dscpTransitStatus = DscpTransitStatus.unverified;
  bool dscpVerifiedByOsTos = false;
  final List<MulticastGapEvent> gaps = [];
  int totalGapsCount = 0;
  int maxGapPackets = 0;
  double maxGapDurationMs = 0.0;
  double sumGapDurationMs = 0.0;
  ReceiverStats stats;

  _ReceiverStreamContext({
    required this.config,
    required this.pooledSocket,
    required this.isJoined,
    this.ssmOsFilterApplied = false,
    this.ssmDiagnosticNote,
    required this.startTime,
    required this.lastSnapshotTime,
    required this.stats,
  });
}

class _DrainingLeaveContext {
  final MulticastReceiverStreamConfig config;
  final _PooledSocket pooledSocket;
  final DateTime leaveIssuedAt;
  final bool hadPriorTraffic;
  final Completer<LeaveLatencyResult> completer;
  final Duration silenceTimeout;
  final void Function(String streamId) onSilenceTimeout;
  DateTime? lastPacketReceivedAt;
  int trailingPacketsReceived = 0;
  int trailingBytesReceived = 0;
  Timer? maxDrainTimer;
  Timer? silenceTimer;
  bool completed = false;

  _DrainingLeaveContext({
    required this.config,
    required this.pooledSocket,
    required this.leaveIssuedAt,
    required this.hadPriorTraffic,
    required this.completer,
    required this.silenceTimeout,
    required this.onSilenceTimeout,
  });

  void restartSilenceTimer() {
    silenceTimer?.cancel();
    silenceTimer = Timer(silenceTimeout, () {
      onSilenceTimeout(config.id);
    });
  }

  LeaveLatencyResult buildResult({
    required FastLeaveStatus status,
    bool aborted = false,
    DateTime? completedAt,
  }) {
    final latencyMs = lastPacketReceivedAt == null
        ? 0
        : lastPacketReceivedAt!
            .difference(leaveIssuedAt)
            .inMilliseconds
            .clamp(0, 86400000);
    return LeaveLatencyResult(
      streamId: config.id,
      streamName: config.name,
      groupIp: config.groupAddress,
      port: config.port,
      leaveIssuedAt: leaveIssuedAt,
      lastPacketReceivedAt: lastPacketReceivedAt,
      leaveLatencyMs: latencyMs,
      trailingPacketsReceived: trailingPacketsReceived,
      trailingBytesReceived: trailingBytesReceived,
      status: status,
      aborted: aborted,
      completedAt: completedAt,
    );
  }
}

class _UnsubscribedStreamContext {
  final String groupAddress;
  final int port;
  String sourceIp;
  String sessionId;
  int packetsReceived = 0;
  int bytesReceived = 0;
  int lastPacketsSnapshot = 0;
  int bytesSinceSnapshot = 0;
  DateTime lastSnapshotTime;
  final DateTime firstSeen;
  DateTime lastSeen;
  UnsubscribedStreamInfo info;

  _UnsubscribedStreamContext({
    required this.groupAddress,
    required this.port,
    required this.sourceIp,
    required this.sessionId,
    required this.firstSeen,
    required this.lastSeen,
    required this.lastSnapshotTime,
    required this.info,
  });
}

class MulticastReceiverService {
  final DateTime Function() _now;
  final int _maxUnsubscribedStreams;

  MulticastReceiverService({
    DateTime Function()? clock,
    int maxUnsubscribedStreams = defaultMaxUnsubscribedStreams,
  })  : _now = clock ?? DateTime.now,
        _maxUnsubscribedStreams =
            maxUnsubscribedStreams < 1 ? 1 : maxUnsubscribedStreams;

  final Map<int, List<_PooledSocket>> _socketPoolByPort = {};
  final Map<String, _ReceiverStreamContext> _streams = {}; // streamId -> context
  final Map<String, _DrainingLeaveContext> _drainingStreams = {}; // streamId -> drain context
  final Map<String, String> _sessionToStreamId = {}; // sessionId -> streamId
  final Map<String, _UnsubscribedStreamContext> _unsubscribedContexts = {}; // group:port -> context
  List<UnsubscribedStreamInfo> _unsubscribedList = [];
  final Set<int> _passiveServerPorts = {};
  final List<MulticastGapEvent> _allGaps = [];
  final Map<String, LeaveLatencyResult> _leaveLatencyByStream = {};
  LeaveLatencyResult? _lastLeaveLatency;
  Timer? _statsTimer;
  NetworkInterface? _rawInterface;

  static const int maxMembershipsPerSocket = 16;
  static const int maxRetainedGaps = 5000;
  static const int defaultMaxUnsubscribedStreams = 500;
  static const Duration defaultMaxDrainDuration = Duration(milliseconds: 3000);
  static const Duration defaultSilenceTimeout = Duration(milliseconds: 500);
  static const Duration defaultPriorTrafficFreshness = Duration(seconds: 5);

  final _statsController = StreamController<ReceiverStats>.broadcast();
  Stream<ReceiverStats> get statsStream => _statsController.stream;

  final _streamStatsController = StreamController<Map<String, ReceiverStats>>.broadcast();
  Stream<Map<String, ReceiverStats>> get streamStatsStream => _streamStatsController.stream;

  final _gapController = StreamController<MulticastGapEvent>.broadcast();
  Stream<MulticastGapEvent> get gapStream => _gapController.stream;

  final _unsubscribedController = StreamController<List<UnsubscribedStreamInfo>>.broadcast();
  Stream<List<UnsubscribedStreamInfo>> get unsubscribedStreamsStream => _unsubscribedController.stream;

  final _leaveLatencyController = StreamController<LeaveLatencyResult?>.broadcast();
  Stream<LeaveLatencyResult?> get leaveLatencyStream => _leaveLatencyController.stream;

  List<MulticastGapEvent> get gaps => List.unmodifiable(_allGaps);
  List<UnsubscribedStreamInfo> get unsubscribedStreams => List.unmodifiable(_unsubscribedList);
  LeaveLatencyResult? get lastLeaveLatency => _lastLeaveLatency;
  Map<String, LeaveLatencyResult> get leaveLatencyByStream =>
      Map.unmodifiable(_leaveLatencyByStream);

  ReceiverStats _aggregateStats = const ReceiverStats();
  ReceiverStats get currentStats => _aggregateStats;

  Map<String, ReceiverStats> _streamStats = {};
  Map<String, ReceiverStats> get currentStreamStats => Map.unmodifiable(_streamStats);

  bool get isRunning => _streams.isNotEmpty || _passiveServerPorts.isNotEmpty;
  bool get isMeasuringLeave => _drainingStreams.isNotEmpty;
  bool isStreamMeasuringLeave(String streamId) => _drainingStreams.containsKey(streamId);
  bool get isPassiveServerRunning =>
      _passiveServerPorts.isNotEmpty || _streams.values.any((s) => !s.isJoined);
  Set<int> get activePassivePorts => Set.unmodifiable(_passiveServerPorts);

  bool isStreamRunning(String streamId) => _streams.containsKey(streamId);
  bool isStreamJoined(String streamId) => _streams[streamId]?.isJoined ?? false;

  Future<_PooledSocket> _ensurePooledSocket({
    required int port,
    required bool enableLoopback,
    String? groupForMembership,
  }) async {
    final pool = _socketPoolByPort.putIfAbsent(port, () => []);
    _PooledSocket? pooled;

    for (final p in pool) {
      if (p.socket == null) continue;
      if (groupForMembership == null ||
          p.joinedGroups.contains(groupForMembership) ||
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
      DscpSocketHelper.enableReceiveTos(socket);
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

    return pooled;
  }

  static RawSocketOption? _buildSsmSourceOption({
    required InternetAddress group,
    required InternetAddress source,
    NetworkInterface? rawInterface,
    required bool drop,
  }) {
    if (group.rawAddress.length != 4 || source.rawAddress.length != 4) {
      return null;
    }
    int optionId;
    bool interfaceSecond;
    if (Platform.isLinux || Platform.isAndroid) {
      optionId = drop ? 40 : 39; // IP_DROP_SOURCE_MEMBERSHIP : IP_ADD_SOURCE_MEMBERSHIP
      interfaceSecond = true;
    } else if (Platform.isMacOS || Platform.isIOS) {
      optionId = drop ? 71 : 70;
      interfaceSecond = false;
    } else if (Platform.isWindows) {
      optionId = drop ? 16 : 15;
      interfaceSecond = false;
    } else {
      return null;
    }

    Uint8List ifaceBytes = Uint8List(4);
    if (rawInterface != null) {
      for (final addr in rawInterface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && addr.rawAddress.length == 4) {
          ifaceBytes = addr.rawAddress;
          break;
        }
      }
    }

    final payload = Uint8List(12);
    payload.setRange(0, 4, group.rawAddress);
    if (interfaceSecond) {
      payload.setRange(4, 8, ifaceBytes);
      payload.setRange(8, 12, source.rawAddress);
    } else {
      payload.setRange(4, 8, source.rawAddress);
      payload.setRange(8, 12, ifaceBytes);
    }

    return RawSocketOption(DscpSocketHelper.ipProtoIp, optionId, payload);
  }

  /// Starts a UDP listener on [port] WITHOUT joining any IGMP multicast group.
  /// Any multicast test packets received on this socket indicate flooded / unsubscribed traffic.
  Future<void> startPassiveServer({
    required int port,
    bool enableLoopback = true,
  }) async {
    await _ensurePooledSocket(
      port: port,
      enableLoopback: enableLoopback,
    );
    _passiveServerPorts.add(port);
    _ensureStatsTimer();
    _recalculateStats();
  }

  Future<void> stopPassiveServer([int? port]) async {
    final portsToRemove = port != null ? <int>[port] : _passiveServerPorts.toList();
    for (final p in portsToRemove) {
      _passiveServerPorts.remove(p);
      final pool = _socketPoolByPort[p];
      if (pool != null) {
        final toClose = pool
            .where((pooled) =>
                !_streams.values.any((s) => s.pooledSocket == pooled) &&
                !_drainingStreams.values.any((d) => d.pooledSocket == pooled))
            .toList();
        for (final unused in toClose) {
          pool.remove(unused);
          try {
            unused.socket?.close();
          } catch (_) {}
        }
        if (pool.isEmpty) {
          _socketPoolByPort.remove(p);
        }
      }
    }
    _recalculateStats();
    if (!isRunning) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  Future<void> startStream({
    required MulticastReceiverStreamConfig streamConfig,
    NetworkInterface? rawInterface,
    bool enableLoopback = true,
    bool passiveListenOnly = false,
  }) async {
    if (_drainingStreams.containsKey(streamConfig.id)) {
      abortLeaveMeasurement(streamConfig.id);
    }
    if (_streams.containsKey(streamConfig.id)) {
      await stopStream(streamConfig.id);
    }

    _rawInterface = rawInterface;

    final targetGroup = InternetAddress(streamConfig.groupAddress);
    final port = streamConfig.port;
    final shouldJoin = streamConfig.joinGroup && !passiveListenOnly;

    final pooled = await _ensurePooledSocket(
      port: port,
      enableLoopback: enableLoopback,
      groupForMembership: shouldJoin ? streamConfig.groupAddress : null,
    );

    bool ssmOsFilterApplied = false;
    String? ssmDiagnosticNote;

    // Only join multicast group on this socket if shouldJoin is true
    if (shouldJoin) {
      if (streamConfig.isSsm && streamConfig.hasSourceFilter) {
        final sourceIp = streamConfig.normalizedSourceIp;
        final ssmKey = '${streamConfig.groupAddress}|$sourceIp';
        InternetAddress? sourceAddress;
        try {
          sourceAddress = InternetAddress(sourceIp);
        } catch (_) {
          sourceAddress = null;
        }

        if (sourceAddress != null && pooled.joinedSsmKeys.contains(ssmKey)) {
          ssmOsFilterApplied = true;
        } else if (sourceAddress != null && pooled.socket != null) {
          final ssmOpt = _buildSsmSourceOption(
            group: targetGroup,
            source: sourceAddress,
            rawInterface: rawInterface,
            drop: false,
          );
          if (ssmOpt != null) {
            try {
              pooled.socket!.setRawOption(ssmOpt);
              pooled.joinedSsmKeys.add(ssmKey);
              ssmOsFilterApplied = true;
            } catch (_) {
              // Kernel/interface rejected IP_ADD_SOURCE_MEMBERSHIP; fall back to ASM + software filter
              ssmOsFilterApplied = false;
              ssmDiagnosticNote =
                  'OS SSM join unavailable; using (*, G) IGMP join with software filter ($sourceIp).';
            }
          }
        }

        // Fall back to standard (*, G) join when OS source membership was not applied
        if (!ssmOsFilterApplied &&
            !pooled.joinedGroups.contains(streamConfig.groupAddress)) {
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
          ssmDiagnosticNote ??=
              'Using (*, G) IGMP join with software source filter ($sourceIp).';
        }
      } else if (!pooled.joinedGroups.contains(streamConfig.groupAddress)) {
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
    }

    final now = _now();
    final ctx = _ReceiverStreamContext(
      config: streamConfig,
      pooledSocket: pooled,
      isJoined: shouldJoin,
      ssmOsFilterApplied: ssmOsFilterApplied,
      ssmDiagnosticNote: ssmDiagnosticNote,
      startTime: now,
      lastSnapshotTime: now,
      stats: ReceiverStats(
        streamId: streamConfig.id,
        streamName: streamConfig.name,
        groupAddress: streamConfig.groupAddress,
        port: streamConfig.port,
        duration: Duration.zero,
        joinMode: streamConfig.joinMode,
        sourceFilterIp:
            streamConfig.hasSourceFilter ? streamConfig.normalizedSourceIp : null,
        ssmOsFilterApplied: ssmOsFilterApplied,
        ssmDiagnosticNote: ssmDiagnosticNote,
        expectedDscp: streamConfig.expectedDscp,
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

    final enabledStreams = config.streams.where((s) => s.enabled).toList();

    for (final s in enabledStreams) {
      await startStream(
        streamConfig: s,
        rawInterface: rawInterface,
        enableLoopback: config.enableLoopback,
        passiveListenOnly: config.passiveListenOnly,
      );
    }

    if (config.passiveListenOnly || enabledStreams.isEmpty) {
      await startPassiveServer(
        port: config.passiveListenPort,
        enableLoopback: config.enableLoopback,
      );
    }
  }

  void _recordUnsubscribedPacket(
    MulticastPacket packet,
    Datagram datagram,
    DateTime now,
  ) {
    final key = '${packet.destinationGroup}:${packet.destinationPort}';
    final sourceIp = datagram.address.address;
    final existing = _unsubscribedContexts[key];

    if (existing == null) {
      while (_unsubscribedContexts.length >= _maxUnsubscribedStreams) {
        String? oldestKey;
        DateTime? oldestLastSeen;
        for (final entry in _unsubscribedContexts.entries) {
          if (oldestLastSeen == null ||
              entry.value.lastSeen.isBefore(oldestLastSeen)) {
            oldestLastSeen = entry.value.lastSeen;
            oldestKey = entry.key;
          }
        }
        if (oldestKey == null) break;
        _unsubscribedContexts.remove(oldestKey);
      }
      final initialInfo = UnsubscribedStreamInfo(
        groupAddress: packet.destinationGroup,
        port: packet.destinationPort,
        sourceIp: sourceIp,
        sessionId: packet.sessionId,
        packetsReceived: 1,
        bytesReceived: datagram.data.length,
        firstSeen: now,
        lastSeen: now,
      );
      final newCtx = _UnsubscribedStreamContext(
        groupAddress: packet.destinationGroup,
        port: packet.destinationPort,
        sourceIp: sourceIp,
        sessionId: packet.sessionId,
        firstSeen: now,
        lastSeen: now,
        lastSnapshotTime: now,
        info: initialInfo,
      )
        ..packetsReceived = 1
        ..bytesReceived = datagram.data.length
        ..bytesSinceSnapshot = datagram.data.length;
      _unsubscribedContexts[key] = newCtx;
    } else {
      existing.packetsReceived++;
      existing.bytesReceived += datagram.data.length;
      existing.bytesSinceSnapshot += datagram.data.length;
      existing.sourceIp = sourceIp;
      existing.sessionId = packet.sessionId;
      existing.lastSeen = now;
    }
  }

  static bool _matchesStreamConfig(
    MulticastReceiverStreamConfig config,
    MulticastPacket packet,
    String sourceIp,
  ) {
    if (config.groupAddress != packet.destinationGroup ||
        config.port != packet.destinationPort) {
      return false;
    }
    if (config.isSsm && config.hasSourceFilter) {
      return sourceIp == config.normalizedSourceIp;
    }
    return true;
  }

  void _processDatagram(
    Datagram datagram,
    int port, {
    int? receivedTosByte,
    DateTime? timestamp,
  }) {
    final packet = MulticastPacket.decode(datagram.data);
    if (packet == null) return;

    final now = timestamp ?? _now();
    final sourceIp = datagram.address.address;

    // Match stream context deterministically by destination group, port, and SSM source
    _ReceiverStreamContext? ctx;
    final mappedStreamId = _sessionToStreamId[packet.sessionId];
    if (mappedStreamId != null) {
      final mappedCtx = _streams[mappedStreamId];
      if (mappedCtx != null &&
          _matchesStreamConfig(mappedCtx.config, packet, sourceIp)) {
        ctx = mappedCtx;
      }
    }

    if (ctx == null) {
      for (final candidate in _streams.values) {
        if (_matchesStreamConfig(candidate.config, packet, sourceIp)) {
          ctx = candidate;
          _sessionToStreamId[packet.sessionId] = candidate.config.id;
          break;
        }
      }
    }

    // If no active stream matched, check whether a stream is currently draining
    // for IGMP Fast-Leave latency measurement before considering unsubscribed traffic.
    if (ctx == null && _drainingStreams.isNotEmpty) {
      bool matchedDrain = false;
      for (final entry in _drainingStreams.entries.toList()) {
        final drain = entry.value;
        if (_matchesStreamConfig(drain.config, packet, sourceIp)) {
          matchedDrain = true;
          drain.trailingPacketsReceived++;
          drain.trailingBytesReceived += datagram.data.length;
          drain.lastPacketReceivedAt = now;
          drain.restartSilenceTimer();
          final interim = drain.buildResult(status: FastLeaveStatus.measuring);
          _leaveLatencyByStream[entry.key] = interim;
          _lastLeaveLatency = interim;
          _leaveLatencyController.add(_lastLeaveLatency);
        }
      }
      if (matchedDrain) {
        _recalculateStats();
        return;
      }
    }

    // If a joined SSM stream exists for (group, port) with a different source IP,
    // software-drop the unauthorized source rather than reporting it as unsubscribed flooding.
    if (ctx == null) {
      final filteredByJoinedSsm = _streams.values.any(
        (candidate) =>
            candidate.isJoined &&
            candidate.config.isSsm &&
            candidate.config.hasSourceFilter &&
            candidate.config.groupAddress == packet.destinationGroup &&
            candidate.config.port == packet.destinationPort &&
            sourceIp != candidate.config.normalizedSourceIp,
      );
      if (filteredByJoinedSsm) {
        return;
      }
    }

    // If no subscribed stream matches, or if the matched stream was started without an IGMP Join,
    // record this packet as unsubscribed / flooded multicast traffic!
    if (ctx == null || !ctx.isJoined) {
      _recordUnsubscribedPacket(packet, datagram, now);
    }

    // If no configured stream matches the packet's destination group and port, do not attribute to subscribed streams
    if (ctx == null) return;

    // Decode DSCP QoS hint & verify received OS TOS metadata (if provided)
    final hintDscp = packet.encodedDscp;
    if (hintDscp != null) {
      ctx.lastPacketHintDscp = hintDscp;
      ctx.senderDscpPreset = DscpPreset.tryFromDscpValue(hintDscp);
    }
    if (receivedTosByte != null) {
      final rxDscp = DscpPreset.extractDscpFromTos(receivedTosByte);
      ctx.dscpVerifiedByOsTos = true;
      ctx.lastReceivedTosByte = receivedTosByte;
      ctx.lastReceivedDscp = rxDscp;
      final expectedPreset = ctx.config.expectedDscp ?? ctx.senderDscpPreset;
      ctx.dscpTransitStatus = DscpPreset.evaluateTransitStatus(
        expectedDscp: expectedPreset?.dscpValue,
        observedDscp: rxDscp,
      );
    } else {
      ctx.dscpVerifiedByOsTos = false;
      ctx.lastReceivedTosByte = null;
      final expectedDscp = ctx.config.expectedDscp;
      if (expectedDscp != null &&
          hintDscp != null &&
          hintDscp != expectedDscp.dscpValue) {
        final inBandStatus = DscpPreset.evaluateTransitStatus(
          expectedDscp: expectedDscp.dscpValue,
          observedDscp: hintDscp,
        );
        ctx.dscpTransitStatus = inBandStatus;
        ctx.lastReceivedDscp =
            inBandStatus == DscpTransitStatus.unverified ? null : hintDscp;
      } else {
        ctx.lastReceivedDscp = null;
        ctx.dscpTransitStatus = DscpTransitStatus.unverified;
      }
    }

    ctx.bytesSinceSnapshot += datagram.data.length;
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

  void _dropMulticastMembership(_ReceiverStreamContext ctx) {
    if (!ctx.isJoined) return;
    final targetGroup = InternetAddress(ctx.config.groupAddress);
    final pooled = ctx.pooledSocket;

    if (ctx.ssmOsFilterApplied &&
        ctx.config.isSsm &&
        ctx.config.hasSourceFilter) {
      final sourceIp = ctx.config.normalizedSourceIp;
      final ssmKey = '${ctx.config.groupAddress}|$sourceIp';
      final ssmStillUsed = _streams.values.any(
        (s) =>
            s.pooledSocket == pooled &&
            s.isJoined &&
            s.ssmOsFilterApplied &&
            s.config.isSsm &&
            s.config.groupAddress == ctx.config.groupAddress &&
            s.config.normalizedSourceIp == sourceIp,
      );
      if (!ssmStillUsed && pooled.joinedSsmKeys.remove(ssmKey)) {
        try {
          final dropOpt = _buildSsmSourceOption(
            group: targetGroup,
            source: InternetAddress(sourceIp),
            rawInterface: _rawInterface,
            drop: true,
          );
          if (dropOpt != null) {
            pooled.socket?.setRawOption(dropOpt);
          }
        } catch (_) {}
      }
    }

    final groupStillUsed = _streams.values.any(
      (s) =>
          s.pooledSocket == pooled &&
          s.isJoined &&
          !s.ssmOsFilterApplied &&
          s.config.groupAddress == ctx.config.groupAddress,
    );
    if (!groupStillUsed && pooled.joinedGroups.remove(ctx.config.groupAddress)) {
      try {
        pooled.socket?.leaveMulticast(targetGroup, _rawInterface);
      } catch (_) {
        try {
          pooled.socket?.leaveMulticast(targetGroup);
        } catch (_) {}
      }
    }
  }

  void _releasePooledSocketIfUnused(_PooledSocket pooled, int port) {
    final socketStillUsed = _streams.values.any((s) => s.pooledSocket == pooled) ||
        _drainingStreams.values.any((d) => d.pooledSocket == pooled) ||
        _passiveServerPorts.contains(port);
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

  Future<void> stopStream(String streamId) async {
    if (_drainingStreams.containsKey(streamId)) {
      abortLeaveMeasurement(streamId);
    }
    final ctx = _streams.remove(streamId);
    if (ctx != null) {
      _sessionToStreamId.removeWhere((_, id) => id == streamId);
      _dropMulticastMembership(ctx);
      _releasePooledSocketIfUnused(ctx.pooledSocket, ctx.config.port);
    }

    _recalculateStats();
    if (!isRunning && !isMeasuringLeave) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }
  }

  /// Issues an IGMP Leave (`leaveMulticast` / `IP_DROP_SOURCE_MEMBERSHIP`) for
  /// [streamId] while keeping the socket bound in a post-leave drain window to
  /// measure switch/router Fast-Leave prune latency.
  ///
  /// Ends early once [silenceTimeout] elapses with no incoming packets, or caps
  /// at [maxDrainDuration] (default 3000 ms).
  Future<LeaveLatencyResult?> leaveStreamWithMeasurement(
    String streamId, {
    Duration maxDrainDuration = defaultMaxDrainDuration,
    Duration silenceTimeout = defaultSilenceTimeout,
  }) async {
    if (_drainingStreams.containsKey(streamId)) {
      return _drainingStreams[streamId]!.completer.future;
    }

    final ctx = _streams.remove(streamId);
    if (ctx == null) return null;

    _sessionToStreamId.removeWhere((_, id) => id == streamId);

    if (!ctx.isJoined) {
      _releasePooledSocketIfUnused(ctx.pooledSocket, ctx.config.port);
      _recalculateStats();
      return null;
    }

    final leaveIssuedAt = _now();
    final hadPriorTraffic = ctx.packetsReceived > 0 &&
        ctx.lastPacketTime != null &&
        leaveIssuedAt.difference(ctx.lastPacketTime!) <=
            defaultPriorTrafficFreshness;
    _dropMulticastMembership(ctx);

    final completer = Completer<LeaveLatencyResult>();
    final drainCtx = _DrainingLeaveContext(
      config: ctx.config,
      pooledSocket: ctx.pooledSocket,
      leaveIssuedAt: leaveIssuedAt,
      hadPriorTraffic: hadPriorTraffic,
      completer: completer,
      silenceTimeout: silenceTimeout,
      onSilenceTimeout: (id) => _completeDrain(id),
    );
    _drainingStreams[streamId] = drainCtx;

    final initialResult = drainCtx.buildResult(status: FastLeaveStatus.measuring);
    _leaveLatencyByStream[streamId] = initialResult;
    _lastLeaveLatency = initialResult;
    _leaveLatencyController.add(_lastLeaveLatency);
    _recalculateStats();

    drainCtx.maxDrainTimer = Timer(maxDrainDuration, () {
      _completeDrain(streamId);
    });
    drainCtx.restartSilenceTimer();

    return completer.future;
  }

  /// Leaves all active receiver streams while measuring Fast-Leave latency across
  /// every joined stream. Non-joined (passive/no-join) streams are stopped cleanly.
  Future<List<LeaveLatencyResult>> leaveAllWithMeasurement({
    Duration maxDrainDuration = defaultMaxDrainDuration,
    Duration silenceTimeout = defaultSilenceTimeout,
  }) async {
    final ids = _streams.keys.toList();
    if (ids.isEmpty) return const [];

    final futures = <Future<LeaveLatencyResult?>>[];
    for (final id in ids) {
      futures.add(
        leaveStreamWithMeasurement(
          id,
          maxDrainDuration: maxDrainDuration,
          silenceTimeout: silenceTimeout,
        ),
      );
    }
    final results = await Future.wait(futures);
    return results.whereType<LeaveLatencyResult>().toList();
  }

  /// Immediately aborts an active post-leave drain window (or all active drains
  /// when [streamId] is omitted) and closes the lingering socket cleanly.
  void abortLeaveMeasurement([String? streamId]) {
    final targetIds =
        streamId != null ? <String>[streamId] : _drainingStreams.keys.toList();
    for (final id in targetIds) {
      _completeDrain(id, aborted: true);
    }
  }

  void _completeDrain(String streamId, {bool aborted = false}) {
    final drainCtx = _drainingStreams.remove(streamId);
    if (drainCtx == null || drainCtx.completed) return;
    drainCtx.completed = true;
    drainCtx.maxDrainTimer?.cancel();
    drainCtx.silenceTimer?.cancel();

    final status = aborted
        ? FastLeaveStatus.aborted
        : (drainCtx.lastPacketReceivedAt == null
            ? (drainCtx.hadPriorTraffic
                ? FastLeaveStatus.fastLeaveActive
                : FastLeaveStatus.inconclusive)
            : FastLeaveStatus.classifyLatency(
                drainCtx.lastPacketReceivedAt!
                    .difference(drainCtx.leaveIssuedAt)
                    .inMilliseconds
                    .clamp(0, 86400000),
              ));

    final result = drainCtx.buildResult(
      status: status,
      aborted: aborted,
      completedAt: _now(),
    );

    _leaveLatencyByStream[streamId] = result;
    _lastLeaveLatency = result;
    _leaveLatencyController.add(_lastLeaveLatency);

    _releasePooledSocketIfUnused(drainCtx.pooledSocket, drainCtx.config.port);
    _recalculateStats();

    if (!isRunning && !isMeasuringLeave) {
      _statsTimer?.cancel();
      _statsTimer = null;
    }

    if (!drainCtx.completer.isCompleted) {
      drainCtx.completer.complete(result);
    }
  }

  Future<void> stop() async {
    if (_drainingStreams.isNotEmpty) {
      abortLeaveMeasurement();
    }
    for (final pool in _socketPoolByPort.values) {
      for (final p in pool) {
        for (final ssmKey in p.joinedSsmKeys.toList()) {
          final parts = ssmKey.split('|');
          if (parts.length == 2) {
            try {
              final opt = _buildSsmSourceOption(
                group: InternetAddress(parts[0]),
                source: InternetAddress(parts[1]),
                rawInterface: _rawInterface,
                drop: true,
              );
              if (opt != null) p.socket?.setRawOption(opt);
            } catch (_) {}
          }
        }
        p.joinedSsmKeys.clear();
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
    _passiveServerPorts.clear();
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

  static int _dscpAggregationPriority(_ReceiverStreamContext ctx) {
    if (ctx.dscpTransitStatus.isAlert) {
      return ctx.dscpVerifiedByOsTos ? 5 : 4;
    }
    if (ctx.dscpTransitStatus == DscpTransitStatus.preserved) {
      return 3;
    }
    if (ctx.dscpVerifiedByOsTos) {
      return 2;
    }
    if (ctx.config.expectedDscp != null) {
      return 1;
    }
    if (ctx.lastPacketHintDscp != null) {
      return 0;
    }
    return -1;
  }

  void _recalculateStats() {
    final now = _now();
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

      final sStats = ReceiverStats(
        streamId: ctx.config.id,
        streamName: ctx.config.name,
        groupAddress: ctx.config.groupAddress,
        port: ctx.config.port,
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
        joinMode: ctx.config.joinMode,
        sourceFilterIp:
            ctx.config.hasSourceFilter ? ctx.config.normalizedSourceIp : null,
        ssmOsFilterApplied: ctx.ssmOsFilterApplied,
        ssmDiagnosticNote: ctx.ssmDiagnosticNote,
        lastLeaveLatency: _leaveLatencyByStream[ctx.config.id],
        expectedDscp: ctx.config.expectedDscp,
        receivedDscp: ctx.lastReceivedDscp,
        receivedTosByte: ctx.lastReceivedTosByte,
        packetHintDscp: ctx.lastPacketHintDscp,
        senderDscpPreset: ctx.senderDscpPreset,
        dscpTransitStatus: ctx.dscpTransitStatus,
        dscpVerifiedByOsTos: ctx.dscpVerifiedByOsTos,
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

    // Update unsubscribed stream snapshots and bitrates
    int totalUnsubscribedPackets = 0;
    final updatedUnsubscribed = <UnsubscribedStreamInfo>[];
    for (final uCtx in _unsubscribedContexts.values) {
      final elapsedSec = (now.difference(uCtx.lastSnapshotTime).inMicroseconds / 1000000.0);
      final validSec = elapsedSec > 0 ? elapsedSec : 0.5;

      final ppsDelta = (uCtx.packetsReceived - uCtx.lastPacketsSnapshot) / validSec;
      final bytesDelta = uCtx.bytesSinceSnapshot / validSec;
      final mbps = (bytesDelta * 8.0) / 1000000.0;

      uCtx.lastPacketsSnapshot = uCtx.packetsReceived;
      uCtx.bytesSinceSnapshot = 0;
      uCtx.lastSnapshotTime = now;

      final updatedInfo = uCtx.info.copyWith(
        sourceIp: uCtx.sourceIp,
        sessionId: uCtx.sessionId,
        packetsReceived: uCtx.packetsReceived,
        bytesReceived: uCtx.bytesReceived,
        currentPps: ppsDelta,
        currentBitrateMbps: mbps,
        lastSeen: uCtx.lastSeen,
      );
      uCtx.info = updatedInfo;
      updatedUnsubscribed.add(updatedInfo);
      totalUnsubscribedPackets += uCtx.packetsReceived;
    }

    _unsubscribedList = updatedUnsubscribed;
    _unsubscribedController.add(_unsubscribedList);

    final globalLossPct = totalExp > 0
        ? ((totalLost / totalExp) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final avgJitter = _streams.isNotEmpty ? (sumJitter / _streams.length) : 0.0;
    final globalAvgGapMs = totalGaps > 0 ? (globalSumGapDurationMs / totalGaps) : 0.0;

    final anySsm = _streams.values.any((c) => c.config.isSsm);
    final aggJoinMode = anySsm ? IgmpJoinMode.ssm : IgmpJoinMode.asm;
    final ssmSources = _streams.values
        .where((c) => c.config.isSsm && c.config.hasSourceFilter)
        .map((c) => c.config.normalizedSourceIp)
        .toSet();
    final aggSsmOsApplied = anySsm &&
        _streams.values
            .where((c) => c.config.isSsm)
            .every((c) => c.ssmOsFilterApplied);
    final firstSsmNote = _streams.values
        .map((c) => c.ssmDiagnosticNote)
        .whereType<String>()
        .cast<String?>()
        .firstWhere((n) => n != null, orElse: () => null);

    _ReceiverStreamContext? aggDscpStream;
    int bestDscpPriority = -1;
    for (final c in _streams.values) {
      final priority = _dscpAggregationPriority(c);
      if (priority > bestDscpPriority) {
        bestDscpPriority = priority;
        aggDscpStream = c;
      }
    }

    final aggDscpStatus =
        aggDscpStream?.dscpTransitStatus ?? DscpTransitStatus.unverified;
    final aggDscpVerifiedByOsTos = aggDscpStream?.dscpVerifiedByOsTos ?? false;
    final aggExpectedDscp = aggDscpStream?.config.expectedDscp;
    final aggReceivedDscp = aggDscpStream?.lastReceivedDscp;
    final aggReceivedTosByte = aggDscpStream?.lastReceivedTosByte;
    final aggHintDscp = aggDscpStream?.lastPacketHintDscp;
    final aggSenderDscpPreset = aggDscpStream?.senderDscpPreset;

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
      unsubscribedStreamsCount: _unsubscribedList.length,
      unsubscribedPacketsReceived: totalUnsubscribedPackets,
      joinMode: aggJoinMode,
      sourceFilterIp: ssmSources.length == 1 ? ssmSources.first : null,
      ssmOsFilterApplied: aggSsmOsApplied,
      ssmDiagnosticNote: firstSsmNote,
      lastLeaveLatency: _lastLeaveLatency,
      leaveLatencyByStream: Map.unmodifiable(_leaveLatencyByStream),
      expectedDscp: aggExpectedDscp,
      receivedDscp: aggReceivedDscp,
      receivedTosByte: aggReceivedTosByte,
      packetHintDscp: aggHintDscp,
      senderDscpPreset: aggSenderDscpPreset,
      dscpTransitStatus: aggDscpStatus,
      dscpVerifiedByOsTos: aggDscpVerifiedByOsTos,
    );
    _statsController.add(_aggregateStats);
  }

  void clearLeaveLatencyResults() {
    _leaveLatencyByStream.clear();
    _lastLeaveLatency = null;
    for (final ctx in _streams.values) {
      ctx.stats = ReceiverStats(
        streamId: ctx.config.id,
        streamName: ctx.config.name,
        groupAddress: ctx.config.groupAddress,
        port: ctx.config.port,
        joinMode: ctx.config.joinMode,
        sourceFilterIp:
            ctx.config.hasSourceFilter ? ctx.config.normalizedSourceIp : null,
        ssmOsFilterApplied: ctx.ssmOsFilterApplied,
        ssmDiagnosticNote: ctx.ssmDiagnosticNote,
        expectedDscp: ctx.config.expectedDscp,
      );
    }
    _leaveLatencyController.add(null);
    _recalculateStats();
  }

  void clearUnsubscribedStreams() {
    _unsubscribedContexts.clear();
    _unsubscribedList = [];
    _unsubscribedController.add(_unsubscribedList);
    _recalculateStats();
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
  @visibleForTesting
  void addStreamForTesting(
    MulticastReceiverStreamConfig streamConfig, {
    bool passiveListenOnly = false,
    bool ssmOsFilterApplied = false,
    String? ssmDiagnosticNote,
    RawDatagramSocket? socket,
  }) {
    final now = _now();
    final shouldJoin = streamConfig.joinGroup && !passiveListenOnly;
    final pool = _socketPoolByPort.putIfAbsent(streamConfig.port, () => []);
    _PooledSocket? pooled;
    for (final p in pool) {
      if (socket != null && !identical(p.socket, socket)) {
        continue;
      }
      if (!shouldJoin ||
          p.joinedGroups.contains(streamConfig.groupAddress) ||
          p.joinedGroups.length < maxMembershipsPerSocket) {
        pooled = p;
        break;
      }
    }
    if (pooled == null) {
      pooled = _PooledSocket(socket: socket, port: streamConfig.port);
      pool.add(pooled);
    }

    if (shouldJoin) {
      if (streamConfig.isSsm &&
          streamConfig.hasSourceFilter &&
          ssmOsFilterApplied) {
        final ssmKey =
            '${streamConfig.groupAddress}|${streamConfig.normalizedSourceIp}';
        pooled.joinedSsmKeys.add(ssmKey);
      } else {
        pooled.joinedGroups.add(streamConfig.groupAddress);
      }
    }

    _streams[streamConfig.id] = _ReceiverStreamContext(
      config: streamConfig,
      pooledSocket: pooled,
      isJoined: shouldJoin,
      ssmOsFilterApplied: ssmOsFilterApplied,
      ssmDiagnosticNote: ssmDiagnosticNote,
      startTime: now,
      lastSnapshotTime: now,
      stats: ReceiverStats(
        streamId: streamConfig.id,
        streamName: streamConfig.name,
        groupAddress: streamConfig.groupAddress,
        port: streamConfig.port,
        duration: Duration.zero,
        joinMode: streamConfig.joinMode,
        sourceFilterIp:
            streamConfig.hasSourceFilter ? streamConfig.normalizedSourceIp : null,
        ssmOsFilterApplied: ssmOsFilterApplied,
        ssmDiagnosticNote: ssmDiagnosticNote,
        expectedDscp: streamConfig.expectedDscp,
      ),
    );
  }

  @visibleForTesting
  Set<String> joinedGroupsForTesting(int port) {
    final pool = _socketPoolByPort[port];
    if (pool == null) return const {};
    return pool.expand((p) => p.joinedGroups).toSet();
  }

  @visibleForTesting
  Set<String> joinedSsmKeysForTesting(int port) {
    final pool = _socketPoolByPort[port];
    if (pool == null) return const {};
    return pool.expand((p) => p.joinedSsmKeys).toSet();
  }

  @visibleForTesting
  void processDatagramForTesting(
    Datagram datagram,
    int port, {
    int? receivedTosByte,
    DateTime? timestamp,
  }) {
    _processDatagram(
      datagram,
      port,
      receivedTosByte: receivedTosByte,
      timestamp: timestamp,
    );
  }

  @visibleForTesting
  void recalculateStatsForTesting() {
    _recalculateStats();
  }

  void dispose() {
    abortLeaveMeasurement();
    stop();
    _statsController.close();
    _streamStatsController.close();
    _gapController.close();
    _unsubscribedController.close();
    _leaveLatencyController.close();
  }
}
