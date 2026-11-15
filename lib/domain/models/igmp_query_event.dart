import 'dart:typed_data';

/// Protocol version detected for an IGMP packet or querier.
enum IgmpProtocolVersion {
  unknown('Unknown'),
  igmpv1('IGMPv1'),
  igmpv2('IGMPv2'),
  igmpv3('IGMPv3');

  final String label;
  const IgmpProtocolVersion(this.label);

  /// Whether this protocol version supports Source-Specific Multicast (SSM).
  bool get supportsSsm => this == IgmpProtocolVersion.igmpv3;

  /// Parses common tshark/wire version strings (e.g. "3", "v3", "IGMPv3").
  static IgmpProtocolVersion parse(String? raw) {
    if (raw == null) return IgmpProtocolVersion.unknown;
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    switch (normalized) {
      case '1':
      case 'v1':
      case 'igmpv1':
        return IgmpProtocolVersion.igmpv1;
      case '2':
      case 'v2':
      case 'igmpv2':
        return IgmpProtocolVersion.igmpv2;
      case '3':
      case 'v3':
      case 'igmpv3':
        return IgmpProtocolVersion.igmpv3;
      default:
        return IgmpProtocolVersion.unknown;
    }
  }
}

class IgmpQueryEvent {
  final DateTime timestamp;
  final String querierIp;
  final String destinationIp;
  final String typeHex;
  final String typeName;
  final String groupAddress;
  final double maxRespTimeSeconds;
  final String version;
  final String interfaceName;
  final String rawSummary;
  final IgmpProtocolVersion? _protocolVersion;
  final int? qrv;
  final int? qqicSeconds;
  final bool suppressRouterProcessing;
  final List<String> sourceAddresses;

  const IgmpQueryEvent({
    required this.timestamp,
    required this.querierIp,
    required this.destinationIp,
    required this.typeHex,
    required this.typeName,
    required this.groupAddress,
    required this.maxRespTimeSeconds,
    required this.version,
    required this.interfaceName,
    required this.rawSummary,
    IgmpProtocolVersion? protocolVersion,
    this.qrv,
    this.qqicSeconds,
    this.suppressRouterProcessing = false,
    this.sourceAddresses = const [],
  }) : _protocolVersion = protocolVersion ??
            (version == 'IGMPv1'
                ? IgmpProtocolVersion.igmpv1
                : version == 'IGMPv2'
                    ? IgmpProtocolVersion.igmpv2
                    : version == 'IGMPv3'
                        ? IgmpProtocolVersion.igmpv3
                        : null);

  /// Normalized IGMP protocol version, derived from [version] or [typeHex] when omitted.
  IgmpProtocolVersion get protocolVersion {
    if (_protocolVersion != null) return _protocolVersion;
    final parsed = IgmpProtocolVersion.parse(version);
    if (parsed != IgmpProtocolVersion.unknown) return parsed;
    switch (typeHex.toLowerCase()) {
      case '0x12':
        return IgmpProtocolVersion.igmpv1;
      case '0x16':
      case '0x17':
        return IgmpProtocolVersion.igmpv2;
      case '0x22':
        return IgmpProtocolVersion.igmpv3;
      default:
        return IgmpProtocolVersion.unknown;
    }
  }

  bool get isQuery =>
      typeHex == '0x11' ||
      typeName.toLowerCase().contains('query');

  bool get isGeneralQuery =>
      isQuery && (groupAddress == '0.0.0.0' || destinationIp == '224.0.0.1');

  /// Decodes an IGMPv3 8-bit Querier's Query Interval Code (QQIC) per RFC 3376 §4.1.7.
  ///
  /// Values `< 128` represent seconds directly; values `>= 128` encode a floating-point
  /// value `(mant | 0x10) << (exp + 3)`.
  static int decodeQqic(int raw) {
    final byte = raw & 0xFF;
    if (byte < 128) return byte;
    final exp = (byte >> 4) & 0x07;
    final mant = byte & 0x0F;
    return (mant | 0x10) << (exp + 3);
  }

  /// Decodes the 8-bit Max Resp Code field into seconds.
  ///
  /// For IGMPv1/v2 (`isV3 == false`), the field represents tenths of a second (`raw / 10.0`).
  /// For IGMPv3 (`isV3 == true`), values `< 128` are tenths of a second while values
  /// `>= 128` use the RFC 3376 §4.1.1 floating-point representation.
  static double decodeMaxRespSeconds(int raw, {required bool isV3}) {
    final byte = raw & 0xFF;
    if (!isV3 || byte < 128) {
      return byte / 10.0;
    }
    final exp = (byte >> 4) & 0x07;
    final mant = byte & 0x0F;
    return ((mant | 0x10) << (exp + 3)) / 10.0;
  }

  static String _formatIpv4(Uint8List bytes, int offset) {
    return '${bytes[offset]}.${bytes[offset + 1]}.${bytes[offset + 2]}.${bytes[offset + 3]}';
  }

  static String _hexByte(int value) {
    return '0x${(value & 0xFF).toRadixString(16).padLeft(2, '0')}';
  }

  /// Parses raw IGMP wire bytes (starting at the IGMP header, after the IPv4 header).
  ///
  /// Distinguishes IGMPv1 (`8` bytes, `maxRespCode == 0`), IGMPv2 (`8` bytes,
  /// `maxRespCode > 0`), and IGMPv3 (`>= 12` bytes) Membership Queries (`0x11`),
  /// as well as IGMPv1/v2/v3 reports and leaves. Returns `null` if truncated or invalid.
  static IgmpQueryEvent? fromRawIgmpBytes(
    Uint8List payload, {
    DateTime? timestamp,
    String querierIp = '',
    String? destinationIp,
    String interfaceName = '',
    String? rawSummary,
  }) {
    if (payload.length < 8) return null;

    final ts = timestamp ?? DateTime.now();
    final type = payload[0];
    final maxRespCode = payload[1];
    final typeHex = _hexByte(type);
    final summary = rawSummary ??
        payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

    if (type == 0x11) {
      final groupAddr = _formatIpv4(payload, 4);
      final resolvedDestIp =
          destinationIp ?? (groupAddr == '0.0.0.0' ? '224.0.0.1' : groupAddr);

      if (payload.length == 8) {
        final isV1 = maxRespCode == 0;
        final proto =
            isV1 ? IgmpProtocolVersion.igmpv1 : IgmpProtocolVersion.igmpv2;
        final typeName =
            groupAddr == '0.0.0.0' ? 'General Query' : 'Group-Specific Query';

        return IgmpQueryEvent(
          timestamp: ts,
          querierIp: querierIp,
          destinationIp: resolvedDestIp,
          typeHex: typeHex,
          typeName: typeName,
          groupAddress: groupAddr,
          maxRespTimeSeconds: decodeMaxRespSeconds(maxRespCode, isV3: false),
          version: proto.label,
          protocolVersion: proto,
          interfaceName: interfaceName,
          rawSummary: summary,
        );
      }

      if (payload.length < 12) {
        // Malformed query length between IGMPv2 (8 bytes) and IGMPv3 minimum (12 bytes).
        return null;
      }

      final suppress = (payload[8] & 0x08) != 0;
      final qrv = payload[8] & 0x07;
      final qqicSeconds = decodeQqic(payload[9]);
      final numSrc = (payload[10] << 8) | payload[11];

      final sources = <String>[];
      for (int i = 0; i < numSrc; i++) {
        final offset = 12 + (i * 4);
        if (offset + 4 > payload.length) break;
        sources.add(_formatIpv4(payload, offset));
      }

      final String typeName;
      if (groupAddr == '0.0.0.0') {
        typeName = 'General Query';
      } else if (sources.isNotEmpty) {
        typeName = 'Group-and-Source-Specific Query';
      } else {
        typeName = 'Group-Specific Query';
      }

      return IgmpQueryEvent(
        timestamp: ts,
        querierIp: querierIp,
        destinationIp: resolvedDestIp,
        typeHex: typeHex,
        typeName: typeName,
        groupAddress: groupAddr,
        maxRespTimeSeconds: decodeMaxRespSeconds(maxRespCode, isV3: true),
        version: IgmpProtocolVersion.igmpv3.label,
        protocolVersion: IgmpProtocolVersion.igmpv3,
        qrv: qrv,
        qqicSeconds: qqicSeconds,
        suppressRouterProcessing: suppress,
        sourceAddresses: List.unmodifiable(sources),
        interfaceName: interfaceName,
        rawSummary: summary,
      );
    }

    if (type == 0x12 || type == 0x16 || type == 0x17) {
      final groupAddr = _formatIpv4(payload, 4);
      final proto = type == 0x12
          ? IgmpProtocolVersion.igmpv1
          : IgmpProtocolVersion.igmpv2;
      final typeName = switch (type) {
        0x12 => 'IGMPv1 Report',
        0x16 => 'IGMPv2 Report',
        _ => 'IGMPv2 Leave',
      };
      final resolvedDestIp =
          destinationIp ?? (type == 0x17 ? '224.0.0.2' : groupAddr);

      return IgmpQueryEvent(
        timestamp: ts,
        querierIp: querierIp,
        destinationIp: resolvedDestIp,
        typeHex: typeHex,
        typeName: typeName,
        groupAddress: groupAddr,
        maxRespTimeSeconds: 0.0,
        version: proto.label,
        protocolVersion: proto,
        interfaceName: interfaceName,
        rawSummary: summary,
      );
    }

    if (type == 0x22) {
      final groupAddr = payload.length >= 16 ? _formatIpv4(payload, 12) : '';
      return IgmpQueryEvent(
        timestamp: ts,
        querierIp: querierIp,
        destinationIp: destinationIp ?? '224.0.0.22',
        typeHex: typeHex,
        typeName: 'IGMPv3 Report',
        groupAddress: groupAddr,
        maxRespTimeSeconds: 0.0,
        version: IgmpProtocolVersion.igmpv3.label,
        protocolVersion: IgmpProtocolVersion.igmpv3,
        interfaceName: interfaceName,
        rawSummary: summary,
      );
    }

    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'querierIp': querierIp,
      'destinationIp': destinationIp,
      'typeHex': typeHex,
      'typeName': typeName,
      'groupAddress': groupAddress,
      'maxRespTimeSeconds': maxRespTimeSeconds,
      'version': version,
      'protocolVersion': protocolVersion.name,
      'qrv': qrv,
      'qqicSeconds': qqicSeconds,
      'suppressRouterProcessing': suppressRouterProcessing,
      'sourceAddresses': sourceAddresses,
      'interfaceName': interfaceName,
      'rawSummary': rawSummary,
    };
  }
}
