import 'dart:convert';
import 'dart:typed_data';

class MulticastPacket {
  static const String magicHeader = 'IGMPTEST';
  static const int minHeaderSize = 50;

  final int version;
  final int flags;
  final String sessionId; // 16 chars or UUID
  final int sequenceNumber;
  final int sendTimestampUs; // Microseconds since epoch
  final int configuredIntervalUs;
  final int payloadSize;
  final Uint8List payload;

  MulticastPacket({
    this.version = 1,
    this.flags = 0,
    required this.sessionId,
    required this.sequenceNumber,
    required this.sendTimestampUs,
    this.configuredIntervalUs = 20000,
    required this.payloadSize,
    Uint8List? payload,
  }) : payload = payload ?? Uint8List(0);

  DateTime get sendDateTime =>
      DateTime.fromMicrosecondsSinceEpoch(sendTimestampUs);

  Uint8List encode() {
    final totalSize = payloadSize < minHeaderSize ? minHeaderSize : payloadSize;
    final buffer = Uint8List(totalSize);
    final byteData = ByteData.sublistView(buffer);

    // 0..7 Magic 'IGMPTEST'
    final magicBytes = ascii.encode(magicHeader);
    buffer.setRange(0, 8, magicBytes);

    // 8: Version
    byteData.setUint8(8, version);

    // 9: Flags
    byteData.setUint8(9, flags);

    // 10..25: Session ID (16 bytes ascii, padded or truncated)
    final sessionBytes = ascii.encode(sessionId);
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

    // 50+: Fill rest with repeating pattern (0xAA, 0x55, 0x00, 0xFF...)
    for (int i = minHeaderSize; i < totalSize; i++) {
      buffer[i] = (i % 256);
    }

    return buffer;
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
    final sequence = byteData.getUint64(26, Endian.big);
    final sendTimeUs = byteData.getInt64(34, Endian.big);
    final intervalUs = byteData.getUint32(42, Endian.big);
    final payloadSize = byteData.getUint32(46, Endian.big);

    return MulticastPacket(
      version: version,
      flags: flags,
      sessionId: rawSession,
      sequenceNumber: sequence,
      sendTimestampUs: sendTimeUs,
      configuredIntervalUs: intervalUs,
      payloadSize: payloadSize,
      payload: data.length > minHeaderSize ? data.sublist(minHeaderSize) : Uint8List(0),
    );
  }
}
