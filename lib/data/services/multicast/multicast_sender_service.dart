import 'dart:async';
import 'dart:io';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';

class MulticastSenderService {
  RawDatagramSocket? _socket;
  Timer? _sendTimer;
  Timer? _statsTimer;
  bool _isRunning = false;

  final _statsController = StreamController<SenderStats>.broadcast();
  Stream<SenderStats> get statsStream => _statsController.stream;

  SenderStats _currentStats = const SenderStats();
  SenderStats get currentStats => _currentStats;

  bool get isRunning => _isRunning;

  int _seq = 0;
  int _packetsSent = 0;
  int _bytesSent = 0;
  DateTime? _startTime;
  int _lastPacketsSnapshot = 0;
  int _lastBytesSnapshot = 0;
  DateTime? _lastSnapshotTime;

  Future<void> start({
    required MulticastSenderConfig config,
    NetworkInterface? rawInterface,
  }) async {
    if (_isRunning) await stop();

    final targetGroup = InternetAddress(config.groupAddress);
    final targetPort = config.port;

    // Bind sender socket
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket?.multicastHops = config.ttl;
    _socket?.multicastLoopback = config.enableLoopback;
    if (rawInterface != null) {
      try {
        // ignore: deprecated_member_use
        _socket?.multicastInterface = rawInterface;
      } catch (_) {}
    }

    _isRunning = true;
    _seq = 0;
    _packetsSent = 0;
    _bytesSent = 0;
    _startTime = DateTime.now();
    _lastPacketsSnapshot = 0;
    _lastBytesSnapshot = 0;
    _lastSnapshotTime = DateTime.now();

    final sessionId = DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(16, '0');
    _currentStats = SenderStats(
      activeSessionId: sessionId,
      duration: Duration.zero,
    );
    _statsController.add(_currentStats);

    final pps = config.packetsPerSecond.clamp(1, 5000);
    final intervalUs = (1000000 / pps).round();

    // Determine batch size and timer interval for smooth transmission
    int tickMs = 10;
    int packetsPerTick = 1;

    if (pps <= 50) {
      tickMs = (1000 / pps).round().clamp(10, 1000);
      packetsPerTick = 1;
    } else {
      tickMs = 10; // 100 ticks per sec
      packetsPerTick = (pps / 100).ceil();
    }

    _sendTimer = Timer.periodic(Duration(milliseconds: tickMs), (timer) {
      if (!_isRunning || _socket == null) return;

      for (int i = 0; i < packetsPerTick; i++) {
        if (_packetsSent >= (pps * 60 * 60 * 24)) break; // safety guard
        _seq++;

        final packet = MulticastPacket(
          version: 1,
          flags: 0,
          sessionId: sessionId,
          sequenceNumber: _seq,
          sendTimestampUs: DateTime.now().microsecondsSinceEpoch,
          configuredIntervalUs: intervalUs,
          payloadSize: config.packetSizeBytes,
        );

        final bytes = packet.encode();
        final sent = _socket?.send(bytes, targetGroup, targetPort);
        if (sent != null && sent > 0) {
          _packetsSent++;
          _bytesSent += sent;
        }
      }
    });

    // 1-second interval stats calculator
    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateStats(sessionId);
    });
  }

  void _updateStats(String sessionId) {
    if (!_isRunning) return;

    final now = DateTime.now();
    final elapsedSec = _lastSnapshotTime == null
        ? 0.5
        : (now.difference(_lastSnapshotTime!).inMicroseconds / 1000000.0);

    final ppsDelta = (_packetsSent - _lastPacketsSnapshot) / (elapsedSec > 0 ? elapsedSec : 1.0);
    final bytesDelta = (_bytesSent - _lastBytesSnapshot) / (elapsedSec > 0 ? elapsedSec : 1.0);
    final mbps = (bytesDelta * 8.0) / 1000000.0;

    _lastPacketsSnapshot = _packetsSent;
    _lastBytesSnapshot = _bytesSent;
    _lastSnapshotTime = now;

    final totalElapsed = _startTime == null ? Duration.zero : now.difference(_startTime!);

    _currentStats = _currentStats.copyWith(
      packetsSent: _packetsSent,
      bytesSent: _bytesSent,
      currentPps: ppsDelta,
      currentBitrateMbps: mbps,
      activeSessionId: sessionId,
      duration: totalElapsed,
    );

    _statsController.add(_currentStats);
  }

  Future<void> stop() async {
    _isRunning = false;
    _sendTimer?.cancel();
    _sendTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;

    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    if (_currentStats.activeSessionId.isNotEmpty) {
      _currentStats = _currentStats.copyWith(
        currentPps: 0.0,
        currentBitrateMbps: 0.0,
      );
      _statsController.add(_currentStats);
    }
  }

  void dispose() {
    stop();
    _statsController.close();
  }
}
