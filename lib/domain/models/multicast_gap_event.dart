class MulticastGapEvent {
  final int id;
  final String sessionId;
  final String streamName;
  final String groupAddress;
  final int port;
  final DateTime timestamp;
  final int startSeq;
  final int endSeq;
  final int missingPackets;
  final Duration gapDuration;
  final DateTime lastPacketTime;
  final DateTime resumedTime;

  const MulticastGapEvent({
    required this.id,
    required this.sessionId,
    this.streamName = 'Stream',
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    required this.timestamp,
    required this.startSeq,
    required this.endSeq,
    required this.missingPackets,
    required this.gapDuration,
    required this.lastPacketTime,
    required this.resumedTime,
  });

  String get endpoint => '$groupAddress:$port';

  double get gapDurationMs =>
      gapDuration.inMicroseconds / 1000.0;

  String get sequenceRange =>
      missingPackets == 1 ? '#$startSeq' : '#$startSeq – #$endSeq';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'streamName': streamName,
      'groupAddress': groupAddress,
      'port': port,
      'timestamp': timestamp.toIso8601String(),
      'startSeq': startSeq,
      'endSeq': endSeq,
      'missingPackets': missingPackets,
      'gapDurationMs': gapDurationMs,
      'lastPacketTime': lastPacketTime.toIso8601String(),
      'resumedTime': resumedTime.toIso8601String(),
    };
  }
}
