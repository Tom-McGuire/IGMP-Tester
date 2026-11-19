import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/network/network_interface_service.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';

void main() {
  group('NetworkInterfaceService Tests', () {
    test('inferPrefixLength and prefixToSubnetMask map IPv4 ranges accurately', () {
      const cases = <(String, int, String)>[
        ('127.0.0.1', 8, '255.0.0.0'),
        ('169.254.42.9', 16, '255.255.0.0'),
        ('10.20.30.40', 8, '255.0.0.0'),
        ('172.16.0.1', 12, '255.240.0.0'),
        ('172.31.255.4', 12, '255.240.0.0'),
        ('172.15.255.1', 24, '255.255.255.0'),
        ('172.32.0.1', 24, '255.255.255.0'),
        ('192.168.1.10', 24, '255.255.255.0'),
        ('0.0.0.0', 0, '0.0.0.0'),
      ];

      for (final (ip, expectedPrefix, expectedMask) in cases) {
        final prefix = NetworkInterfaceService.inferPrefixLength(ip);
        final mask = NetworkInterfaceInfo.prefixToSubnetMask(prefix);
        expect(prefix, equals(expectedPrefix), reason: 'Prefix mismatch for $ip');
        expect(mask, equals(expectedMask), reason: 'Mask mismatch for $ip');
      }
    });

    test('getAvailableInterfaces populates inferred prefixLength and subnetMask', () async {
      final service = NetworkInterfaceService();
      final interfaces = await service.getAvailableInterfaces();

      expect(interfaces, isNotEmpty);
      for (final iface in interfaces) {
        final expectedPrefix = NetworkInterfaceService.inferPrefixLength(iface.ip);
        expect(iface.prefixLength, equals(expectedPrefix));
        expect(
          iface.subnetMask,
          equals(NetworkInterfaceInfo.prefixToSubnetMask(expectedPrefix)),
        );
      }

      final loopback = interfaces.where((i) => i.ip == '127.0.0.1').toList();
      if (loopback.isNotEmpty) {
        expect(loopback.first.prefixLength, equals(8));
        expect(loopback.first.subnetMask, equals('255.0.0.0'));
      }
    });
  });
}
