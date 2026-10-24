class NetworkInterfaceInfo {
  final String name;
  final String ip;
  final String subnetMask;
  final int prefixLength;

  const NetworkInterfaceInfo({
    required this.name,
    required this.ip,
    required this.subnetMask,
    required this.prefixLength,
  });

  String get displayName => '$name ($ip)';

  static String prefixToSubnetMask(int prefix) {
    if (prefix < 0 || prefix > 32) return '255.255.255.0';
    final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return '${(mask >> 24) & 0xFF}.${(mask >> 16) & 0xFF}.${(mask >> 8) & 0xFF}.${mask & 0xFF}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkInterfaceInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          ip == other.ip;

  @override
  int get hashCode => name.hashCode ^ ip.hashCode;
}
