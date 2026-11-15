import 'dart:async';
import '../../../domain/models/igmp_query_event.dart';

enum QuerierHealth {
  active('Querier Active', 0xFF4CAF50),
  warning('Querier Late', 0xFFFF9800),
  critical('Querier Missing / Expired', 0xFFF44336),
  idle('Listening for Queries...', 0xFF9E9E9E);

  final String label;
  final int colorHex;
  const QuerierHealth(this.label, this.colorHex);
}

class QuerierStatus {
  final QuerierHealth health;
  final int? secondsSinceLastQuery;
  final String? querierIp;
  final IgmpProtocolVersion querierVersion;
  final String statusMessage;

  const QuerierStatus({
    this.health = QuerierHealth.idle,
    this.secondsSinceLastQuery,
    this.querierIp,
    this.querierVersion = IgmpProtocolVersion.unknown,
    this.statusMessage = 'Awaiting IGMP Query...',
  });

  /// Human-readable protocol badge label (e.g., 'IGMPv3', 'IGMPv2', 'IGMPv1', 'Unknown').
  String get displayBadge => querierVersion.label;

  /// Whether the detected querier supports IGMPv3 Source-Specific Multicast (SSM).
  bool get supportsSsm => querierVersion.supportsSsm;
}

class IgmpQuerierWatchdog {
  Timer? _timer;
  DateTime? _lastQueryTime;
  String? _querierIp;
  IgmpProtocolVersion _detectedQuerierVersion = IgmpProtocolVersion.unknown;

  final _statusController = StreamController<QuerierStatus>.broadcast();
  Stream<QuerierStatus> get statusStream => _statusController.stream;

  QuerierStatus _currentStatus = const QuerierStatus();
  QuerierStatus get currentStatus => _currentStatus;

  IgmpProtocolVersion get detectedQuerierVersion => _detectedQuerierVersion;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _evaluate();
    });
  }

  void recordQuery(IgmpQueryEvent event) {
    if (event.isQuery) {
      _lastQueryTime = event.timestamp;
      _querierIp = event.querierIp;
      _detectedQuerierVersion = event.protocolVersion;
      _evaluate();
    }
  }

  void _evaluate() {
    if (_lastQueryTime == null) {
      _detectedQuerierVersion = IgmpProtocolVersion.unknown;
      _currentStatus = const QuerierStatus(
        health: QuerierHealth.idle,
        querierVersion: IgmpProtocolVersion.unknown,
        statusMessage:
            'Waiting for network IGMP Queries (typical querier interval: 60s–125s)',
      );
      _statusController.add(_currentStatus);
      return;
    }

    final diffSeconds = DateTime.now().difference(_lastQueryTime!).inSeconds;

    QuerierHealth health;
    String msg;

    if (diffSeconds <= 125) {
      health = QuerierHealth.active;
      final verTag = _detectedQuerierVersion != IgmpProtocolVersion.unknown
          ? ' (${_detectedQuerierVersion.label})'
          : '';
      msg = 'Querier $_querierIp$verTag active (last query ${diffSeconds}s ago)';
    } else if (diffSeconds <= 260) {
      health = QuerierHealth.warning;
      final verTag = _detectedQuerierVersion != IgmpProtocolVersion.unknown
          ? ' (${_detectedQuerierVersion.label})'
          : '';
      msg =
          'Warning: Querier $_querierIp$verTag is late (${diffSeconds}s since last query)';
    } else {
      health = QuerierHealth.critical;
      _detectedQuerierVersion = IgmpProtocolVersion.unknown;
      msg =
          'Critical: No IGMP query for ${diffSeconds}s! Multicast will be pruned by switches.';
    }

    _currentStatus = QuerierStatus(
      health: health,
      secondsSinceLastQuery: diffSeconds,
      querierIp: _querierIp,
      querierVersion: _detectedQuerierVersion,
      statusMessage: msg,
    );
    _statusController.add(_currentStatus);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    _lastQueryTime = null;
    _querierIp = null;
    _detectedQuerierVersion = IgmpProtocolVersion.unknown;
    _evaluate();
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
