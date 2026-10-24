import 'dart:convert';
import 'dart:typed_data';

class MulticastPacket {
  static const String magicHeader = 'IGMPTEST';
  static const int minHeaderSize = 56;

  final int version;
  final int flags;
  final String sessionId; // 16 chars sanitized alphanumeric/hex/hyphen
  final int sequenceNumber;
  final int sendTimestampUs; // Microseconds since epoch
  final int configuredIntervalUs;
  final int payloadSize;
  final String destinationGroup;
  final int destinationPort;
  final Uint8List payload;

  MulticastPacket({
    this.version = 1,
    this.flags = 0,
    required this.sessionId,
    required this.sequenceNumber,
    required this.sendTimestampUs,
    this.configuredIntervalUs = 20000,
    required this.payloadSize,
    this.destinationGroup = '239.255.0.1',
    this.destinationPort = 5004,
    Uint8List? payload,
  }) : payload = payload ?? Uint8List(0);

  DateTime get sendDateTime =>
      DateTime.fromMicrosecondsSinceEpoch(sendTimestampUs);

  static String sanitizeSessionId(String raw) {
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
  }

  Uint8List encode() {
    final totalSize = payloadSize < minHeaderSize ? minHeaderSize : payloadSize;
    final buffer = Uint8List(totalSize);
    final byteData = ByteData.sublistView(buffer);

    // 0..7: Magic 'IGMPTEST'
    final magicBytes = ascii.encode(magicHeader);
    buffer.setRange(0, 8, magicBytes);

    // 8: Version
    byteData.setUint8(8, version);

    // 9: Flags
    byteData.setUint8(9, flags);

    // 10..25: Session ID (16 bytes ascii, padded or truncated)
    final cleanSession = sanitizeSessionId(sessionId);
    final sessionBytes = ascii.encode(cleanSession);
    for (int i = 0; i < 16; i++) {
      buffer[10 + i] = i < sessionBytes.length ? sessionBytes[i] : 0x20;
    }

    // 26..33: Sequence number (uint64)
    byteData.setUint64(26, sequenceNumber, Endian.big);

    // 34..41: Send timestamp microseconds (int64)
    byteData.setInt64(34, sendTimestampUs, Endian.big);

    // 42..45: Configured interval microseconds (uint32)
    byteData.setUint32(42, configuredIntervalUs, Endian.big);

    // 46..49: Payload size (uint32)
    byteData.setUint32(46, totalSize, Endian.big);

    // 50..53: Destination IPv4 octets
    final octets = destinationGroup.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 4; i++) {
      buffer[50 + i] = (i < octets.length ? octets[i] : 0).clamp(0, 255);
    }

    // 54..55: Destination UDP Port (uint16)
    byteData.setUint16(54, destinationPort.clamp(1, 65535), Endian.big);

    // 56+: Fill rest with repeating pattern
    for (int i = minHeaderSize; i < totalSize; i++) {
      buffer[i] = (i % 256);
    }

    return buffer;
  }

  /// Fast in-place update of sequence number and timestamp on a pre-allocated template buffer
  static void updateSequenceAndTimestamp(Uint8List buffer, int sequence, int timestampUs) {
    final byteData = ByteData.sublistView(buffer);
    byteData.setUint64(26, sequence, Endian.big);
    byteData.setInt64(34, timestampUs, Endian.big);
  }

  static MulticastPacket? decode(Uint8List data) {
    if (data.length < minHeaderSize) return null;

    final byteData = ByteData.sublistView(data);

    // Check magic
    final magicBytes = data.sublist(0, 8);
    final magic = ascii.decode(magicBytes, allowInvalid: true);
    if (magic != magicHeader) return null;

    final version = byteData.getUint8(8);
    final flags = byteData.getUint8(9);

    final rawSession = ascii.decode(data.sublist(10, 26), allowInvalid: true).trim();
    final cleanSession = sanitizeSessionId(rawSession);
    final sequence = byteData.getUint64(26, Endian.big);
    final sendTimeUs = byteData.getInt64(34, Endian.big);
    final intervalUs = byteData.getUint32(42, Endian.big);
    final payloadSize = byteData.getUint32(46, Endian.big);

    final destGroup = '${data[50]}.${data[51]}.${data[52]}.${data[53]}';
    final destPort = byteData.getUint16(54, Endian.big);

    return MulticastPacket(
      version: version,
      flags: flags,
      sessionId: cleanSession,
      sequenceNumber: sequence,
      sendTimestampUs: sendTimeUs,
      configuredIntervalUs: intervalUs,
      payloadSize: payloadSize,
      destinationGroup: destGroup,
      destinationPort: destPort,
      payload: data.length > minHeaderSize ? data.sublist(minHeaderSize) : Uint8List(0),
    );
  }
}
