import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/domain/models/igmp_query_event.dart';

void main() {
  group('IgmpQuerierWatchdog Tests', () {
    late IgmpQuerierWatchdog watchdog;

    setUp(() {
      watchdog = IgmpQuerierWatchdog();
    });

    tearDown(() {
      watchdog.dispose();
    });

    test('initial state is idle with null querier IP and waiting message', () {
      final status = watchdog.currentStatus;
      expect(status.health, equals(QuerierHealth.idle));
      expect(status.querierIp, isNull);
      expect(status.secondsSinceLastQuery, isNull);
      expect(status.querierVersion, equals(IgmpProtocolVersion.unknown));
      expect(status.displayBadge, equals('Unknown'));
      expect(status.supportsSsm, isFalse);
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.unknown));
      expect(status.statusMessage, contains('Awaiting'));
    });

    test('recordQuery with active query transitions state to QuerierHealth.active', () async {
      final now = DateTime.now();
      final event = IgmpQueryEvent(
        timestamp: now,
        querierIp: '192.168.1.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'IGMP General Query',
      );

      expect(event.isQuery, isTrue);
      expect(event.isGeneralQuery, isTrue);

      watchdog.recordQuery(event);

      final status = watchdog.currentStatus;
      expect(status.health, equals(QuerierHealth.active));
      expect(status.querierIp, equals('192.168.1.1'));
      expect(status.secondsSinceLastQuery, inInclusiveRange(0, 1));
      expect(status.querierVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(status.displayBadge, equals('IGMPv2'));
      expect(status.supportsSsm, isFalse);
      expect(status.statusMessage, contains('active'));
    });

    test('recordQuery ignores non-query packets (e.g. V2 report / leave)', () {
      final nonQueryEvent = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.100',
        destinationIp: '239.255.0.1',
        typeHex: '0x16',
        typeName: 'V2 Membership Report',
        groupAddress: '239.255.0.1',
        maxRespTimeSeconds: 0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'IGMP Join',
      );

      expect(nonQueryEvent.isQuery, isFalse);

      watchdog.recordQuery(nonQueryEvent);

      final status = watchdog.currentStatus;
      expect(status.health, equals(QuerierHealth.idle));
      expect(status.querierIp, isNull);
      expect(status.querierVersion, equals(IgmpProtocolVersion.unknown));
    });

    test('status transitions to warning between 126 and 260 seconds', () {
      final oldQueryTime = DateTime.now().subtract(const Duration(seconds: 150));
      final event = IgmpQueryEvent(
        timestamp: oldQueryTime,
        querierIp: '10.0.0.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'IGMP General Query',
      );

      watchdog.recordQuery(event);

      final status = watchdog.currentStatus;
      expect(status.health, equals(QuerierHealth.warning));
      expect(status.querierVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(status.displayBadge, equals('IGMPv2'));
      expect(status.statusMessage, contains('Warning'));
      expect(status.statusMessage, contains('late'));
      expect(status.statusMessage, contains('IGMPv2'));
      expect(status.secondsSinceLastQuery, greaterThanOrEqualTo(150));
    });

    test('status transitions to critical when elapsed time exceeds 260 seconds and resets version', () {
      final oldQueryTime = DateTime.now().subtract(const Duration(seconds: 300));
      final event = IgmpQueryEvent(
        timestamp: oldQueryTime,
        querierIp: '10.0.0.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv3',
        protocolVersion: IgmpProtocolVersion.igmpv3,
        interfaceName: 'eth0',
        rawSummary: 'IGMPv3 General Query',
      );

      watchdog.recordQuery(event);

      final status = watchdog.currentStatus;
      expect(status.health, equals(QuerierHealth.critical));
      expect(status.querierVersion, equals(IgmpProtocolVersion.unknown));
      expect(status.displayBadge, equals('Unknown'));
      expect(status.supportsSsm, isFalse);
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.unknown));
      expect(status.statusMessage, contains('Critical'));
      expect(status.statusMessage, contains('pruned'));
    });

    test('reset reverts state to idle and clears querier IP and version', () {
      final event = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '172.16.0.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv3',
        protocolVersion: IgmpProtocolVersion.igmpv3,
        interfaceName: 'eth0',
        rawSummary: 'Query',
      );

      watchdog.recordQuery(event);
      expect(watchdog.currentStatus.health, equals(QuerierHealth.active));
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.igmpv3));

      watchdog.reset();
      expect(watchdog.currentStatus.health, equals(QuerierHealth.idle));
      expect(watchdog.currentStatus.querierIp, isNull);
      expect(watchdog.currentStatus.querierVersion, equals(IgmpProtocolVersion.unknown));
      expect(watchdog.currentStatus.displayBadge, equals('Unknown'));
      expect(watchdog.currentStatus.supportsSsm, isFalse);
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.unknown));
      expect(watchdog.currentStatus.statusMessage, contains('Waiting for network IGMP Queries'));
    });

    test('statusStream emits updates when recordQuery and reset are called', () async {
      final statuses = <QuerierStatus>[];
      final sub = watchdog.statusStream.listen((s) => statuses.add(s));

      final event = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '192.168.1.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'Membership Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'Query',
      );

      watchdog.recordQuery(event);
      watchdog.reset();

      await Future.delayed(const Duration(milliseconds: 10));
      expect(statuses.length, greaterThanOrEqualTo(2));
      expect(statuses[0].health, equals(QuerierHealth.active));
      expect(statuses[0].querierVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(statuses[1].health, equals(QuerierHealth.idle));
      expect(statuses[1].querierVersion, equals(IgmpProtocolVersion.unknown));

      await sub.cancel();
    });

    test('tracks detectedQuerierVersion across IGMPv1, IGMPv2, and IGMPv3 queries without interference from reports', () {
      final now = DateTime.now();

      // IGMPv1 Query
      watchdog.recordQuery(IgmpQueryEvent(
        timestamp: now,
        querierIp: '10.0.0.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'General Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 0.0,
        version: 'IGMPv1',
        protocolVersion: IgmpProtocolVersion.igmpv1,
        interfaceName: 'eth0',
        rawSummary: 'v1 query',
      ));
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.igmpv1));
      expect(watchdog.currentStatus.displayBadge, equals('IGMPv1'));
      expect(watchdog.currentStatus.supportsSsm, isFalse);

      // IGMPv3 Query
      watchdog.recordQuery(IgmpQueryEvent(
        timestamp: now,
        querierIp: '10.0.0.1',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'General Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv3',
        protocolVersion: IgmpProtocolVersion.igmpv3,
        qrv: 2,
        qqicSeconds: 125,
        interfaceName: 'eth0',
        rawSummary: 'v3 query',
      ));
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(watchdog.currentStatus.displayBadge, equals('IGMPv3'));
      expect(watchdog.currentStatus.supportsSsm, isTrue);
      expect(watchdog.currentStatus.statusMessage, contains('IGMPv3'));

      // Host IGMPv2 Report should NOT downgrade detected querier version
      watchdog.recordQuery(IgmpQueryEvent(
        timestamp: now,
        querierIp: '10.0.0.99',
        destinationIp: '239.1.1.1',
        typeHex: '0x16',
        typeName: 'IGMPv2 Report',
        groupAddress: '239.1.1.1',
        maxRespTimeSeconds: 0.0,
        version: 'IGMPv2',
        interfaceName: 'eth0',
        rawSummary: 'v2 report',
      ));
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.igmpv3));
      expect(watchdog.currentStatus.querierIp, equals('10.0.0.1'));
      expect(watchdog.currentStatus.supportsSsm, isTrue);

      // Switch querier downgrades to IGMPv2 Query
      watchdog.recordQuery(IgmpQueryEvent(
        timestamp: now,
        querierIp: '10.0.0.2',
        destinationIp: '224.0.0.1',
        typeHex: '0x11',
        typeName: 'General Query',
        groupAddress: '0.0.0.0',
        maxRespTimeSeconds: 10.0,
        version: 'IGMPv2',
        protocolVersion: IgmpProtocolVersion.igmpv2,
        interfaceName: 'eth0',
        rawSummary: 'v2 query',
      ));
      expect(watchdog.detectedQuerierVersion, equals(IgmpProtocolVersion.igmpv2));
      expect(watchdog.currentStatus.querierIp, equals('10.0.0.2'));
      expect(watchdog.currentStatus.displayBadge, equals('IGMPv2'));
      expect(watchdog.currentStatus.supportsSsm, isFalse);
    });
  });
}
