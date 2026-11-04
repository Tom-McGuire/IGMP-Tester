import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';

void main() {
  group('ProtocolPreset Tests', () {
    test('all presets have valid configuration within ethernet limits', () {
      expect(ProtocolPreset.all, isNotEmpty);

      for (final preset in ProtocolPreset.all) {
        expect(preset.id, isNotEmpty);
        expect(preset.name, isNotEmpty);
        expect(preset.category, isNotEmpty);
        expect(preset.description, isNotEmpty);
        expect(MulticastStreamConfig.isValidMulticastIpv4(preset.defaultGroup), isTrue);
        expect(preset.defaultPort, inInclusiveRange(1, 65535));
        expect(preset.packetsPerSecond, inInclusiveRange(1, 5000));
        expect(preset.packetSizeBytes, inInclusiveRange(56, 1472));
        expect(preset.defaultTtl, inInclusiveRange(1, 255));
        expect(preset.approximateBitrateMbps, greaterThan(0));
      }
    });

    test('lighting and audio presets have accurate protocol properties', () {
      // sACN
      expect(ProtocolPreset.sacn.defaultPort, equals(5568));
      expect(ProtocolPreset.sacn.packetsPerSecond, equals(44));
      expect(ProtocolPreset.sacn.packetSizeBytes, equals(638));
      expect(ProtocolPreset.sacn.category, equals('Lighting'));

      // Dante 1ms
      expect(ProtocolPreset.dante1ms.defaultPort, equals(5004));
      expect(ProtocolPreset.dante1ms.packetsPerSecond, equals(1000));
      expect(ProtocolPreset.dante1ms.category, equals('Audio'));

      // Dante 0.25ms
      expect(ProtocolPreset.danteLowLatency.packetsPerSecond, equals(4000));

      // NDI
      expect(ProtocolPreset.ndiVideo.defaultPort, equals(5960));
      expect(ProtocolPreset.ndiVideo.category, equals('Video'));
    });
  });
}
