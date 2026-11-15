/// Represents a multicast (or unexpected UDP) stream detected on a passively
/// bound UDP socket without an active IGMP group membership join.
class FloodedStreamEntry {
  final String groupIp;
  final int destinationPort;
  final String sourceIp;
  final String detectedProtocol;
  final String? protocolDetail;
  final int packetCount;
  final int bytesReceived;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final double estimatedBitrateBps;
  final bool isAlreadyJoined;

  const FloodedStreamEntry({
    required this.groupIp,
    required this.destinationPort,
    required this.sourceIp,
    required this.detectedProtocol,
    this.protocolDetail,
    required this.packetCount,
    required this.bytesReceived,
    required this.firstSeen,
    required this.lastSeen,
    this.estimatedBitrateBps = 0.0,
    this.isAlreadyJoined = false,
  });

  /// Canonical endpoint label `<groupIp>:<destinationPort>`.
  String get endpoint => '$groupIp:$destinationPort';

  /// Unique aggregation key `(sourceIp, groupIp, destinationPort)`.
  String get streamKey => '$sourceIp|$groupIp|$destinationPort';

  /// Estimated bitrate in kilobits per second (kbps).
  double get estimatedBitrateKbps => estimatedBitrateBps / 1000.0;

  /// Estimated bitrate in megabits per second (Mbps).
  double get estimatedBitrateMbps => estimatedBitrateBps / 1000000.0;

  /// Observation window between [firstSeen] and [lastSeen].
  Duration get observationDuration => lastSeen.difference(firstSeen);

  /// Combined protocol and optional detail string (e.g., `sACN Univ 1`).
  String get protocolDisplay =>
      (protocolDetail != null && protocolDetail!.isNotEmpty)
          ? '$detectedProtocol $protocolDetail'
          : detectedProtocol;

  /// Human-readable bitrate formatting (`bps`, `kbps`, `Mbps`).
  String get formattedBitrate {
    if (estimatedBitrateBps >= 1000000.0) {
      return '${(estimatedBitrateBps / 1000000.0).toStringAsFixed(2)} Mbps';
    }
    if (estimatedBitrateBps >= 1000.0) {
      return '${(estimatedBitrateBps / 1000.0).toStringAsFixed(1)} kbps';
    }
    return '${estimatedBitrateBps.toStringAsFixed(0)} bps';
  }

  /// Human-readable byte counter formatting (`B`, `KB`, `MB`).
  String get formattedBytes {
    if (bytesReceived >= 1024 * 1024) {
      return '${(bytesReceived / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytesReceived >= 1024) {
      return '${(bytesReceived / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytesReceived B';
  }

  FloodedStreamEntry copyWith({
    String? groupIp,
    int? destinationPort,
    String? sourceIp,
    String? detectedProtocol,
    String? protocolDetail,
    bool clearProtocolDetail = false,
    int? packetCount,
    int? bytesReceived,
    DateTime? firstSeen,
    DateTime? lastSeen,
    double? estimatedBitrateBps,
    bool? isAlreadyJoined,
  }) {
    return FloodedStreamEntry(
      groupIp: groupIp ?? this.groupIp,
      destinationPort: destinationPort ?? this.destinationPort,
      sourceIp: sourceIp ?? this.sourceIp,
      detectedProtocol: detectedProtocol ?? this.detectedProtocol,
      protocolDetail:
          clearProtocolDetail ? null : (protocolDetail ?? this.protocolDetail),
      packetCount: packetCount ?? this.packetCount,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      estimatedBitrateBps: estimatedBitrateBps ?? this.estimatedBitrateBps,
      isAlreadyJoined: isAlreadyJoined ?? this.isAlreadyJoined,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FloodedStreamEntry &&
        other.groupIp == groupIp &&
        other.destinationPort == destinationPort &&
        other.sourceIp == sourceIp &&
        other.detectedProtocol == detectedProtocol &&
        other.protocolDetail == protocolDetail &&
        other.packetCount == packetCount &&
        other.bytesReceived == bytesReceived &&
        other.firstSeen == firstSeen &&
        other.lastSeen == lastSeen &&
        other.estimatedBitrateBps == estimatedBitrateBps &&
        other.isAlreadyJoined == isAlreadyJoined;
  }

  @override
  int get hashCode => Object.hash(
        groupIp,
        destinationPort,
        sourceIp,
        detectedProtocol,
        protocolDetail,
        packetCount,
        bytesReceived,
        firstSeen,
        lastSeen,
        estimatedBitrateBps,
        isAlreadyJoined,
      );

  @override
  String toString() {
    return 'FloodedStreamEntry(groupIp: $groupIp, port: $destinationPort, '
        'sourceIp: $sourceIp, protocol: $protocolDisplay, '
        'packets: $packetCount, bytes: $bytesReceived, '
        'bitrate: $formattedBitrate)';
  }
}
