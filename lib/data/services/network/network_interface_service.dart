import 'dart:io';
import '../../../domain/models/network_interface_info.dart';

class NetworkInterfaceService {
  List<NetworkInterface> _rawInterfaces = [];

  /// Infers a sensible CIDR prefix length from an IPv4 address when `dart:io`
  /// does not expose interface netmasks directly.
  static int inferPrefixLength(String ip) {
    final trimmed = ip.trim();
    if (trimmed == '0.0.0.0') return 0;

    final parts = trimmed.split('.');
    if (parts.length != 4) return 24;

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return 24;

    final o0 = octets[0]!;
    final o1 = octets[1]!;

    if (o0 == 0 && o1 == 0 && octets[2] == 0 && octets[3] == 0) return 0;
    if (o0 == 127) return 8;
    if (o0 == 169 && o1 == 254) return 16;
    if (o0 == 10) return 8;
    if (o0 == 172 && o1 >= 16 && o1 <= 31) return 12;
    if (o0 == 192 && o1 == 168) return 24;
    return 24;
  }

  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final results = <NetworkInterfaceInfo>[];

    try {
      _rawInterfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );

      for (final iface in _rawInterfaces) {
        for (final addr in iface.addresses) {
          final prefixLength = inferPrefixLength(addr.address);
          results.add(
            NetworkInterfaceInfo(
              name: iface.name,
              ip: addr.address,
              subnetMask: NetworkInterfaceInfo.prefixToSubnetMask(prefixLength),
              prefixLength: prefixLength,
            ),
          );
        }
      }
    } catch (_) {}

    if (results.isEmpty) {
      results.add(
        const NetworkInterfaceInfo(
          name: 'Default (Any)',
          ip: '0.0.0.0',
          subnetMask: '0.0.0.0',
          prefixLength: 0,
        ),
      );
    }

    return results;
  }

  /// Returns the underlying dart:io NetworkInterface instance matching the info
  NetworkInterface? findRawInterface(NetworkInterfaceInfo? info) {
    if (info == null || info.ip == '0.0.0.0') return null;
    for (final raw in _rawInterfaces) {
      if (raw.name == info.name) {
        for (final addr in raw.addresses) {
          if (addr.address == info.ip) {
            return raw;
          }
        }
      }
    }
    // Fallback by name
    for (final raw in _rawInterfaces) {
      if (raw.name == info.name) return raw;
    }
    return null;
  }
}
