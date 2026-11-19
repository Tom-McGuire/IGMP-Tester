import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../domain/models/dscp_preset.dart';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';
import 'dscp_socket_helper.dart';

class _ActiveSenderContext {
  final MulticastStreamConfig config;
  final RawDatagramSocket socket;
  final String sessionId;
  final DateTime startTime;
  final Uint8List packetBuffer;
  Timer? sendTimer;
  int seq = 0;
  int packetsSent = 0;
  int bytesSent = 0;
  int lastSendTimestampUs = 0;
  int lastPacketsSnapshot = 0;
  int lastBytesSnapshot = 0;
  DateTime lastSnapshotTime;
  SenderStats stats;

  _ActiveSenderContext({
    required this.config,
    required this.socket,
    required this.sessionId,
    required this.startTime,
    required this.packetBuffer,
    required this.lastSnapshotTime,
    required this.stats,
  });
}

class MulticastSenderService {
  final Map<String, _ActiveSenderContext> _activeStreams = {};
  Timer? _aggregateStatsTimer;

  final _statsController = StreamController<SenderStats>.broadcast();
  Stream<SenderStats> get statsStream => _statsController.stream;

  final _streamStatsController = StreamController<Map<String, SenderStats>>.broadcast();
  Stream<Map<String, SenderStats>> get streamStatsStream => _streamStatsController.stream;

  SenderStats _aggregateStats = const SenderStats();
  SenderStats get currentStats => _aggregateStats;

  Map<String, SenderStats> _streamStats = {};
  Map<String, SenderStats> get currentStreamStats => Map.unmodifiable(_streamStats);

  bool get isRunning => _activeStreams.isNotEmpty;
  bool isStreamRunning(String streamId) => _activeStreams.containsKey(streamId);

  /// Builds an IPv4 `IP_MULTICAST_IF` [RawSocketOption] (`IPPROTO_IP = 0`)
  /// carrying the 4-byte `struct in_addr` for [ipv4], or `null` if [ipv4] is
  /// not an IPv4 address.
  @visibleForTesting
  static RawSocketOption? buildMulticastIfOption(
    InternetAddress ipv4, {
    String? operatingSystemOverride,
  }) {
    if (ipv4.type != InternetAddressType.IPv4 || ipv4.rawAddress.length != 4) {
      return null;
    }
    final os = (operatingSystemOverride ?? Platform.operatingSystem)
        .toLowerCase();
    // IP_MULTICAST_IF: Windows = 9, Linux/macOS/default = 32
    final optName = os == 'windows' ? 9 : 32;
    return RawSocketOption(
      RawSocketOption.levelIPv4,
      optName,
      Uint8List.fromList(ipv4.rawAddress),
    );
  }

  /// Computes how many packets are due at [elapsedUs] for [pps] given
  /// [alreadySent], capped at [maxBurstPerTick] to prevent timer-stall bursts.
  @visibleForTesting
  static int computePacketsDue({
    required int elapsedUs,
    required int pps,
    required int alreadySent,
    int maxBurstPerTick = 64,
  }) {
    if (elapsedUs < 0 || pps <= 0 || maxBurstPerTick <= 0) {
      return 0;
    }
    final targetPackets = ((elapsedUs * pps) ~/ 1000000).clamp(
      alreadySent,
      alreadySent + maxBurstPerTick,
    );
    return targetPackets - alreadySent;
  }

  Future<RawDatagramSocket> _bindSenderSocket(
    NetworkInterface? rawInterface,
  ) async {
    InternetAddress? selectedIpv4;
    if (rawInterface != null) {
      for (final addr in rawInterface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && addr.address != '0.0.0.0') {
          selectedIpv4 = addr;
          break;
        }
      }
    }

    if (selectedIpv4 != null) {
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(selectedIpv4, 0);
      } on SocketException {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      }

      final multicastIfOption = buildMulticastIfOption(selectedIpv4);
      if (multicastIfOption != null) {
        try {
          socket.setRawOption(multicastIfOption);
        } catch (_) {}
      }
      return socket;
    }

    return RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  Future<void> startStream({
    required MulticastStreamConfig streamConfig,
    NetworkInterface? rawInterface,
    bool enableLoopback = true,
  }) async {
    if (_activeStreams.containsKey(streamConfig.id)) {
      await stopStream(streamConfig.id);
    }

    final targetGroup = InternetAddress(streamConfig.groupAddress);
    final targetPort = streamConfig.port;

    final socket = await _bindSenderSocket(rawInterface);
    socket.multicastHops = streamConfig.ttl;
    socket.multicastLoopback = enableLoopback;

    final dscpResult = DscpSocketHelper.applySenderPresetWithResult(
      socket,
      streamConfig.dscpPreset,
    );

    final now = DateTime.now();
    // Unique session ID per stream run (16 chars)
    final hexTime = now.millisecondsSinceEpoch.toRadixString(16);
    final streamHash = streamConfig.id.hashCode.abs().toRadixString(16).padLeft(4, '0');
    final sessionId = (streamHash + hexTime).padRight(16, '0').substring(0, 16);

    final pps = streamConfig.packetsPerSecond.clamp(1, 5000);
    final intervalUs = (1000000 / pps).round();

    // Pre-allocate template packet buffer with destination group, port, and DSCP hint
    final templatePacket = MulticastPacket(
      version: 1,
      flags: 0,
      dscpValue: streamConfig.dscpPreset.dscpValue,
      sessionId: sessionId,
      sequenceNumber: 0,
      sendTimestampUs: 0,
      configuredIntervalUs: intervalUs,
      payloadSize: streamConfig.packetSizeBytes,
      destinationGroup: streamConfig.groupAddress,
      destinationPort: streamConfig.port,
    );
    final packetBuffer = templatePacket.encode();

    final context = _ActiveSenderContext(
      config: streamConfig,
      socket: socket,
      sessionId: sessionId,
      startTime: now,
      packetBuffer: packetBuffer,
      lastSnapshotTime: now,
      stats: SenderStats(
        streamId: streamConfig.id,
        streamName: streamConfig.name,
        groupAddress: streamConfig.groupAddress,
        port: streamConfig.port,
        activeSessionId: sessionId,
        duration: Duration.zero,
        dscpPreset: streamConfig.dscpPreset,
        dscpSocketApplied: dscpResult.success,
        dscpWarning: dscpResult.warningMessage,
      ),
    );

    final tickMs = pps >= 20 ? 10 : 25;
    context.sendTimer = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      if (!_activeStreams.containsKey(streamConfig.id)) return;

      final nowUs = DateTime.now().microsecondsSinceEpoch;
      final elapsedUs = nowUs - context.startTime.microsecondsSinceEpoch;
      final due = computePacketsDue(
        elapsedUs: elapsedUs,
        pps: pps,
        alreadySent: context.packetsSent,
      );

      for (int i = 0; i < due; i++) {
        final sampleUs = DateTime.now().microsecondsSinceEpoch;
        final packetTimestampUs = sampleUs > context.lastSendTimestampUs
            ? sampleUs
            : context.lastSendTimestampUs + 1;
        context.lastSendTimestampUs = packetTimestampUs;

        final nextSeq = context.seq + 1;
        MulticastPacket.updateSequenceAndTimestamp(
          context.packetBuffer,
          nextSeq,
          packetTimestampUs,
        );

        final sent = socket.send(context.packetBuffer, targetGroup, targetPort);
        if (sent > 0) {
          context.seq = nextSeq;
          context.packetsSent++;
          context.bytesSent += sent;
        } else {
          break;
        }
      }
    });

    _activeStreams[streamConfig.id] = context;

    _ensureStatsTimer();
    _recalculateStats();
  }

  Future<void> startAll({
    required MulticastSenderConfig config,
    NetworkInterface? rawInterface,
  }) async {
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

  Future<void> stopStream(String streamId) async {
    final ctx = _activeStreams.remove(streamId);
    if (ctx != null) {
      ctx.sendTimer?.cancel();
      try {
        ctx.socket.close();
      } catch (_) {}
    }
    _recalculateStats();
    if (_activeStreams.isEmpty) {
      _aggregateStatsTimer?.cancel();
      _aggregateStatsTimer = null;
    }
  }

  Future<void> stop() async {
    for (final ctx in _activeStreams.values) {
      ctx.sendTimer?.cancel();
      try {
        ctx.socket.close();
      } catch (_) {}
    }
    _activeStreams.clear();
    _aggregateStatsTimer?.cancel();
    _aggregateStatsTimer = null;
    _recalculateStats();
  }

  void _ensureStatsTimer() {
    _aggregateStatsTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      _recalculateStats();
    });
  }

  void _recalculateStats() {
    final now = DateTime.now();
    int totalPkts = 0;
    int totalBytes = 0;
    double totalPps = 0.0;
    double totalMbps = 0.0;

    final updatedStreamStats = <String, SenderStats>{};

    for (final entry in _activeStreams.entries) {
      final ctx = entry.value;
      final elapsedSec = (now.difference(ctx.lastSnapshotTime).inMicroseconds / 1000000.0);
      final validSec = elapsedSec > 0 ? elapsedSec : 0.5;

      final ppsDelta = (ctx.packetsSent - ctx.lastPacketsSnapshot) / validSec;
      final bytesDelta = (ctx.bytesSent - ctx.lastBytesSnapshot) / validSec;
      final mbps = (bytesDelta * 8.0) / 1000000.0;

      ctx.lastPacketsSnapshot = ctx.packetsSent;
      ctx.lastBytesSnapshot = ctx.bytesSent;
      ctx.lastSnapshotTime = now;

      final duration = now.difference(ctx.startTime);

      final sStats = ctx.stats.copyWith(
        packetsSent: ctx.packetsSent,
        bytesSent: ctx.bytesSent,
        currentPps: ppsDelta,
        currentBitrateMbps: mbps,
        duration: duration,
        activeStreamsCount: 1,
      );
      ctx.stats = sStats;
      updatedStreamStats[entry.key] = sStats;

      totalPkts += ctx.packetsSent;
      totalBytes += ctx.bytesSent;
      totalPps += ppsDelta;
      totalMbps += mbps;
    }

    final presets = updatedStreamStats.values.map((s) => s.dscpPreset).toSet();
    final aggDscpPreset = presets.length == 1
        ? presets.first
        : DscpPreset.bestEffort;
    final aggDscpApplied =
        updatedStreamStats.isNotEmpty &&
        updatedStreamStats.values.every((s) => s.dscpSocketApplied);
    final firstDscpWarning = updatedStreamStats.values
        .map((s) => s.dscpWarning)
        .whereType<String>()
        .cast<String?>()
        .firstWhere((w) => w != null, orElse: () => null);

    _streamStats = updatedStreamStats;
    _streamStatsController.add(_streamStats);

    _aggregateStats = SenderStats(
      packetsSent: totalPkts,
      bytesSent: totalBytes,
      currentPps: totalPps,
      currentBitrateMbps: totalMbps,
      activeStreamsCount: _activeStreams.length,
      dscpPreset: aggDscpPreset,
      dscpSocketApplied: aggDscpApplied,
      dscpWarning: firstDscpWarning,
    );
    _statsController.add(_aggregateStats);
  }

  void dispose() {
    stop();
    _statsController.close();
    _streamStatsController.close();
  }
}
