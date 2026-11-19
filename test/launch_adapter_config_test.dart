import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/launch_adapter_config.dart';
import 'package:igmp_tester/domain/models/network_interface_info.dart';

void main() {
  NetworkInterfaceInfo makeInterface({
    required String name,
    required String ip,
  }) {
    return NetworkInterfaceInfo(
      name: name,
      ip: ip,
      subnetMask: '255.255.255.0',
      prefixLength: 24,
    );
  }

  group('LaunchAdapterConfig.fromArgs', () {
    test('parses space-separated flags', () {
      final config = LaunchAdapterConfig.fromArgs([
        '--adapter-ip',
        '192.168.10.25',
        '--adapter-name',
        'Ethernet 2',
      ]);

      expect(config.adapterIp, equals('192.168.10.25'));
      expect(config.adapterName, equals('Ethernet 2'));
      expect(config.hasAdapterOverride, isTrue);
      expect(config.hasOverride, isTrue);
    });

    test('parses equals-separated flags', () {
      final config = LaunchAdapterConfig.fromArgs([
        '--adapter-ip=10.20.30.40',
        '--adapter-name=Wi-Fi',
      ]);

      expect(config.adapterIp, equals('10.20.30.40'));
      expect(config.adapterName, equals('Wi-Fi'));
      expect(config.hasAdapterOverride, isTrue);
      expect(config.hasOverride, isTrue);
    });

    test('trims surrounding whitespace on values', () {
      final spaced = LaunchAdapterConfig.fromArgs([
        '--adapter-ip',
        '  172.16.0.10 \t',
        '--adapter-name',
        '  eth0  ',
      ]);
      expect(spaced.adapterIp, equals('172.16.0.10'));
      expect(spaced.adapterName, equals('eth0'));

      final equalsForm = LaunchAdapterConfig.fromArgs([
        '--adapter-ip= 172.16.0.11 ',
        '--adapter-name=\ten1\n',
      ]);
      expect(equalsForm.adapterIp, equals('172.16.0.11'));
      expect(equalsForm.adapterName, equals('en1'));
    });

    test('normalizes empty and whitespace-only values to null', () {
      final spacedEmpty = LaunchAdapterConfig.fromArgs([
        '--adapter-ip',
        '   ',
        '--adapter-name',
        '',
      ]);
      expect(spacedEmpty.adapterIp, isNull);
      expect(spacedEmpty.adapterName, isNull);
      expect(spacedEmpty.hasAdapterOverride, isFalse);
      expect(spacedEmpty.hasOverride, isFalse);

      final equalsEmpty = LaunchAdapterConfig.fromArgs([
        '--adapter-ip=',
        '--adapter-name= \t ',
      ]);
      expect(equalsEmpty.adapterIp, isNull);
      expect(equalsEmpty.adapterName, isNull);
      expect(equalsEmpty.hasAdapterOverride, isFalse);
      expect(equalsEmpty.hasOverride, isFalse);
    });

    test('ignores trailing flag with missing value without throwing', () {
      final trailingIp = LaunchAdapterConfig.fromArgs(['--adapter-ip']);
      expect(trailingIp.adapterIp, isNull);
      expect(trailingIp.adapterName, isNull);
      expect(trailingIp.hasOverride, isFalse);

      final trailingNameAfterIp = LaunchAdapterConfig.fromArgs([
        '--adapter-ip',
        '192.168.1.5',
        '--adapter-name',
      ]);
      expect(trailingNameAfterIp.adapterIp, equals('192.168.1.5'));
      expect(trailingNameAfterIp.adapterName, isNull);
      expect(trailingNameAfterIp.hasOverride, isTrue);
    });

    test('ignores unknown flags and positional arguments', () {
      final config = LaunchAdapterConfig.fromArgs([
        '--verbose',
        'positional',
        '--unknown=value',
        '--adapter-name',
        'en0',
        '--other-flag',
        'other-val',
        '--adapter-ip=192.168.50.2',
      ]);

      expect(config.adapterIp, equals('192.168.50.2'));
      expect(config.adapterName, equals('en0'));
      expect(config.hasAdapterOverride, isTrue);
    });

    test(
      'hasAdapterOverride and hasOverride handle whitespace in direct ctor',
      () {
        const blank = LaunchAdapterConfig(adapterIp: '   ', adapterName: '\t');
        expect(blank.hasAdapterOverride, isFalse);
        expect(blank.hasOverride, isFalse);

        const ipOnly = LaunchAdapterConfig(adapterIp: '10.0.0.1');
        expect(ipOnly.hasAdapterOverride, isTrue);
        expect(ipOnly.hasOverride, isTrue);

        const nameOnly = LaunchAdapterConfig(adapterName: 'eth0');
        expect(nameOnly.hasAdapterOverride, isTrue);
        expect(nameOnly.hasOverride, isTrue);
      },
    );
  });

  group('LaunchAdapterConfig.selectInitialInterface', () {
    test('returns null when interface list is empty', () {
      const config = LaunchAdapterConfig(
        adapterIp: '192.168.1.10',
        adapterName: 'eth0',
      );
      expect(config.selectInitialInterface(const []), isNull);
    });

    test('Priority 1: exact IPv4 match wins over conflicting adapterName', () {
      final eth0 = makeInterface(name: 'eth0', ip: '192.168.1.10');
      final eth1 = makeInterface(name: 'eth1', ip: '10.0.0.55');
      final wlan0 = makeInterface(name: 'wlan0', ip: '172.16.1.20');

      const config = LaunchAdapterConfig(
        adapterIp: ' 10.0.0.55 ',
        adapterName: 'eth0',
      );

      expect(config.selectInitialInterface([eth0, eth1, wlan0]), equals(eth1));
    });

    test(
      'Priority 1: matches trimmed interface ip and falls through if unmatched',
      () {
        final eth0 = makeInterface(name: 'eth0', ip: ' 192.168.1.10 ');
        final eth1 = makeInterface(name: 'eth1', ip: '10.0.0.55');

        const ipMatched = LaunchAdapterConfig(adapterIp: '192.168.1.10');
        expect(ipMatched.selectInitialInterface([eth0, eth1]), equals(eth0));

        const ipUnmatchedNameMatched = LaunchAdapterConfig(
          adapterIp: '10.99.99.99',
          adapterName: 'eth1',
        );
        expect(
          ipUnmatchedNameMatched.selectInitialInterface([eth0, eth1]),
          equals(eth1),
        );
      },
    );

    test(
      'Priority 2: exact case-insensitive name match beats substring match',
      () {
        final vlan = makeInterface(name: 'eth0-vlan10', ip: '10.10.10.2');
        final exact = makeInterface(name: 'ETH0', ip: '192.168.1.5');

        const config = LaunchAdapterConfig(adapterName: 'eth0');
        expect(config.selectInitialInterface([vlan, exact]), equals(exact));
      },
    );

    test(
      'Priority 2: substring case-insensitive match works when exact absent',
      () {
        final eth0 = makeInterface(name: 'eth0', ip: '192.168.1.5');
        final wifi = makeInterface(
          name: 'Intel(R) Wi-Fi 6E AX211',
          ip: '192.168.1.25',
        );

        const config = LaunchAdapterConfig(adapterName: 'wi-fi 6e');
        expect(config.selectInitialInterface([eth0, wifi]), equals(wifi));
      },
    );

    test(
      'Priority 3: falls back to first non-loopback non-unspecified interface',
      () {
        final loopback = makeInterface(name: 'lo', ip: '127.0.0.1');
        final unspecified = makeInterface(name: 'any', ip: '0.0.0.0');
        final lan = makeInterface(name: 'eth0', ip: '192.168.1.50');
        final wifi = makeInterface(name: 'wlan0', ip: '192.168.1.51');

        const noOverride = LaunchAdapterConfig();
        expect(
          noOverride.selectInitialInterface([loopback, unspecified, lan, wifi]),
          equals(lan),
        );

        const unmatchedOverride = LaunchAdapterConfig(
          adapterIp: '203.0.113.9',
          adapterName: 'nonexistent',
        );
        expect(
          unmatchedOverride.selectInitialInterface([
            loopback,
            unspecified,
            lan,
            wifi,
          ]),
          equals(lan),
        );
      },
    );

    test('Priority 3: falls back to first interface when only loopback or 0.0.0.0 exists', () {
      final loopback = makeInterface(name: 'lo', ip: '127.0.0.1');
      final unspecified = makeInterface(name: 'any', ip: '0.0.0.0');

      const config = LaunchAdapterConfig(adapterName: 'missing');
      expect(
        config.selectInitialInterface([loopback, unspecified]),
        equals(loopback),
      );
    });
  });
}
