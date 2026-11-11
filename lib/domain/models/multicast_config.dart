import 'network_interface_info.dart';

enum MulticastPreset {
  orgLocal('239.255.0.1', 5004, 'Admin / Org-Local (239.255.0.1)'),
  siteLocal('239.192.0.1', 5004, 'Site-Local (239.192.0.1)'),
  multicastTestGroup('239.1.1.1', 5004, 'IGMP Test Stream (239.1.1.1)'),
  custom('', 5004, 'Custom Multicast Group');

  final String group;
  final int port;
  final String label;

  const MulticastPreset(this.group, this.port, this.label);
}

/// Pre-configured multicast protocol profiles for common AV, broadcast, and lighting protocols.
class ProtocolPreset {
  final String id;
  final String name;
  final String category; // 'Lighting', 'Audio', 'Video', 'General'
  final String defaultGroup;
  final int defaultPort;
  final int packetsPerSecond;
  final int packetSizeBytes;
  final int defaultTtl;
  final String description;

  const ProtocolPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultGroup,
    required this.defaultPort,
    required this.packetsPerSecond,
    required this.packetSizeBytes,
    this.defaultTtl = 64,
    required this.description,
  });

  /// Approximate data bitrate in Mbps: (pps * size * 8) / 1,000,000
  double get approximateBitrateMbps =>
      (packetsPerSecond * packetSizeBytes * 8) / 1000000.0;

  static const List<ProtocolPreset> all = [
    custom,
    sacn,
    dante1ms,
    danteLowLatency,
    ndiVideo,
    st2110Video,
    artnet,
  ];

  static const custom = ProtocolPreset(
    id: 'custom',
    name: 'Custom / Synthetic Saturation',
    category: 'General',
    defaultGroup: '239.255.0.1',
    defaultPort: 5004,
    packetsPerSecond: 50,
    packetSizeBytes: 256,
    defaultTtl: 64,
    description: 'Custom rates and packet sizes for arbitrary multicast testing',
  );

  static const sacn = ProtocolPreset(
    id: 'sacn',
    name: 'sACN (ANSI E1.31) — Lighting',
    category: 'Lighting',
    defaultGroup: '239.255.0.1',
    defaultPort: 5568,
    packetsPerSecond: 44,
    packetSizeBytes: 638,
    defaultTtl: 64,
    description: 'DMX-over-Ethernet lighting (Universe 1, 44 pps, 638 bytes, ~0.22 Mbps)',
  );

  static const dante1ms = ProtocolPreset(
    id: 'dante_1ms',
    name: 'Dante / AES67 Audio (1ms latency)',
    category: 'Audio',
    defaultGroup: '239.69.1.1',
    defaultPort: 5004,
    packetsPerSecond: 1000,
    packetSizeBytes: 200,
    defaultTtl: 64,
    description: 'Uncompressed audio (48kHz 24-bit, 1ms packet time, 1,000 pps, ~1.6 Mbps)',
  );

  static const danteLowLatency = ProtocolPreset(
    id: 'dante_low_latency',
    name: 'Dante / AES67 Audio (0.25ms latency)',
    category: 'Audio',
    defaultGroup: '239.69.1.1',
    defaultPort: 5004,
    packetsPerSecond: 4000,
    packetSizeBytes: 100,
    defaultTtl: 64,
    description: 'Ultra-low latency audio (250µs packet time, 4,000 pps, ~3.2 Mbps)',
  );

  static const ndiVideo = ProtocolPreset(
    id: 'ndi',
    name: 'NDI / Compressed HD Video',
    category: 'Video',
    defaultGroup: '239.255.0.1',
    defaultPort: 5960,
    packetsPerSecond: 1200,
    packetSizeBytes: 1450,
    defaultTtl: 64,
    description: 'Network Device Interface video stream (~14 Mbps, 1,450 bytes)',
  );

  static const st2110Video = ProtocolPreset(
    id: 'st2110',
    name: 'SMPTE ST 2110 Video Saturation',
    category: 'Video',
    defaultGroup: '239.255.0.1',
    defaultPort: 5004,
    packetsPerSecond: 5000,
    packetSizeBytes: 1450,
    defaultTtl: 64,
    description: 'High-bandwidth broadcast video saturation (~58 Mbps, 5,000 pps)',
  );

  static const artnet = ProtocolPreset(
    id: 'artnet',
    name: 'Art-Net DMX Lighting',
    category: 'Lighting',
    defaultGroup: '239.255.0.1',
    defaultPort: 6454,
    packetsPerSecond: 40,
    packetSizeBytes: 530,
    defaultTtl: 64,
    description: 'Art-Net DMX lighting stream (40 pps, 530 bytes, ~0.17 Mbps)',
  );
}

class MulticastStreamConfig {
  final String id;
  final String name;
  final String groupAddress;
  final int port;
  final int packetsPerSecond;
  final int packetSizeBytes;
  final int ttl;
  final bool enabled;

  const MulticastStreamConfig({
    required this.id,
    required this.name,
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    this.packetsPerSecond = 50,
    this.packetSizeBytes = 256,
    this.ttl = 64,
    this.enabled = true,
  });

  String get endpoint => '$groupAddress:$port';

  MulticastStreamConfig copyWith({
    String? id,
    String? name,
    String? groupAddress,
    int? port,
    int? packetsPerSecond,
    int? packetSizeBytes,
    int? ttl,
    bool? enabled,
  }) {
    return MulticastStreamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      groupAddress: groupAddress ?? this.groupAddress,
      port: (port ?? this.port).clamp(1, 65535),
      packetsPerSecond: (packetsPerSecond ?? this.packetsPerSecond).clamp(1, 5000),
      packetSizeBytes: (packetSizeBytes ?? this.packetSizeBytes).clamp(56, 1472),
      ttl: (ttl ?? this.ttl).clamp(1, 255),
      enabled: enabled ?? this.enabled,
    );
  }

  static bool isValidMulticastIpv4(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null)) return false;
    if (octets[0]! < 224 || octets[0]! > 239) return false;
    for (int i = 1; i < 4; i++) {
      if (octets[i]! < 0 || octets[i]! > 255) return false;
    }
    return true;
  }

  static const int minMulticastIpInt = 0xE0000000;
  static const int maxMulticastIpInt = 0xEFFFFFFF;

  static String incrementIp(String ip, int increment) {
    if (!isValidMulticastIpv4(ip)) return ip;
    final parts = ip.trim().split('.').map(int.parse).toList();
    int intVal = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    intVal += increment;
    if (intVal < minMulticastIpInt) intVal = minMulticastIpInt;
    if (intVal > maxMulticastIpInt) intVal = maxMulticastIpInt;
    return '${(intVal >> 24) & 0xFF}.${(intVal >> 16) & 0xFF}.${(intVal >> 8) & 0xFF}.${intVal & 0xFF}';
  }
}

class MulticastReceiverStreamConfig {
  final String id;
  final String name;
  final String groupAddress;
  final int port;
  final bool enabled;
  final bool joinGroup;

  const MulticastReceiverStreamConfig({
    required this.id,
    required this.name,
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    this.enabled = true,
    this.joinGroup = true,
  });

  String get endpoint => '$groupAddress:$port';

  MulticastReceiverStreamConfig copyWith({
    String? id,
    String? name,
    String? groupAddress,
    int? port,
    bool? enabled,
    bool? joinGroup,
  }) {
    return MulticastReceiverStreamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      groupAddress: groupAddress ?? this.groupAddress,
      port: (port ?? this.port).clamp(1, 65535),
      enabled: enabled ?? this.enabled,
      joinGroup: joinGroup ?? this.joinGroup,
    );
  }
}

class MulticastSenderConfig {
  final NetworkInterfaceInfo? interface;
  final bool enableLoopback;
  final List<MulticastStreamConfig> streams;

  const MulticastSenderConfig({
    this.interface,
    this.enableLoopback = true,
    this.streams = const [
      MulticastStreamConfig(
        id: 'stream_1',
        name: 'Stream 1',
        groupAddress: '239.255.0.1',
        port: 5004,
        packetsPerSecond: 50,
        packetSizeBytes: 256,
        ttl: 64,
        enabled: true,
      ),
    ],
  });

  MulticastSenderConfig copyWith({
    NetworkInterfaceInfo? interface,
    bool? enableLoopback,
    List<MulticastStreamConfig>? streams,
  }) {
    return MulticastSenderConfig(
      interface: interface ?? this.interface,
      enableLoopback: enableLoopback ?? this.enableLoopback,
      streams: streams ?? this.streams,
    );
  }
}

class MulticastReceiverConfig {
  final NetworkInterfaceInfo? interface;
  final bool enableLoopback;
  final bool passiveListenOnly;
  final int passiveListenPort;
  final List<MulticastReceiverStreamConfig> streams;

  const MulticastReceiverConfig({
    this.interface,
    this.enableLoopback = true,
    this.passiveListenOnly = false,
    this.passiveListenPort = 5004,
    this.streams = const [
      MulticastReceiverStreamConfig(
        id: 'rx_stream_1',
        name: 'Group 1',
        groupAddress: '239.255.0.1',
        port: 5004,
        enabled: true,
      ),
    ],
  });

  MulticastReceiverConfig copyWith({
    NetworkInterfaceInfo? interface,
    bool? enableLoopback,
    bool? passiveListenOnly,
    int? passiveListenPort,
    List<MulticastReceiverStreamConfig>? streams,
  }) {
    return MulticastReceiverConfig(
      interface: interface ?? this.interface,
      enableLoopback: enableLoopback ?? this.enableLoopback,
      passiveListenOnly: passiveListenOnly ?? this.passiveListenOnly,
      passiveListenPort: (passiveListenPort ?? this.passiveListenPort).clamp(1, 65535),
      streams: streams ?? this.streams,
    );
  }
}
