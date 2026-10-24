import 'dart:io';
import '../../../domain/models/network_interface_info.dart';

class NetworkInterfaceService {
  List<NetworkInterface> _rawInterfaces = [];

  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final results = <NetworkInterfaceInfo>[];

    try {
      _rawInterfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );

      for (final iface in _rawInterfaces) {
        for (final addr in iface.addresses) {
          results.add(
            NetworkInterfaceInfo(
              name: iface.name,
              ip: addr.address,
              subnetMask: '255.255.255.0',
              prefixLength: 24,
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
