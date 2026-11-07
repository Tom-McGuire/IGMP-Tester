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
      expect(status.statusMessage, contains('Warning'));
      expect(status.statusMessage, contains('late'));
      expect(status.secondsSinceLastQuery, greaterThanOrEqualTo(150));
    });

    test('status transitions to critical when elapsed time exceeds 260 seconds', () {
      final oldQueryTime = DateTime.now().subtract(const Duration(seconds: 300));
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
      expect(status.health, equals(QuerierHealth.critical));
      expect(status.statusMessage, contains('Critical'));
      expect(status.statusMessage, contains('pruned'));
    });

    test('reset reverts state to idle and clears querier IP', () {
      final event = IgmpQueryEvent(
        timestamp: DateTime.now(),
        querierIp: '172.16.0.1',
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
      expect(watchdog.currentStatus.health, equals(QuerierHealth.active));

      watchdog.reset();
      expect(watchdog.currentStatus.health, equals(QuerierHealth.idle));
      expect(watchdog.currentStatus.querierIp, isNull);
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
      expect(statuses[1].health, equals(QuerierHealth.idle));

      await sub.cancel();
    });
  });
}
