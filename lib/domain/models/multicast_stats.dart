import 'dscp_preset.dart';
import 'multicast_config.dart';

/// Classification of measured IGMP Fast-Leave / Immediate-Leave switch prune latency.
enum FastLeaveStatus {
  notMeasured('Not Measured'),
  measuring('Measuring Leave...'),
  fastLeaveActive('Fast-Leave Active'),
  delayedPrune('Delayed Prune'),
  noFastLeave('No Fast-Leave (Query Timeout)'),
  inconclusive('No Traffic Before Leave'),
  aborted('Measurement Aborted');

  final String label;
  const FastLeaveStatus(this.label);

  bool get isComplete =>
      this == FastLeaveStatus.fastLeaveActive ||
      this == FastLeaveStatus.delayedPrune ||
      this == FastLeaveStatus.noFastLeave;

  /// Classifies a measured post-leave prune latency in milliseconds:
  /// - `0–50 ms`: [fastLeaveActive]
  /// - `51–500 ms`: [delayedPrune]
  /// - `> 500 ms`: [noFastLeave]
  static FastLeaveStatus classifyLatency(int latencyMs) {
    if (latencyMs <= 50) return FastLeaveStatus.fastLeaveActive;
    if (latencyMs <= 500) return FastLeaveStatus.delayedPrune;
    return FastLeaveStatus.noFastLeave;
  }
}

/// Measured IGMP Fast-Leave latency telemetry for a multicast receiver stream.
class LeaveLatencyResult {
  final String streamId;
  final String streamName;
  final String groupIp;
  final int port;
  final DateTime leaveIssuedAt;
  final DateTime? lastPacketReceivedAt;
  final int leaveLatencyMs;
  final int trailingPacketsReceived;
  final int trailingBytesReceived;
  final FastLeaveStatus status;
  final bool aborted;
  final DateTime? completedAt;

  const LeaveLatencyResult({
    this.streamId = '',
    this.streamName = '',
    required this.groupIp,
    required this.port,
    required this.leaveIssuedAt,
    this.lastPacketReceivedAt,
    required this.leaveLatencyMs,
    this.trailingPacketsReceived = 0,
    this.trailingBytesReceived = 0,
    required this.status,
    this.aborted = false,
    this.completedAt,
  });

  String get endpoint => '$groupIp:$port';
  String get streamKey => streamId.isNotEmpty ? streamId : endpoint;

  LeaveLatencyResult copyWith({
    String? streamId,
    String? streamName,
    String? groupIp,
    int? port,
    DateTime? leaveIssuedAt,
    DateTime? lastPacketReceivedAt,
    int? leaveLatencyMs,
    int? trailingPacketsReceived,
    int? trailingBytesReceived,
    FastLeaveStatus? status,
    bool? aborted,
    DateTime? completedAt,
  }) {
    return LeaveLatencyResult(
      streamId: streamId ?? this.streamId,
      streamName: streamName ?? this.streamName,
      groupIp: groupIp ?? this.groupIp,
      port: port ?? this.port,
      leaveIssuedAt: leaveIssuedAt ?? this.leaveIssuedAt,
      lastPacketReceivedAt: lastPacketReceivedAt ?? this.lastPacketReceivedAt,
      leaveLatencyMs: leaveLatencyMs ?? this.leaveLatencyMs,
      trailingPacketsReceived:
          trailingPacketsReceived ?? this.trailingPacketsReceived,
      trailingBytesReceived:
          trailingBytesReceived ?? this.trailingBytesReceived,
      status: status ?? this.status,
      aborted: aborted ?? this.aborted,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

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
  final DscpPreset dscpPreset;
  final bool dscpSocketApplied;
  final String? dscpWarning;

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
    this.dscpPreset = DscpPreset.bestEffort,
    this.dscpSocketApplied = false,
    this.dscpWarning,
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
    DscpPreset? dscpPreset,
    bool? dscpSocketApplied,
    String? dscpWarning,
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
      dscpPreset: dscpPreset ?? this.dscpPreset,
      dscpSocketApplied: dscpSocketApplied ?? this.dscpSocketApplied,
      dscpWarning: dscpWarning ?? this.dscpWarning,
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
  final int unsubscribedStreamsCount;
  final int unsubscribedPacketsReceived;
  final IgmpJoinMode joinMode;
  final String? sourceFilterIp;
  final bool ssmOsFilterApplied;
  final String? ssmDiagnosticNote;
  final LeaveLatencyResult? lastLeaveLatency;
  final Map<String, LeaveLatencyResult> leaveLatencyByStream;
  final DscpPreset? expectedDscp;
  final int? receivedDscp;
  final int? receivedTosByte;
  final int? packetHintDscp;
  final DscpPreset? senderDscpPreset;
  final DscpTransitStatus dscpTransitStatus;
  final bool dscpVerifiedByOsTos;

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
    this.unsubscribedStreamsCount = 0,
    this.unsubscribedPacketsReceived = 0,
    this.joinMode = IgmpJoinMode.asm,
    this.sourceFilterIp,
    this.ssmOsFilterApplied = false,
    this.ssmDiagnosticNote,
    this.lastLeaveLatency,
    this.leaveLatencyByStream = const {},
    this.expectedDscp,
    this.receivedDscp,
    this.receivedTosByte,
    this.packetHintDscp,
    this.senderDscpPreset,
    this.dscpTransitStatus = DscpTransitStatus.unverified,
    this.dscpVerifiedByOsTos = false,
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
    int? unsubscribedStreamsCount,
    int? unsubscribedPacketsReceived,
    IgmpJoinMode? joinMode,
    String? sourceFilterIp,
    bool? ssmOsFilterApplied,
    String? ssmDiagnosticNote,
    LeaveLatencyResult? lastLeaveLatency,
    bool clearLastLeaveLatency = false,
    Map<String, LeaveLatencyResult>? leaveLatencyByStream,
    DscpPreset? expectedDscp,
    int? receivedDscp,
    int? receivedTosByte,
    int? packetHintDscp,
    DscpPreset? senderDscpPreset,
    DscpTransitStatus? dscpTransitStatus,
    bool? dscpVerifiedByOsTos,
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
      unsubscribedStreamsCount: unsubscribedStreamsCount ?? this.unsubscribedStreamsCount,
      unsubscribedPacketsReceived: unsubscribedPacketsReceived ?? this.unsubscribedPacketsReceived,
      joinMode: joinMode ?? this.joinMode,
      sourceFilterIp: sourceFilterIp ?? this.sourceFilterIp,
      ssmOsFilterApplied: ssmOsFilterApplied ?? this.ssmOsFilterApplied,
      ssmDiagnosticNote: ssmDiagnosticNote ?? this.ssmDiagnosticNote,
      lastLeaveLatency: clearLastLeaveLatency
          ? null
          : (lastLeaveLatency ?? this.lastLeaveLatency),
      leaveLatencyByStream: leaveLatencyByStream ?? this.leaveLatencyByStream,
      expectedDscp: expectedDscp ?? this.expectedDscp,
      receivedDscp: receivedDscp ?? this.receivedDscp,
      receivedTosByte: receivedTosByte ?? this.receivedTosByte,
      packetHintDscp: packetHintDscp ?? this.packetHintDscp,
      senderDscpPreset: senderDscpPreset ?? this.senderDscpPreset,
      dscpTransitStatus: dscpTransitStatus ?? this.dscpTransitStatus,
      dscpVerifiedByOsTos: dscpVerifiedByOsTos ?? this.dscpVerifiedByOsTos,
    );
  }
}

class UnsubscribedStreamInfo {
  final String groupAddress;
  final int port;
  final String sourceIp;
  final String sessionId;
  final int packetsReceived;
  final int bytesReceived;
  final double currentPps;
  final double currentBitrateMbps;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const UnsubscribedStreamInfo({
    required this.groupAddress,
    required this.port,
    required this.sourceIp,
    required this.sessionId,
    required this.packetsReceived,
    required this.bytesReceived,
    this.currentPps = 0.0,
    this.currentBitrateMbps = 0.0,
    required this.firstSeen,
    required this.lastSeen,
  });

  String get endpoint => '$groupAddress:$port';

  UnsubscribedStreamInfo copyWith({
    String? groupAddress,
    int? port,
    String? sourceIp,
    String? sessionId,
    int? packetsReceived,
    int? bytesReceived,
    double? currentPps,
    double? currentBitrateMbps,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) {
    return UnsubscribedStreamInfo(
      groupAddress: groupAddress ?? this.groupAddress,
      port: port ?? this.port,
      sourceIp: sourceIp ?? this.sourceIp,
      sessionId: sessionId ?? this.sessionId,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      currentPps: currentPps ?? this.currentPps,
      currentBitrateMbps: currentBitrateMbps ?? this.currentBitrateMbps,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
