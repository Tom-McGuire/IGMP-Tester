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

  const MulticastReceiverStreamConfig({
    required this.id,
    required this.name,
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    this.enabled = true,
  });

  String get endpoint => '$groupAddress:$port';

  MulticastReceiverStreamConfig copyWith({
    String? id,
    String? name,
    String? groupAddress,
    int? port,
    bool? enabled,
  }) {
    return MulticastReceiverStreamConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      groupAddress: groupAddress ?? this.groupAddress,
      port: (port ?? this.port).clamp(1, 65535),
      enabled: enabled ?? this.enabled,
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
  final List<MulticastReceiverStreamConfig> streams;

  const MulticastReceiverConfig({
    this.interface,
    this.enableLoopback = true,
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
    List<MulticastReceiverStreamConfig>? streams,
  }) {
    return MulticastReceiverConfig(
      interface: interface ?? this.interface,
      enableLoopback: enableLoopback ?? this.enableLoopback,
      streams: streams ?? this.streams,
    );
  }
}
