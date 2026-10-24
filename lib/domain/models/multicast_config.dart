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

class MulticastSenderConfig {
  final String groupAddress;
  final int port;
  final NetworkInterfaceInfo? interface;
  final int packetsPerSecond;
  final int packetSizeBytes;
  final int ttl;
  final bool enableLoopback;
  final String sessionLabel;

  const MulticastSenderConfig({
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    this.interface,
    this.packetsPerSecond = 50,
    this.packetSizeBytes = 256,
    this.ttl = 64,
    this.enableLoopback = true,
    this.sessionLabel = 'IGMP-Stream',
  });

  MulticastSenderConfig copyWith({
    String? groupAddress,
    int? port,
    NetworkInterfaceInfo? interface,
    int? packetsPerSecond,
    int? packetSizeBytes,
    int? ttl,
    bool? enableLoopback,
    String? sessionLabel,
  }) {
    return MulticastSenderConfig(
      groupAddress: groupAddress ?? this.groupAddress,
      port: port ?? this.port,
      interface: interface ?? this.interface,
      packetsPerSecond: packetsPerSecond ?? this.packetsPerSecond,
      packetSizeBytes: packetSizeBytes ?? this.packetSizeBytes,
      ttl: ttl ?? this.ttl,
      enableLoopback: enableLoopback ?? this.enableLoopback,
      sessionLabel: sessionLabel ?? this.sessionLabel,
    );
  }
}

class MulticastReceiverConfig {
  final String groupAddress;
  final int port;
  final NetworkInterfaceInfo? interface;
  final bool enableLoopback;

  const MulticastReceiverConfig({
    this.groupAddress = '239.255.0.1',
    this.port = 5004,
    this.interface,
    this.enableLoopback = true,
  });

  MulticastReceiverConfig copyWith({
    String? groupAddress,
    int? port,
    NetworkInterfaceInfo? interface,
    bool? enableLoopback,
  }) {
    return MulticastReceiverConfig(
      groupAddress: groupAddress ?? this.groupAddress,
      port: port ?? this.port,
      interface: interface ?? this.interface,
      enableLoopback: enableLoopback ?? this.enableLoopback,
    );
  }
}
