import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/multicast/dscp_socket_helper.dart';
import 'package:igmp_tester/domain/models/dscp_preset.dart';

void main() {
  group('DscpPreset enum properties', () {
    test(
      'defines all 5 presets with exact DSCP values, TOS bytes, and labels',
      () {
        expect(DscpPreset.values, hasLength(5));

        expect(DscpPreset.bestEffort.dscpValue, equals(0));
        expect(DscpPreset.bestEffort.tosByte, equals(0));
        expect(DscpPreset.bestEffort.tosHex, equals('0x00'));
        expect(DscpPreset.bestEffort.shortName, equals('BE'));
        expect(DscpPreset.bestEffort.shortLabel, equals('BE (0)'));
        expect(
          DscpPreset.bestEffort.trafficClassDescription,
          equals('Best Effort / Default'),
        );
        expect(
          DscpPreset.bestEffort.label,
          equals('BE (0) — Best Effort / Default'),
        );
        expect(
          DscpPreset.bestEffort.dropdownLabel,
          equals(DscpPreset.bestEffort.label),
        );

        expect(DscpPreset.cs3.dscpValue, equals(24));
        expect(DscpPreset.cs3.tosByte, equals(96));
        expect(DscpPreset.cs3.tosHex, equals('0x60'));
        expect(DscpPreset.cs3.shortName, equals('CS3'));
        expect(DscpPreset.cs3.shortLabel, equals('CS3 (24)'));
        expect(
          DscpPreset.cs3.trafficClassDescription,
          equals('Call Signaling / Broadcast'),
        );
        expect(
          DscpPreset.cs3.label,
          equals('CS3 (24) — Call Signaling / Broadcast'),
        );
        expect(DscpPreset.cs3.dropdownLabel, equals(DscpPreset.cs3.label));

        expect(DscpPreset.af41.dscpValue, equals(34));
        expect(DscpPreset.af41.tosByte, equals(136));
        expect(DscpPreset.af41.tosHex, equals('0x88'));
        expect(DscpPreset.af41.shortName, equals('AF41'));
        expect(DscpPreset.af41.shortLabel, equals('AF41 (34)'));
        expect(DscpPreset.af41.trafficClassDescription, equals('Video / NDI'));
        expect(DscpPreset.af41.label, equals('AF41 (34) — Video / NDI'));
        expect(DscpPreset.af41.dropdownLabel, equals(DscpPreset.af41.label));

        expect(DscpPreset.ef.dscpValue, equals(46));
        expect(DscpPreset.ef.tosByte, equals(184));
        expect(DscpPreset.ef.tosHex, equals('0xB8'));
        expect(DscpPreset.ef.shortName, equals('EF'));
        expect(DscpPreset.ef.shortLabel, equals('EF (46)'));
        expect(
          DscpPreset.ef.trafficClassDescription,
          equals('Audio / AES67 / Dante'),
        );
        expect(DscpPreset.ef.label, equals('EF (46) — Audio / AES67 / Dante'));
        expect(DscpPreset.ef.dropdownLabel, equals(DscpPreset.ef.label));

        expect(DscpPreset.cs7.dscpValue, equals(56));
        expect(DscpPreset.cs7.tosByte, equals(224));
        expect(DscpPreset.cs7.tosHex, equals('0xE0'));
        expect(DscpPreset.cs7.shortName, equals('CS7'));
        expect(DscpPreset.cs7.shortLabel, equals('CS7 (56)'));
        expect(
          DscpPreset.cs7.trafficClassDescription,
          equals('PTPv2 / Network Control'),
        );
        expect(
          DscpPreset.cs7.label,
          equals('CS7 (56) — PTPv2 / Network Control'),
        );
        expect(DscpPreset.cs7.dropdownLabel, equals(DscpPreset.cs7.label));
      },
    );
  });

  group('DSCP / TOS codec helpers', () {
    test('encodeTosByte and extractDscpFromTos round-trip all 64 DSCP values and ECN bits 0..3', () {
      for (var dscp = 0; dscp <= 63; dscp++) {
        for (var ecn = 0; ecn <= 3; ecn++) {
          final tosByte = DscpPreset.encodeTosByte(dscp, ecn: ecn);
          expect(tosByte, inInclusiveRange(0, 255));
          expect(tosByte, equals((dscp << 2) | ecn));

          // Non-zero ECN bits (0x01, 0x02, 0x03) must not corrupt extracted DSCP
          expect(DscpPreset.extractDscpFromTos(tosByte), equals(dscp));
          expect(DscpPreset.extractEcnFromTos(tosByte), equals(ecn));
        }
      }
    });

    test(
      'exhaustive 8-bit TOS byte space 0..255 extracts clean 6-bit DSCP',
      () {
        for (var tos = 0; tos <= 255; tos++) {
          final dscp = DscpPreset.extractDscpFromTos(tos);
          final ecn = DscpPreset.extractEcnFromTos(tos);
          expect(dscp, inInclusiveRange(0, 63));
          expect(ecn, inInclusiveRange(0, 3));
          expect(DscpPreset.encodeTosByte(dscp, ecn: ecn), equals(tos));
        }
      },
    );

    test('encodeTosByte and extractDscpFromTos mask out-of-range high bits cleanly', () {
      expect(DscpPreset.encodeTosByte(0xFF, ecn: 0xFF), equals(0xFF));
      expect(DscpPreset.encodeTosByte(64, ecn: 4), equals(0));
      expect(DscpPreset.extractDscpFromTos(0xFFFF), equals(63));
      expect(DscpPreset.isValidDscp(0), isTrue);
      expect(DscpPreset.isValidDscp(63), isTrue);
      expect(DscpPreset.isValidDscp(-1), isFalse);
      expect(DscpPreset.isValidDscp(64), isFalse);
    });

    test('tryFromDscpValue and fromDscpValue resolve presets and handle unknown values', () {
      for (final preset in DscpPreset.values) {
        expect(DscpPreset.tryFromDscpValue(preset.dscpValue), equals(preset));
        expect(DscpPreset.fromDscpValue(preset.dscpValue), equals(preset));
      }

      expect(DscpPreset.tryFromDscpValue(18), isNull);
      expect(DscpPreset.tryFromDscpValue(-1), isNull);
      expect(DscpPreset.tryFromDscpValue(64), isNull);

      expect(DscpPreset.fromDscpValue(18), equals(DscpPreset.bestEffort));
      expect(
        DscpPreset.fromDscpValue(18, fallback: DscpPreset.af41),
        equals(DscpPreset.af41),
      );
    });

    test('tryFromTosByte and fromTosByte ignore lower 2 ECN bits', () {
      for (final preset in DscpPreset.values) {
        for (final ecn in const [0x00, 0x01, 0x02, 0x03]) {
          final tosWithEcn = preset.tosByte | ecn;
          expect(
            DscpPreset.tryFromTosByte(tosWithEcn),
            equals(preset),
            reason:
                'Failed for ${preset.shortName} with ECN=$ecn (TOS=$tosWithEcn)',
          );
          expect(DscpPreset.fromTosByte(tosWithEcn), equals(preset));
        }
      }

      // DSCP 18 (AF21) with ECN CE (0x03) -> 0x4B (75), not a preset
      final unknownTos = DscpPreset.encodeTosByte(18, ecn: 3);
      expect(DscpPreset.tryFromTosByte(unknownTos), isNull);
      expect(
        DscpPreset.fromTosByte(unknownTos, fallback: DscpPreset.ef),
        equals(DscpPreset.ef),
      );
    });

    test(
      'formatDscpBadge formats known presets and arbitrary DSCP values 0..63',
      () {
        expect(DscpPreset.formatDscpBadge(0), equals('BE (0)'));
        expect(DscpPreset.formatDscpBadge(24), equals('CS3 (24)'));
        expect(DscpPreset.formatDscpBadge(34), equals('AF41 (34)'));
        expect(DscpPreset.formatDscpBadge(46), equals('EF (46)'));
        expect(DscpPreset.formatDscpBadge(56), equals('CS7 (56)'));

        expect(DscpPreset.formatDscpBadge(18), equals('DSCP 18'));
        expect(DscpPreset.formatDscpBadge(1), equals('DSCP 1'));
        expect(DscpPreset.formatDscpBadge(63), equals('DSCP 63'));
      },
    );

    test('evaluateTransitStatus classifies unverified, preserved, remarked, and stripped-to-zero states', () {
      // Null / unverified cases
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 46, observedDscp: null),
        equals(DscpTransitStatus.unverified),
      );
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: null, observedDscp: 46),
        equals(DscpTransitStatus.unverified),
      );
      expect(
        DscpPreset.evaluateTransitStatus(
          expectedDscp: null,
          observedDscp: null,
        ),
        equals(DscpTransitStatus.unverified),
      );

      // Out-of-range values degrade safely to unverified
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: -1, observedDscp: 0),
        equals(DscpTransitStatus.unverified),
      );
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 46, observedDscp: 64),
        equals(DscpTransitStatus.unverified),
      );

      // Preserved (including 0 -> 0 and non-zero -> same non-zero)
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 0, observedDscp: 0),
        equals(DscpTransitStatus.preserved),
      );
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 46, observedDscp: 46),
        equals(DscpTransitStatus.preserved),
      );
      expect(DscpTransitStatus.preserved.isPreserved, isTrue);
      expect(DscpTransitStatus.preserved.isAlert, isFalse);

      // Expected Best Effort (0) arriving with non-zero DSCP is not treated as QoS stripping
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 0, observedDscp: 34),
        equals(DscpTransitStatus.unverified),
      );
      expect(DscpTransitStatus.unverified.isUnverified, isTrue);
      expect(DscpTransitStatus.unverified.isAlert, isFalse);

      // Remarked to a different non-zero DSCP
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 46, observedDscp: 24),
        equals(DscpTransitStatus.remarkedOrStripped),
      );
      expect(DscpTransitStatus.remarkedOrStripped.isAlert, isTrue);
      expect(DscpTransitStatus.remarkedOrStripped.isPreserved, isFalse);

      // Stripped to Best Effort 0
      expect(
        DscpPreset.evaluateTransitStatus(expectedDscp: 34, observedDscp: 0),
        equals(DscpTransitStatus.remarkedToZero),
      );
      expect(DscpTransitStatus.remarkedToZero.isAlert, isTrue);
      expect(DscpTransitStatus.remarkedToZero.isPreserved, isFalse);
    });
  });

  group('DscpSocketHelper null safety and cross-platform options', () {
    test('null socket calls return false / null without throwing', () {
      expect(DscpSocketHelper.applySenderDscp(null, 46), isFalse);
      expect(DscpSocketHelper.applySenderPreset(null, DscpPreset.ef), isFalse);
      expect(DscpSocketHelper.enableReceiveTos(null), isFalse);
      expect(DscpSocketHelper.readSocketTos(null), isNull);
      expect(DscpSocketHelper.readSocketDscp(null), isNull);

      final senderResult = DscpSocketHelper.applySenderDscpWithResult(null, 46);
      expect(senderResult.success, isFalse);
      expect(senderResult.appliedTosByte, isNull);
      expect(senderResult.appliedDscp, isNull);
      expect(senderResult.warningMessage, isNotEmpty);

      final presetResult = DscpSocketHelper.applySenderPresetWithResult(
        null,
        DscpPreset.af41,
      );
      expect(presetResult.success, isFalse);
      expect(presetResult.appliedTosByte, isNull);
      expect(presetResult.warningMessage, isNotEmpty);

      final recvResult = DscpSocketHelper.enableReceiveTosWithResult(null);
      expect(recvResult.success, isFalse);
      expect(recvResult.appliedTosByte, isNull);
      expect(recvResult.warningMessage, isNotEmpty);
    });

    test('invalid DSCP or ECN arguments fail safely with warning messages', () {
      final lowDscp = DscpSocketHelper.applySenderDscpWithResult(null, -1);
      expect(lowDscp.success, isFalse);
      expect(lowDscp.appliedTosByte, isNull);
      expect(lowDscp.warningMessage, contains('Invalid DSCP'));

      final highDscp = DscpSocketHelper.applySenderDscpWithResult(null, 64);
      expect(highDscp.success, isFalse);
      expect(highDscp.appliedTosByte, isNull);
      expect(highDscp.warningMessage, contains('Invalid DSCP'));

      final badEcn = DscpSocketHelper.applySenderDscpWithResult(
        null,
        46,
        ecn: 4,
      );
      expect(badEcn.success, isFalse);
      expect(badEcn.appliedTosByte, isNull);
      expect(badEcn.warningMessage, contains('Invalid ECN'));

      expect(DscpSocketHelper.buildSenderTosOption(-1), isNull);
      expect(DscpSocketHelper.buildSenderTosOption(64), isNull);
      expect(DscpSocketHelper.buildSenderTosOption(46, ecn: 4), isNull);
    });

    test('resolves exact IPPROTO_IP, IP_TOS, and IP_RECVTOS constants for Linux, macOS, and Windows', () {
      final linux = DscpSocketHelper.platformOptionsForOS('linux');
      expect(linux, isNotNull);
      expect(linux!.level, equals(0));
      expect(linux.ipTosOption, equals(1));
      expect(linux.ipRecvTosOption, equals(13));

      final macos = DscpSocketHelper.platformOptionsForOS('macos');
      expect(macos, isNotNull);
      expect(macos!.level, equals(0));
      expect(macos.ipTosOption, equals(3));
      expect(macos.ipRecvTosOption, equals(27));

      final windows = DscpSocketHelper.platformOptionsForOS('windows');
      expect(windows, isNotNull);
      expect(windows!.level, equals(0));
      expect(windows.ipTosOption, equals(3));
      expect(windows.ipRecvTosOption, equals(40));

      expect(DscpSocketHelper.platformOptionsForOS('fuchsia'), isNull);
      expect(DscpSocketHelper.platformOptionsForOS('unknown'), isNull);
    });

    test('buildSenderTosOption and buildReceiveTosOption construct host-endian RawSocketOptions', () {
      final linuxTos = DscpSocketHelper.buildSenderTosOption(
        DscpPreset.ef.dscpValue,
        operatingSystem: 'linux',
      );
      expect(linuxTos, isNotNull);
      expect(linuxTos!.level, equals(0));
      expect(linuxTos.option, equals(1));
      expect(
        ByteData.sublistView(linuxTos.value).getInt32(0, Endian.host),
        equals(184),
      );

      final macosTos = DscpSocketHelper.buildSenderTosOption(
        DscpPreset.af41.dscpValue,
        operatingSystem: 'macos',
      );
      expect(macosTos, isNotNull);
      expect(macosTos!.level, equals(0));
      expect(macosTos.option, equals(3));
      expect(
        ByteData.sublistView(macosTos.value).getInt32(0, Endian.host),
        equals(136),
      );

      final winRecvTos = DscpSocketHelper.buildReceiveTosOption(
        operatingSystem: 'windows',
      );
      expect(winRecvTos, isNotNull);
      expect(winRecvTos!.level, equals(0));
      expect(winRecvTos.option, equals(40));
      expect(
        ByteData.sublistView(winRecvTos.value).getInt32(0, Endian.host),
        equals(1),
      );

      expect(
        DscpSocketHelper.buildSenderTosOption(46, operatingSystem: 'unknown'),
        isNull,
      );
      expect(
        DscpSocketHelper.buildReceiveTosOption(operatingSystem: 'unknown'),
        isNull,
      );
    });

    test(
      'handles live and closed RawDatagramSocket safely without throwing',
      () async {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        try {
          final efResult = DscpSocketHelper.applySenderPresetWithResult(
            socket,
            DscpPreset.ef,
          );
          if (efResult.success) {
            expect(efResult.appliedTosByte, equals(184));
            expect(efResult.appliedDscp, equals(46));
            expect(efResult.warningMessage, isNull);
            final readBack = DscpSocketHelper.readSocketDscp(socket);
            if (readBack != null) {
              expect(readBack, equals(46));
            }
          } else {
            expect(efResult.appliedTosByte, isNull);
            expect(efResult.warningMessage, isNotEmpty);
          }

          // enableReceiveTos must never throw regardless of kernel/sandbox support
          final recvOk = DscpSocketHelper.enableReceiveTos(socket);
          expect(recvOk, isA<bool>());
        } finally {
          socket.close();
        }

        // Closed socket must fail gracefully without throwing
        expect(DscpSocketHelper.applySenderDscp(socket, 34), isFalse);
        expect(DscpSocketHelper.enableReceiveTos(socket), isFalse);
        expect(DscpSocketHelper.readSocketTos(socket), isNull);
      },
    );
  });
}
