import 'dart:async';
import 'dart:io';
import '../../../domain/models/multicast_config.dart';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_packet.dart';
import '../../../domain/models/multicast_stats.dart';

class MulticastReceiverService {
  RawDatagramSocket? _socket;
  Timer? _statsTimer;
  bool _isRunning = false;

  final _statsController = StreamController<ReceiverStats>.broadcast();
  Stream<ReceiverStats> get statsStream => _statsController.stream;

  final _gapController = StreamController<MulticastGapEvent>.broadcast();
  Stream<MulticastGapEvent> get gapStream => _gapController.stream;

  final List<MulticastGapEvent> _gaps = [];
  List<MulticastGapEvent> get gaps => List.unmodifiable(_gaps);

  ReceiverStats _currentStats = const ReceiverStats();
  ReceiverStats get currentStats => _currentStats;

  bool get isRunning => _isRunning;

  // Tracking state
  String? _activeSessionId;
  int? _firstSeq;
  int? _lastSeq;
  DateTime? _lastPacketTime;
  DateTime? _startTime;
  int _packetsReceived = 0;
  int _packetsLost = 0;
  int _outOfOrderPackets = 0;
  int _duplicatePackets = 0;

  // Jitter RFC 3550
  double _jitterUs = 0.0;
  int? _lastTransitUs;

  // Rate calculations
  int _lastPacketsSnapshot = 0;
  int _bytesReceivedSinceLastSnapshot = 0;
  DateTime? _lastSnapshotTime;

  InternetAddress? _joinedGroup;
  NetworkInterface? _joinedInterface;

  Future<void> start({
    required MulticastReceiverConfig config,
    NetworkInterface? rawInterface,
  }) async {
    if (_isRunning) await stop();

    final targetGroup = InternetAddress(config.groupAddress);
    final targetPort = config.port;

    _joinedGroup = targetGroup;
    _joinedInterface = rawInterface;

    // Windows & POSIX: bind to 0.0.0.0 with reuseAddress
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      targetPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );

    _socket?.multicastLoopback = config.enableLoopback;

    // Join multicast group
    try {
      _socket?.joinMulticast(targetGroup, rawInterface);
    } catch (_) {
      // Fallback without interface argument if system prefers default
      _socket?.joinMulticast(targetGroup);
    }

    _isRunning = true;
    _activeSessionId = null;
    _firstSeq = null;
    _lastSeq = null;
    _lastPacketTime = null;
    _startTime = DateTime.now();
    _packetsReceived = 0;
    _packetsLost = 0;
    _outOfOrderPackets = 0;
    _duplicatePackets = 0;
    _jitterUs = 0.0;
    _lastTransitUs = null;
    _lastPacketsSnapshot = 0;
    _bytesReceivedSinceLastSnapshot = 0;
    _lastSnapshotTime = DateTime.now();
    _gaps.clear();

    _currentStats = ReceiverStats(duration: Duration.zero);
    _statsController.add(_currentStats);

    _socket?.listen((event) {
      if (event == RawSocketEvent.read && _socket != null) {
        while (true) {
          final datagram = _socket?.receive();
          if (datagram == null) break;
          _processDatagram(datagram);
        }
      }
    });

    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateStats();
    });
  }

  void _processDatagram(Datagram datagram) {
    _bytesReceivedSinceLastSnapshot += datagram.data.length;
    final packet = MulticastPacket.decode(datagram.data);
    if (packet == null) return; // Ignore non-IGMPTEST traffic

    final now = DateTime.now();
    final nowUs = now.microsecondsSinceEpoch;

    // Jitter calculation
    final transitUs = nowUs - packet.sendTimestampUs;
    if (_lastTransitUs != null) {
      final d = (transitUs - _lastTransitUs!).abs();
      _jitterUs += (d - _jitterUs) / 16.0;
    }
    _lastTransitUs = transitUs;

    // Session handling
    if (_activeSessionId == null || _activeSessionId != packet.sessionId) {
      _activeSessionId = packet.sessionId;
      _firstSeq = packet.sequenceNumber;
      _lastSeq = packet.sequenceNumber;
      _lastPacketTime = now;
      _packetsReceived++;
      return;
    }

    final seq = packet.sequenceNumber;
    final last = _lastSeq!;

    if (seq == last + 1) {
      // Sequential packet
      _packetsReceived++;
      _lastSeq = seq;
      _lastPacketTime = now;
    } else if (seq > last + 1) {
      // GAP DETECTED
      final missingCount = (seq - last - 1);
      final gapDuration = _lastPacketTime != null
          ? now.difference(_lastPacketTime!)
          : Duration.zero;

      final gapEvent = MulticastGapEvent(
        id: _gaps.length + 1,
        sessionId: packet.sessionId,
        timestamp: now,
        startSeq: last + 1,
        endSeq: seq - 1,
        missingPackets: missingCount,
        gapDuration: gapDuration,
        lastPacketTime: _lastPacketTime ?? now,
        resumedTime: now,
      );

      _gaps.add(gapEvent);
      _gapController.add(gapEvent);

      _packetsLost += missingCount;
      _packetsReceived++;
      _lastSeq = seq;
      _lastPacketTime = now;
    } else {
      // Out of order or duplicate
      if (seq == last) {
        _duplicatePackets++;
      } else {
        _outOfOrderPackets++;
      }
      _packetsReceived++;
    }
  }

  void _updateStats() {
    if (!_isRunning) return;

    final now = DateTime.now();
    final elapsedSec = _lastSnapshotTime == null
        ? 0.5
        : (now.difference(_lastSnapshotTime!).inMicroseconds / 1000000.0);

    final ppsDelta = (_packetsReceived - _lastPacketsSnapshot) / (elapsedSec > 0 ? elapsedSec : 1.0);
    final bytesDelta = _bytesReceivedSinceLastSnapshot / (elapsedSec > 0 ? elapsedSec : 1.0);
    final mbps = (bytesDelta * 8.0) / 1000000.0;

    _lastPacketsSnapshot = _packetsReceived;
    _bytesReceivedSinceLastSnapshot = 0;
    _lastSnapshotTime = now;

    final totalElapsed = _startTime == null ? Duration.zero : now.difference(_startTime!);

    final expected = _firstSeq != null && _lastSeq != null
        ? (_lastSeq! - _firstSeq! + 1)
        : _packetsReceived;

    final lossPct = expected > 0
        ? ((_packetsLost / expected) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    int maxGapPkts = 0;
    double maxGapMs = 0.0;
    double totalGapMs = 0.0;

    for (final gap in _gaps) {
      if (gap.missingPackets > maxGapPkts) maxGapPkts = gap.missingPackets;
      if (gap.gapDurationMs > maxGapMs) maxGapMs = gap.gapDurationMs;
      totalGapMs += gap.gapDurationMs;
    }

    final avgGapMs = _gaps.isNotEmpty ? (totalGapMs / _gaps.length) : 0.0;

    _currentStats = _currentStats.copyWith(
      packetsReceived: _packetsReceived,
      expectedPackets: expected,
      packetsLost: _packetsLost,
      lossRatePercent: lossPct,
      outOfOrderPackets: _outOfOrderPackets,
      duplicatePackets: _duplicatePackets,
      totalGaps: _gaps.length,
      maxGapPackets: maxGapPkts,
      maxGapDurationMs: maxGapMs,
      avgGapDurationMs: avgGapMs,
      currentPps: ppsDelta,
      currentBitrateMbps: mbps,
      jitterMs: _jitterUs / 1000.0,
      firstSeq: _firstSeq,
      lastSeq: _lastSeq,
      activeSessionId: _activeSessionId,
      duration: totalElapsed,
    );

    _statsController.add(_currentStats);
  }

  Future<void> stop() async {
    _isRunning = false;
    _statsTimer?.cancel();
    _statsTimer = null;

    if (_socket != null && _joinedGroup != null) {
      try {
        _socket?.leaveMulticast(_joinedGroup!, _joinedInterface);
      } catch (_) {}
      try {
        _socket?.close();
      } catch (_) {}
    }
    _socket = null;

    _currentStats = _currentStats.copyWith(
      currentPps: 0.0,
      currentBitrateMbps: 0.0,
    );
    _statsController.add(_currentStats);
  }

  void clearGaps() {
    _gaps.clear();
    _packetsLost = 0;
    _outOfOrderPackets = 0;
    _duplicatePackets = 0;
    _updateStats();
  }

  void dispose() {
    stop();
    _statsController.close();
    _gapController.close();
  }
}
