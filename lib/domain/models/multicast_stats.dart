class SenderStats {
  final String streamId;
  final String streamName;
  final String groupAddress;
  final int port;
  final int packetsSent;
  final int bytesSent;
  final double currentPps;
  final double currentBitrateMbps;
  final String activeSessionId;
  final Duration duration;
  final int activeStreamsCount;

  const SenderStats({
    this.streamId = '',
    this.streamName = '',
    this.groupAddress = '',
    this.port = 0,
    this.packetsSent = 0,
    this.bytesSent = 0,
    this.currentPps = 0.0,
    this.currentBitrateMbps = 0.0,
    this.activeSessionId = '',
    this.duration = Duration.zero,
    this.activeStreamsCount = 0,
  });

  SenderStats copyWith({
    String? streamId,
    String? streamName,
    String? groupAddress,
    int? port,
    int? packetsSent,
    int? bytesSent,
    double? currentPps,
    double? currentBitrateMbps,
    String? activeSessionId,
    Duration? duration,
    int? activeStreamsCount,
  }) {
    return SenderStats(
      streamId: streamId ?? this.streamId,
      streamName: streamName ?? this.streamName,
      groupAddress: groupAddress ?? this.groupAddress,
      port: port ?? this.port,
      packetsSent: packetsSent ?? this.packetsSent,
      bytesSent: bytesSent ?? this.bytesSent,
      currentPps: currentPps ?? this.currentPps,
      currentBitrateMbps: currentBitrateMbps ?? this.currentBitrateMbps,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      duration: duration ?? this.duration,
      activeStreamsCount: activeStreamsCount ?? this.activeStreamsCount,
    );
  }
}

class ReceiverStats {
  final String streamId;
  final String streamName;
  final String groupAddress;
  final int port;
  final int packetsReceived;
  final int expectedPackets;
  final int packetsLost;
  final double lossRatePercent;
  final int outOfOrderPackets;
  final int duplicatePackets;
  final int totalGaps;
  final int maxGapPackets;
  final double maxGapDurationMs;
  final double avgGapDurationMs;
  final double currentPps;
  final double currentBitrateMbps;
  final double jitterMs;
  final int? firstSeq;
  final int? lastSeq;
  final String? activeSessionId;
  final Duration duration;
  final int activeStreamsCount;

  const ReceiverStats({
    this.streamId = '',
    this.streamName = '',
    this.groupAddress = '',
    this.port = 0,
    this.packetsReceived = 0,
    this.expectedPackets = 0,
    this.packetsLost = 0,
    this.lossRatePercent = 0.0,
    this.outOfOrderPackets = 0,
    this.duplicatePackets = 0,
    this.totalGaps = 0,
    this.maxGapPackets = 0,
    this.maxGapDurationMs = 0.0,
    this.avgGapDurationMs = 0.0,
    this.currentPps = 0.0,
    this.currentBitrateMbps = 0.0,
    this.jitterMs = 0.0,
    this.firstSeq,
    this.lastSeq,
    this.activeSessionId,
    this.duration = Duration.zero,
    this.activeStreamsCount = 0,
  });

  ReceiverStats copyWith({
    String? streamId,
    String? streamName,
    String? groupAddress,
    int? port,
    int? packetsReceived,
    int? expectedPackets,
    int? packetsLost,
    double? lossRatePercent,
    int? outOfOrderPackets,
    int? duplicatePackets,
    int? totalGaps,
    int? maxGapPackets,
    double? maxGapDurationMs,
    double? avgGapDurationMs,
    double? currentPps,
    double? currentBitrateMbps,
    double? jitterMs,
    int? firstSeq,
    int? lastSeq,
    String? activeSessionId,
    Duration? duration,
    int? activeStreamsCount,
  }) {
    return ReceiverStats(
      streamId: streamId ?? this.streamId,
      streamName: streamName ?? this.streamName,
      groupAddress: groupAddress ?? this.groupAddress,
      port: port ?? this.port,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      expectedPackets: expectedPackets ?? this.expectedPackets,
      packetsLost: packetsLost ?? this.packetsLost,
      lossRatePercent: lossRatePercent ?? this.lossRatePercent,
      outOfOrderPackets: outOfOrderPackets ?? this.outOfOrderPackets,
      duplicatePackets: duplicatePackets ?? this.duplicatePackets,
      totalGaps: totalGaps ?? this.totalGaps,
      maxGapPackets: maxGapPackets ?? this.maxGapPackets,
      maxGapDurationMs: maxGapDurationMs ?? this.maxGapDurationMs,
      avgGapDurationMs: avgGapDurationMs ?? this.avgGapDurationMs,
      currentPps: currentPps ?? this.currentPps,
      currentBitrateMbps: currentBitrateMbps ?? this.currentBitrateMbps,
      jitterMs: jitterMs ?? this.jitterMs,
      firstSeq: firstSeq ?? this.firstSeq,
      lastSeq: lastSeq ?? this.lastSeq,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      duration: duration ?? this.duration,
      activeStreamsCount: activeStreamsCount ?? this.activeStreamsCount,
    );
  }
}
