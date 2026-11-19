import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../domain/models/dscp_preset.dart';
import '../../../../domain/models/flooded_stream_entry.dart';
import '../../../../domain/models/igmp_query_event.dart';
import '../../../../domain/models/launch_adapter_config.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../../../domain/models/multicast_gap_event.dart';
import '../../../../domain/models/multicast_stats.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../../../../data/services/export/csv_export_service.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';
import '../../../../data/services/igmp/igmp_query_sniffer.dart';
import '../../../../data/services/multicast/flooding_scanner_service.dart';
import '../../../../data/services/multicast/multicast_receiver_service.dart';
import '../../../../data/services/multicast/multicast_sender_service.dart';
import '../../../../data/services/network/network_interface_service.dart';

class IgmpTesterViewModel extends ChangeNotifier {
  final NetworkInterfaceService _interfaceService;
  final MulticastSenderService _senderService;
  final MulticastReceiverService _receiverService;
  final IgmpQuerySnifferService _snifferService;
  final IgmpQuerierWatchdog _watchdog;
  final FloodingScannerService _floodingScannerService;
  final CsvExportService _csvService;
  final LaunchAdapterConfig? launchAdapterConfig;

  StreamSubscription? _senderSub;
  StreamSubscription? _senderStreamSub;
  StreamSubscription? _receiverSub;
  StreamSubscription? _receiverStreamSub;
  StreamSubscription? _gapSub;
  StreamSubscription? _unsubscribedSub;
  StreamSubscription? _leaveLatencySub;
  StreamSubscription? _snifferSub;
  StreamSubscription? _snifferStatusSub;
  StreamSubscription? _watchdogSub;
  bool _scannerListenerAttached = false;
  bool _startupAdapterApplied = false;
  bool _isDemoMode = false;
  bool get isDemoMode => _isDemoMode;

  IgmpTesterViewModel({
    NetworkInterfaceService? interfaceService,
    MulticastSenderService? senderService,
    MulticastReceiverService? receiverService,
    IgmpQuerySnifferService? snifferService,
    IgmpQuerierWatchdog? watchdog,
    FloodingScannerService? floodingScannerService,
    CsvExportService? csvService,
    this.launchAdapterConfig,
  })  : _interfaceService = interfaceService ?? NetworkInterfaceService(),
        _senderService = senderService ?? MulticastSenderService(),
        _receiverService = receiverService ?? MulticastReceiverService(),
        _snifferService = snifferService ?? IgmpQuerySnifferService(),
        _watchdog = watchdog ?? IgmpQuerierWatchdog(),
        _floodingScannerService =
            floodingScannerService ?? FloodingScannerService(),
        _csvService = csvService ?? CsvExportService() {
    _floodingScannerService.addListener(_onFloodingScannerChanged);
    _scannerListenerAttached = true;
    init();
  }

  List<NetworkInterfaceInfo> _interfaces = [];
  List<NetworkInterfaceInfo> get interfaces => _interfaces;

  NetworkInterfaceInfo? _selectedInterface;
  NetworkInterfaceInfo? get selectedInterface => _selectedInterface;

  MulticastSenderConfig _senderConfig = const MulticastSenderConfig();
  MulticastSenderConfig get senderConfig => _senderConfig;

  MulticastReceiverConfig _receiverConfig = const MulticastReceiverConfig();
  MulticastReceiverConfig get receiverConfig => _receiverConfig;

  SenderStats _senderStats = const SenderStats();
  SenderStats get senderStats => _senderStats;

  Map<String, SenderStats> _streamSenderStats = {};
  Map<String, SenderStats> get streamSenderStats => _streamSenderStats;

  ReceiverStats _receiverStats = const ReceiverStats();
  ReceiverStats get receiverStats => _receiverStats;

  Map<String, ReceiverStats> _streamReceiverStats = {};
  Map<String, ReceiverStats> get streamReceiverStats => _streamReceiverStats;

  List<MulticastGapEvent> _gaps = [];
  List<MulticastGapEvent> get gaps => _gaps;

  List<UnsubscribedStreamInfo> _unsubscribedStreams = [];
  List<UnsubscribedStreamInfo> get unsubscribedStreams => _unsubscribedStreams;

  List<IgmpQueryEvent> _igmpEvents = [];
  List<IgmpQueryEvent> get igmpEvents => _igmpEvents;

  QuerierStatus _querierStatus = const QuerierStatus();
  QuerierStatus get querierStatus => _querierStatus;

  String? _tsharkPath;
  String? get tsharkPath => _tsharkPath;
  bool get hasTShark => _tsharkPath != null;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _dismissedDiagnosticWarning;
  bool _measureFastLeave = false;
  bool get measureFastLeave => _measureFastLeave;
  LeaveLatencyResult? _lastLeaveLatency;
  LeaveLatencyResult? get lastLeaveLatency =>
      _lastLeaveLatency ?? _receiverService.lastLeaveLatency;
  Map<String, LeaveLatencyResult> get leaveLatencyByStream =>
      _receiverService.leaveLatencyByStream;

  String _gapFilter = '';
  String get gapFilter => _gapFilter;

  FloodingScannerService get floodingScannerService => _floodingScannerService;
  bool get isFloodingScanRunning => _floodingScannerService.isScanning;
  List<FloodedStreamEntry> get floodedStreamEntries =>
      _floodingScannerService.entries;
  Set<String> get activeJoinedGroupKeys => _receiverConfig.streams
      .where((s) => isReceiverStreamJoined(s.id))
      .map((s) => s.endpoint)
      .toSet();

  bool get isSenderRunning => _senderService.isRunning;
  bool get isReceiverRunning => _receiverService.isRunning;
  bool get isMeasuringLeave => _receiverService.isMeasuringLeave;
  bool get isPassiveServerRunning => _receiverService.isPassiveServerRunning;
  Set<int> get activePassivePorts => _receiverService.activePassivePorts;
  bool get isSnifferRunning => _snifferService.isRunning;
  bool get isAnyRunning =>
      isSenderRunning || isReceiverRunning || isMeasuringLeave || isSnifferRunning;

  bool isSenderStreamActive(String streamId) => _senderService.isStreamRunning(streamId);
  bool isReceiverStreamActive(String streamId) => _receiverService.isStreamRunning(streamId);
  bool isReceiverStreamJoined(String streamId) => _receiverService.isStreamJoined(streamId);
  bool isStreamMeasuringLeave(String streamId) =>
      _receiverService.isStreamMeasuringLeave(streamId);

  /// Actionable compatibility alert when an `SSM (S, G)` stream is configured
  /// on a subnet whose active Querier only speaks IGMPv1 or IGMPv2.
  String? get ssmCompatibilityWarning {
    final hasSsm = _receiverConfig.streams.any((s) => s.enabled && s.isSsm);
    if (!hasSsm) return null;
    final qv = _querierStatus.querierVersion;
    if (qv == IgmpProtocolVersion.igmpv1 || qv == IgmpProtocolVersion.igmpv2) {
      return 'SSM (S, G) Compatibility Warning: Active Querier is speaking ${qv.label}, '
          'which does not support IGMPv3 source filtering. Using software source filtering fallback.';
    }
    return null;
  }

  /// Non-blocking informational note when OS `IP_ADD_SOURCE_MEMBERSHIP` fell back
  /// to `(*, G)` join with software source filtering on an active stream.
  String? get ssmFallbackNote {
    for (final rx in _streamReceiverStats.values) {
      if (rx.ssmDiagnosticNote != null) return rx.ssmDiagnosticNote;
    }
    return _receiverStats.ssmDiagnosticNote;
  }

  /// QoS policy mismatch or OS `IP_TOS` warning when DSCP tags are stripped,
  /// remarked, or rejected by the local socket layer.
  String? get dscpPolicyWarning {
    for (final s in _streamSenderStats.values) {
      if (!s.dscpSocketApplied &&
          s.dscpPreset != DscpPreset.bestEffort &&
          s.dscpWarning != null) {
        return 'QoS OS Socket Warning (${s.streamName}): ${s.dscpWarning}';
      }
    }
    for (final rx in _streamReceiverStats.values) {
      if (rx.dscpTransitStatus.isAlert) {
        final expected = rx.expectedDscp ?? rx.senderDscpPreset;
        final expectedLabel =
            expected?.shortLabel ?? 'DSCP ${expected?.dscpValue ?? "?"}';
        final observedLabel = rx.receivedDscp != null
            ? DscpPreset.formatDscpBadge(rx.receivedDscp!)
            : 'BE (0)';
        if (rx.dscpTransitStatus == DscpTransitStatus.remarkedToZero) {
          return 'QoS Policy Alert (${rx.streamName}): Sent $expectedLabel -> Received $observedLabel (QoS Stripped by Network)';
        }
        return 'QoS Policy Alert (${rx.streamName}): Sent $expectedLabel -> Received $observedLabel (QoS Remarked in Transit)';
      }
    }
    if (_receiverStats.dscpTransitStatus.isAlert) {
      final expected =
          _receiverStats.expectedDscp ?? _receiverStats.senderDscpPreset;
      final expectedLabel = expected?.shortLabel ?? 'Expected QoS';
      final observedLabel = _receiverStats.receivedDscp != null
          ? DscpPreset.formatDscpBadge(_receiverStats.receivedDscp!)
          : 'BE (0)';
      return 'QoS Policy Alert: Sent $expectedLabel -> Received $observedLabel';
    }
    return null;
  }

  String? get rawDiagnosticWarning =>
      ssmCompatibilityWarning ?? dscpPolicyWarning;

  /// Current active non-blocking diagnostic warning banner (unless dismissed).
  String? get diagnosticWarning {
    final raw = rawDiagnosticWarning;
    if (raw == null) return null;
    if (_dismissedDiagnosticWarning == raw) return null;
    return raw;
  }

  void dismissDiagnosticWarning() {
    _dismissedDiagnosticWarning = rawDiagnosticWarning;
    notifyListeners();
  }

  void _syncDiagnosticDismissal() {
    if (rawDiagnosticWarning == null) {
      _dismissedDiagnosticWarning = null;
    }
  }

  void _onFloodingScannerChanged() {
    notifyListeners();
  }

  // Chart data points (last 40 samples)
  final List<double> _rxThroughputHistory = [];
  List<double> get rxThroughputHistory => List.unmodifiable(_rxThroughputHistory);

  Future<void> init() async {
    await refreshInterfaces();
    _tsharkPath = await _snifferService.findTSharkPath();

    _senderSub = _senderService.statsStream.listen((stats) {
      _senderStats = stats;
      notifyListeners();
    });

    _senderStreamSub = _senderService.streamStatsStream.listen((streamMap) {
      _streamSenderStats = streamMap;
      _syncDiagnosticDismissal();
      notifyListeners();
    });

    _receiverSub = _receiverService.statsStream.listen((stats) {
      _receiverStats = stats;
      _lastLeaveLatency = stats.lastLeaveLatency;
      _rxThroughputHistory.add(stats.currentBitrateMbps);
      if (_rxThroughputHistory.length > 40) {
        _rxThroughputHistory.removeAt(0);
      }
      _syncDiagnosticDismissal();
      notifyListeners();
    });

    _receiverStreamSub = _receiverService.streamStatsStream.listen((streamMap) {
      _streamReceiverStats = streamMap;
      _syncDiagnosticDismissal();
      notifyListeners();
    });

    _gapSub = _receiverService.gapStream.listen((gap) {
      _gaps = _receiverService.gaps;
      notifyListeners();
    });

    _unsubscribedSub = _receiverService.unsubscribedStreamsStream.listen((unsubList) {
      _unsubscribedStreams = unsubList;
      notifyListeners();
    });

    _leaveLatencySub = _receiverService.leaveLatencyStream.listen((result) {
      _lastLeaveLatency = result;
      notifyListeners();
    });

    _snifferSub = _snifferService.queryStream.listen((event) {
      _igmpEvents = _snifferService.events;
      _watchdog.recordQuery(event);
      notifyListeners();
    });

    _snifferStatusSub = _snifferService.statusStream.listen((running) {
      if (!running && _snifferService.lastError != null && _snifferService.lastError!.isNotEmpty) {
        _errorMessage = 'IGMP Sniffer stopped: ${_snifferService.lastError}';
      }
      notifyListeners();
    });

    _watchdogSub = _watchdog.statusStream.listen((status) {
      _querierStatus = status;
      _syncDiagnosticDismissal();
      notifyListeners();
    });

    _watchdog.start();
    notifyListeners();
  }

  Future<void> refreshInterfaces() async {
    _interfaces = await _interfaceService.getAvailableInterfaces();
    if (_interfaces.isNotEmpty && _selectedInterface == null) {
      final NetworkInterfaceInfo? preferred;
      if (!_startupAdapterApplied &&
          launchAdapterConfig != null &&
          launchAdapterConfig!.hasAdapterOverride) {
        preferred = launchAdapterConfig!.selectInitialInterface(_interfaces);
      } else {
        preferred = _interfaces.firstWhere(
          (i) => i.ip != '127.0.0.1' && i.ip != '0.0.0.0',
          orElse: () => _interfaces.first,
        );
      }
      _startupAdapterApplied = true;
      if (preferred != null) {
        _selectedInterface = preferred;
        _senderConfig = _senderConfig.copyWith(interface: preferred);
        _receiverConfig = _receiverConfig.copyWith(interface: preferred);
      }
    }
    notifyListeners();
  }

  void selectInterface(NetworkInterfaceInfo iface) {
    _startupAdapterApplied = true;
    _selectedInterface = iface;
    _senderConfig = _senderConfig.copyWith(interface: iface);
    _receiverConfig = _receiverConfig.copyWith(interface: iface);
    notifyListeners();
  }

  void setGapFilter(String query) {
    _gapFilter = query.trim().toLowerCase();
    notifyListeners();
  }

  List<MulticastGapEvent> get filteredGaps {
    if (_gapFilter.isEmpty) return _gaps;
    return _gaps.where((g) {
      return g.startSeq.toString().contains(_gapFilter) ||
          g.endSeq.toString().contains(_gapFilter) ||
          g.missingPackets.toString().contains(_gapFilter) ||
          g.streamName.toLowerCase().contains(_gapFilter) ||
          g.groupAddress.contains(_gapFilter) ||
          g.sessionId.toLowerCase().contains(_gapFilter);
    }).toList();
  }

  // Sender Stream Operations
  void addSenderStream(MulticastStreamConfig stream) {
    final list = List<MulticastStreamConfig>.from(_senderConfig.streams)..add(stream);
    _senderConfig = _senderConfig.copyWith(streams: list);
    notifyListeners();
  }

  void updateSenderStream(MulticastStreamConfig stream) {
    final list = _senderConfig.streams.map((s) => s.id == stream.id ? stream : s).toList();
    _senderConfig = _senderConfig.copyWith(streams: list);
    notifyListeners();
  }

  void removeSenderStream(String streamId) {
    if (isSenderStreamActive(streamId)) {
      _senderService.stopStream(streamId);
    }
    final list = _senderConfig.streams.where((s) => s.id != streamId).toList();
    _senderConfig = _senderConfig.copyWith(streams: list);
    notifyListeners();
  }

  Future<void> toggleIndividualSenderStream(String streamId) async {
    _clearError();
    if (isSenderStreamActive(streamId)) {
      await _senderService.stopStream(streamId);
      notifyListeners();
    } else {
      final stream = _senderConfig.streams.firstWhere((s) => s.id == streamId);
      try {
        final rawIface = _interfaceService.findRawInterface(_senderConfig.interface ?? _selectedInterface);
        await _senderService.startStream(
          streamConfig: stream,
          rawInterface: rawIface,
          enableLoopback: _senderConfig.enableLoopback,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to start stream ${stream.name}: $e';
        notifyListeners();
      }
    }
  }

  void batchGenerateSenderStreams({
    required int count,
    required String startingIp,
    required int basePort,
    required int pps,
    required int packetSize,
    bool incrementPort = false,
    DscpPreset dscpPreset = DscpPreset.bestEffort,
  }) {
    final newStreams = <MulticastStreamConfig>[];
    for (int i = 0; i < count; i++) {
      final ip = MulticastStreamConfig.incrementIp(startingIp, i);
      final port = (incrementPort ? basePort + i : basePort).clamp(1, 65535);
      newStreams.add(
        MulticastStreamConfig(
          id: 'gen_tx_${DateTime.now().millisecondsSinceEpoch}_$i',
          name: 'Stream ${i + 1}',
          groupAddress: ip,
          port: port,
          packetsPerSecond: pps,
          packetSizeBytes: packetSize,
          dscpPreset: dscpPreset,
        ),
      );
    }
    _senderConfig = _senderConfig.copyWith(streams: newStreams);
    notifyListeners();
  }

  void updateSenderLoopback(bool loopback) {
    _senderConfig = _senderConfig.copyWith(enableLoopback: loopback);
    notifyListeners();
  }

  Future<void> toggleSender() async {
    _clearError();
    if (isSenderRunning) {
      await _senderService.stop();
      notifyListeners();
    } else {
      try {
        final rawIface = _interfaceService.findRawInterface(_senderConfig.interface ?? _selectedInterface);
        await _senderService.startAll(
          config: _senderConfig,
          rawInterface: rawIface,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to start multicast senders: $e';
        notifyListeners();
      }
    }
  }

  // Receiver Stream Operations
  void addReceiverStream(MulticastReceiverStreamConfig stream) {
    final list = List<MulticastReceiverStreamConfig>.from(_receiverConfig.streams)..add(stream);
    _receiverConfig = _receiverConfig.copyWith(streams: list);
    _syncDiagnosticDismissal();
    notifyListeners();
  }

  void updateReceiverStream(MulticastReceiverStreamConfig stream) {
    final list = _receiverConfig.streams.map((s) => s.id == stream.id ? stream : s).toList();
    _receiverConfig = _receiverConfig.copyWith(streams: list);
    _syncDiagnosticDismissal();
    notifyListeners();
  }

  void removeReceiverStream(String streamId) {
    if (isStreamMeasuringLeave(streamId)) {
      _receiverService.abortLeaveMeasurement(streamId);
    }
    if (isReceiverStreamActive(streamId)) {
      _receiverService.stopStream(streamId);
    }
    final list = _receiverConfig.streams.where((s) => s.id != streamId).toList();
    _receiverConfig = _receiverConfig.copyWith(streams: list);
    _syncDiagnosticDismissal();
    notifyListeners();
  }

  void updateMeasureFastLeave(bool enabled) {
    _measureFastLeave = enabled;
    notifyListeners();
  }

  Future<LeaveLatencyResult?> leaveStreamWithMeasurement(
    String streamId, {
    Duration maxDrainDuration = MulticastReceiverService.defaultMaxDrainDuration,
    Duration silenceTimeout = MulticastReceiverService.defaultSilenceTimeout,
  }) async {
    final future = _receiverService.leaveStreamWithMeasurement(
      streamId,
      maxDrainDuration: maxDrainDuration,
      silenceTimeout: silenceTimeout,
    );
    _lastLeaveLatency = _receiverService.lastLeaveLatency;
    notifyListeners();
    final result = await future;
    _lastLeaveLatency = result ?? _receiverService.lastLeaveLatency;
    notifyListeners();
    return result;
  }

  Future<List<LeaveLatencyResult>> leaveAllWithMeasurement({
    Duration maxDrainDuration = MulticastReceiverService.defaultMaxDrainDuration,
    Duration silenceTimeout = MulticastReceiverService.defaultSilenceTimeout,
  }) async {
    final future = _receiverService.leaveAllWithMeasurement(
      maxDrainDuration: maxDrainDuration,
      silenceTimeout: silenceTimeout,
    );
    _lastLeaveLatency = _receiverService.lastLeaveLatency;
    notifyListeners();
    final results = await future;
    _lastLeaveLatency = _receiverService.lastLeaveLatency;
    notifyListeners();
    return results;
  }

  void abortLeaveMeasurement([String? streamId]) {
    _receiverService.abortLeaveMeasurement(streamId);
    _lastLeaveLatency = _receiverService.lastLeaveLatency;
    notifyListeners();
  }

  void clearLeaveLatencyResults() {
    _receiverService.clearLeaveLatencyResults();
    _lastLeaveLatency = null;
    _receiverStats = _receiverStats.copyWith(
      clearLastLeaveLatency: true,
      leaveLatencyByStream: const {},
    );
    notifyListeners();
  }

  Future<void> toggleIndividualReceiverStream(String streamId) async {
    _clearError();
    if (isStreamMeasuringLeave(streamId)) {
      abortLeaveMeasurement(streamId);
      return;
    }
    if (isReceiverStreamActive(streamId)) {
      if (_measureFastLeave && isReceiverStreamJoined(streamId)) {
        await leaveStreamWithMeasurement(streamId);
      } else {
        await _receiverService.stopStream(streamId);
        notifyListeners();
      }
    } else {
      final stream = _receiverConfig.streams.firstWhere((s) => s.id == streamId);
      try {
        final rawIface = _interfaceService.findRawInterface(_receiverConfig.interface ?? _selectedInterface);
        await _receiverService.startStream(
          streamConfig: stream,
          rawInterface: rawIface,
          enableLoopback: _receiverConfig.enableLoopback,
          passiveListenOnly: _receiverConfig.passiveListenOnly,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to join group ${stream.groupAddress}: $e';
        notifyListeners();
      }
    }
  }

  void toggleReceiverStreamJoinMode(String streamId) {
    final stream = _receiverConfig.streams.firstWhere((s) => s.id == streamId);
    updateReceiverStream(stream.copyWith(joinGroup: !stream.joinGroup));
  }

  void updateReceiverPassiveMode(bool passiveOnly) {
    _receiverConfig = _receiverConfig.copyWith(passiveListenOnly: passiveOnly);
    notifyListeners();
  }

  void updateReceiverPassivePort(int port) {
    _receiverConfig = _receiverConfig.copyWith(passiveListenPort: port);
    notifyListeners();
  }

  Future<void> togglePassiveServer({int? port}) async {
    _clearError();
    final targetPort = port ?? _receiverConfig.passiveListenPort;
    if (_receiverService.activePassivePorts.contains(targetPort)) {
      await _receiverService.stopPassiveServer(targetPort);
      notifyListeners();
    } else {
      try {
        await _receiverService.startPassiveServer(
          port: targetPort,
          enableLoopback: _receiverConfig.enableLoopback,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to start no-subscription passive server on port $targetPort: $e';
        notifyListeners();
      }
    }
  }

  void subscribeToDetectedStream(UnsubscribedStreamInfo info) {
    final alreadyExists = _receiverConfig.streams.any(
      (s) => s.groupAddress == info.groupAddress && s.port == info.port,
    );
    if (!alreadyExists) {
      addReceiverStream(
        MulticastReceiverStreamConfig(
          id: 'rx_detected_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Detected ${info.groupAddress}',
          groupAddress: info.groupAddress,
          port: info.port,
          joinGroup: true,
        ),
      );
    }
  }

  void clearUnsubscribedStreams() {
    _receiverService.clearUnsubscribedStreams();
    _unsubscribedStreams = [];
    notifyListeners();
  }

  void batchGenerateReceiverStreams({
    required int count,
    required String startingIp,
    required int basePort,
    bool incrementPort = false,
  }) {
    final newStreams = <MulticastReceiverStreamConfig>[];
    for (int i = 0; i < count; i++) {
      final ip = MulticastStreamConfig.incrementIp(startingIp, i);
      final port = (incrementPort ? basePort + i : basePort).clamp(1, 65535);
      newStreams.add(
        MulticastReceiverStreamConfig(
          id: 'gen_rx_${DateTime.now().millisecondsSinceEpoch}_$i',
          name: 'Group ${i + 1}',
          groupAddress: ip,
          port: port,
        ),
      );
    }
    _receiverConfig = _receiverConfig.copyWith(streams: newStreams);
    notifyListeners();
  }

  void updateReceiverLoopback(bool loopback) {
    _receiverConfig = _receiverConfig.copyWith(enableLoopback: loopback);
    notifyListeners();
  }

  /// Adopts a discovered unjoined flooded multicast stream from [FloodingScannerService]
  /// into the receiver group table and optionally joins + starts tracking it immediately.
  Future<void> adoptFloodedStream(
    FloodedStreamEntry entry, {
    bool autoJoinAndStart = true,
  }) async {
    _clearError();
    MulticastReceiverStreamConfig? targetStream;
    for (final existing in _receiverConfig.streams) {
      if (existing.groupAddress == entry.groupIp &&
          existing.port == entry.destinationPort) {
        targetStream = existing;
        break;
      }
    }

    if (targetStream == null) {
      targetStream = MulticastReceiverStreamConfig(
        id: 'rx_flood_${DateTime.now().millisecondsSinceEpoch}',
        name: '${entry.protocolDisplay} ${entry.groupIp}',
        groupAddress: entry.groupIp,
        port: entry.destinationPort,
        enabled: true,
        joinGroup: true,
      );
      addReceiverStream(targetStream);
    } else if (!targetStream.enabled || !targetStream.joinGroup) {
      targetStream = targetStream.copyWith(enabled: true, joinGroup: true);
      updateReceiverStream(targetStream);
    }

    if (autoJoinAndStart && !isReceiverStreamJoined(targetStream.id)) {
      try {
        final rawIface = _interfaceService.findRawInterface(
          _receiverConfig.interface ?? _selectedInterface,
        );
        await _receiverService.startStream(
          streamConfig: targetStream,
          rawInterface: rawIface,
          enableLoopback: _receiverConfig.enableLoopback,
          passiveListenOnly: false,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to adopt and join ${entry.groupIp}: $e';
        notifyListeners();
      }
    }
  }

  Future<void> toggleReceiver() async {
    _clearError();
    if (isMeasuringLeave) {
      abortLeaveMeasurement();
      return;
    }
    if (isReceiverRunning) {
      if (_measureFastLeave) {
        if (_receiverService.activePassivePorts.isNotEmpty) {
          await _receiverService.stopPassiveServer();
        }
        await leaveAllWithMeasurement();
      } else {
        await _receiverService.stop();
        notifyListeners();
      }
    } else {
      try {
        final rawIface = _interfaceService.findRawInterface(_receiverConfig.interface ?? _selectedInterface);
        await _receiverService.startAll(
          config: _receiverConfig,
          rawInterface: rawIface,
        );
        _gaps = _receiverService.gaps;
        _rxThroughputHistory.clear();
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to bind or join multicast receivers: $e';
        notifyListeners();
      }
    }
  }

  // Sniffer Operations
  Future<void> toggleSniffer() async {
    _clearError();
    if (isSnifferRunning) {
      await _snifferService.stop();
      notifyListeners();
    } else {
      if (!hasTShark) {
        _errorMessage = 'TShark executable not found on this system.';
        notifyListeners();
        return;
      }
      final started = await _snifferService.start(iface: _selectedInterface);
      if (!started) {
        _errorMessage = _snifferService.lastError ??
            'Failed to start TShark IGMP sniffer on interface ${_selectedInterface?.name}.';
      }
      notifyListeners();
    }
  }

  void clearGaps() {
    _receiverService.clearGaps();
    _gaps = [];
    notifyListeners();
  }

  void clearIgmpLogs() {
    _snifferService.clearEvents();
    _igmpEvents = [];
    _watchdog.reset();
    _querierStatus = _watchdog.currentStatus;
    _syncDiagnosticDismissal();
    notifyListeners();
  }

  void dismissError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String generateGapsCsvContent() {
    return _csvService.generateGapsCsv(
      gaps: _gaps,
      stats: _receiverStats,
    );
  }

  Future<String> exportGapsCsv(String filePath) async {
    final csv = generateGapsCsvContent();
    await _csvService.saveCsvToFile(filePath, csv);
    return filePath;
  }

  Future<void> startAll() async {
    _clearError();
    try {
      final rawIface = _interfaceService.findRawInterface(_selectedInterface);
      if (!isSenderRunning && _senderConfig.streams.any((s) => s.enabled)) {
        await _senderService.startAll(
          config: _senderConfig,
          rawInterface: rawIface,
        );
      }
      if (!isReceiverRunning && _receiverConfig.streams.any((s) => s.enabled)) {
        await _receiverService.startAll(
          config: _receiverConfig,
          rawInterface: rawIface,
        );
        _gaps = _receiverService.gaps;
        _rxThroughputHistory.clear();
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start multicast test: $e';
      notifyListeners();
    }
  }

  void loadDemo() {
    batchGenerateSenderStreams(
      count: 10,
      startingIp: '239.255.0.1',
      basePort: 5004,
      pps: 50,
      packetSize: 256,
    );
    batchGenerateReceiverStreams(
      count: 10,
      startingIp: '239.255.0.1',
      basePort: 5004,
    );
  }

  /// Populates realistic in-memory Tx/Rx multicast streams and IGMP query
  /// monitor events, then activates the interactive spotlight walkthrough.
  /// Never writes demo data to [SharedDeviceDatabase].
  void startDemoWalkthrough() {
    if (isAnyRunning) return;
    _isDemoMode = true;
    loadDemo();

    final now = DateTime.now();
    final ifaceName = _selectedInterface?.name ?? 'eth0';
    final generalQuery = IgmpQueryEvent(
      timestamp: now.subtract(const Duration(seconds: 2)),
      querierIp: '192.168.10.1',
      destinationIp: '224.0.0.1',
      typeHex: '0x11',
      typeName: 'General Query',
      groupAddress: '0.0.0.0',
      maxRespTimeSeconds: 10.0,
      version: 'IGMPv3',
      protocolVersion: IgmpProtocolVersion.igmpv3,
      qrv: 2,
      qqicSeconds: 125,
      interfaceName: ifaceName,
      rawSummary: 'IGMPv3 General Query (QRV=2, QQIC=125s)',
    );
    final groupQuery = IgmpQueryEvent(
      timestamp: now.subtract(const Duration(seconds: 5)),
      querierIp: '192.168.10.1',
      destinationIp: '239.255.0.1',
      typeHex: '0x11',
      typeName: 'Group-Specific Query',
      groupAddress: '239.255.0.1',
      maxRespTimeSeconds: 1.0,
      version: 'IGMPv3',
      protocolVersion: IgmpProtocolVersion.igmpv3,
      qrv: 2,
      qqicSeconds: 125,
      interfaceName: ifaceName,
      rawSummary: 'IGMPv3 Group-Specific Query for 239.255.0.1',
    );
    final v2Report = IgmpQueryEvent(
      timestamp: now.subtract(const Duration(seconds: 8)),
      querierIp: '192.168.10.42',
      destinationIp: '239.255.0.2',
      typeHex: '0x16',
      typeName: 'IGMPv2 Membership Report',
      groupAddress: '239.255.0.2',
      maxRespTimeSeconds: 0.0,
      version: 'IGMPv2',
      protocolVersion: IgmpProtocolVersion.igmpv2,
      interfaceName: ifaceName,
      rawSummary: 'IGMPv2 Membership Report for 239.255.0.2',
    );
    final v2Leave = IgmpQueryEvent(
      timestamp: now.subtract(const Duration(seconds: 12)),
      querierIp: '192.168.10.42',
      destinationIp: '224.0.0.2',
      typeHex: '0x17',
      typeName: 'IGMPv2 Leave Group',
      groupAddress: '239.255.0.3',
      maxRespTimeSeconds: 0.0,
      version: 'IGMPv2',
      protocolVersion: IgmpProtocolVersion.igmpv2,
      interfaceName: ifaceName,
      rawSummary: 'IGMPv2 Leave Group 239.255.0.3',
    );

    _igmpEvents = [generalQuery, groupQuery, v2Report, v2Leave];
    _watchdog.recordQuery(generalQuery);
    _querierStatus = _watchdog.currentStatus;
    _syncDiagnosticDismissal();
    notifyListeners();
  }

  /// Clears all Tx/Rx streams, telemetry counters, gaps, IGMP events, and
  /// resets the querier watchdog back to idle.
  void clearAllStreams() {
    _senderConfig = _senderConfig.copyWith(streams: const []);
    _receiverConfig = _receiverConfig.copyWith(streams: const []);
    _gaps = [];
    _igmpEvents = [];
    _unsubscribedStreams = [];
    _rxThroughputHistory.clear();
    _senderStats = const SenderStats();
    _receiverStats = const ReceiverStats();
    _streamSenderStats = {};
    _streamReceiverStats = {};
    _lastLeaveLatency = null;
    _dismissedDiagnosticWarning = null;

    _receiverService.clearGaps();
    _receiverService.clearUnsubscribedStreams();
    _receiverService.clearLeaveLatencyResults();
    _snifferService.clearEvents();
    _watchdog.reset();
    _querierStatus = _watchdog.currentStatus;
    notifyListeners();
  }

  /// Exits demo mode and clears all in-memory demo streams and IGMP events.
  void endDemoWalkthrough() {
    _isDemoMode = false;
    clearAllStreams();
  }

  Future<void> stopAll() async {
    await _senderService.stop();
    await _receiverService.stop();
    await _snifferService.stop();
    await _floodingScannerService.stopScan();
    _watchdog.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_scannerListenerAttached) {
      _floodingScannerService.removeListener(_onFloodingScannerChanged);
      _scannerListenerAttached = false;
    }
    _senderSub?.cancel();
    _senderStreamSub?.cancel();
    _receiverSub?.cancel();
    _receiverStreamSub?.cancel();
    _gapSub?.cancel();
    _unsubscribedSub?.cancel();
    _leaveLatencySub?.cancel();
    _snifferSub?.cancel();
    _snifferStatusSub?.cancel();
    _watchdogSub?.cancel();
    _senderService.dispose();
    _receiverService.dispose();
    _snifferService.dispose();
    _floodingScannerService.dispose();
    _watchdog.dispose();
    super.dispose();
  }
}
