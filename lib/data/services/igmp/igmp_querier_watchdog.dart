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
  final String statusMessage;

  const QuerierStatus({
    this.health = QuerierHealth.idle,
    this.secondsSinceLastQuery,
    this.querierIp,
    this.statusMessage = 'Awaiting IGMP Query...',
  });
}

class IgmpQuerierWatchdog {
  Timer? _timer;
  DateTime? _lastQueryTime;
  String? _querierIp;

  final _statusController = StreamController<QuerierStatus>.broadcast();
  Stream<QuerierStatus> get statusStream => _statusController.stream;

  QuerierStatus _currentStatus = const QuerierStatus();
  QuerierStatus get currentStatus => _currentStatus;

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
      _evaluate();
    }
  }

  void _evaluate() {
    if (_lastQueryTime == null) {
      _currentStatus = const QuerierStatus(
        health: QuerierHealth.idle,
        statusMessage: 'Waiting for network IGMP Queries (typical querier interval: 60s–125s)',
      );
      _statusController.add(_currentStatus);
      return;
    }

    final diffSeconds = DateTime.now().difference(_lastQueryTime!).inSeconds;

    QuerierHealth health;
    String msg;

    if (diffSeconds <= 125) {
      health = QuerierHealth.active;
      msg = 'Querier $_querierIp active (last query ${diffSeconds}s ago)';
    } else if (diffSeconds <= 260) {
      health = QuerierHealth.warning;
      msg = 'Warning: Querier $_querierIp is late (${diffSeconds}s since last query)';
    } else {
      health = QuerierHealth.critical;
      msg = 'Critical: No IGMP query for ${diffSeconds}s! Multicast will be pruned by switches.';
    }

    _currentStatus = QuerierStatus(
      health: health,
      secondsSinceLastQuery: diffSeconds,
      querierIp: _querierIp,
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
    _evaluate();
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
