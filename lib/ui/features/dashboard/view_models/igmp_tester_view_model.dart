import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../domain/models/igmp_query_event.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../../../domain/models/multicast_gap_event.dart';
import '../../../../domain/models/multicast_stats.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../../../../data/services/export/csv_export_service.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';
import '../../../../data/services/igmp/igmp_query_sniffer.dart';
import '../../../../data/services/multicast/multicast_receiver_service.dart';
import '../../../../data/services/multicast/multicast_sender_service.dart';
import '../../../../data/services/network/network_interface_service.dart';

class IgmpTesterViewModel extends ChangeNotifier {
  final NetworkInterfaceService _interfaceService;
  final MulticastSenderService _senderService;
  final MulticastReceiverService _receiverService;
  final IgmpQuerySnifferService _snifferService;
  final IgmpQuerierWatchdog _watchdog;
  final CsvExportService _csvService;

  StreamSubscription? _senderSub;
  StreamSubscription? _senderStreamSub;
  StreamSubscription? _receiverSub;
  StreamSubscription? _receiverStreamSub;
  StreamSubscription? _gapSub;
  StreamSubscription? _snifferSub;
  StreamSubscription? _watchdogSub;

  IgmpTesterViewModel({
    NetworkInterfaceService? interfaceService,
    MulticastSenderService? senderService,
    MulticastReceiverService? receiverService,
    IgmpQuerySnifferService? snifferService,
    IgmpQuerierWatchdog? watchdog,
    CsvExportService? csvService,
  })  : _interfaceService = interfaceService ?? NetworkInterfaceService(),
        _senderService = senderService ?? MulticastSenderService(),
        _receiverService = receiverService ?? MulticastReceiverService(),
        _snifferService = snifferService ?? IgmpQuerySnifferService(),
        _watchdog = watchdog ?? IgmpQuerierWatchdog(),
        _csvService = csvService ?? CsvExportService() {
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

  List<IgmpQueryEvent> _igmpEvents = [];
  List<IgmpQueryEvent> get igmpEvents => _igmpEvents;

  QuerierStatus _querierStatus = const QuerierStatus();
  QuerierStatus get querierStatus => _querierStatus;

  String? _tsharkPath;
  String? get tsharkPath => _tsharkPath;
  bool get hasTShark => _tsharkPath != null;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _gapFilter = '';
  String get gapFilter => _gapFilter;

  bool get isSenderRunning => _senderService.isRunning;
  bool get isReceiverRunning => _receiverService.isRunning;
  bool get isSnifferRunning => _snifferService.isRunning;

  bool isSenderStreamActive(String streamId) => _senderService.isStreamRunning(streamId);
  bool isReceiverStreamActive(String streamId) => _receiverService.isStreamRunning(streamId);

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
      notifyListeners();
    });

    _receiverSub = _receiverService.statsStream.listen((stats) {
      _receiverStats = stats;
      _rxThroughputHistory.add(stats.currentBitrateMbps);
      if (_rxThroughputHistory.length > 40) {
        _rxThroughputHistory.removeAt(0);
      }
      notifyListeners();
    });

    _receiverStreamSub = _receiverService.streamStatsStream.listen((streamMap) {
      _streamReceiverStats = streamMap;
      notifyListeners();
    });

    _gapSub = _receiverService.gapStream.listen((gap) {
      _gaps = _receiverService.gaps;
      notifyListeners();
    });

    _snifferSub = _snifferService.queryStream.listen((event) {
      _igmpEvents = _snifferService.events;
      _watchdog.recordQuery(event);
      notifyListeners();
    });

    _watchdogSub = _watchdog.statusStream.listen((status) {
      _querierStatus = status;
      notifyListeners();
    });

    _watchdog.start();
    notifyListeners();
  }

  Future<void> refreshInterfaces() async {
    _interfaces = await _interfaceService.getAvailableInterfaces();
    if (_interfaces.isNotEmpty && _selectedInterface == null) {
      final preferred = _interfaces.firstWhere(
        (i) => i.ip != '127.0.0.1' && i.ip != '0.0.0.0',
        orElse: () => _interfaces.first,
      );
      _selectedInterface = preferred;
      _senderConfig = _senderConfig.copyWith(interface: preferred);
      _receiverConfig = _receiverConfig.copyWith(interface: preferred);
    }
    notifyListeners();
  }

  void selectInterface(NetworkInterfaceInfo iface) {
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
  }) {
    final newStreams = <MulticastStreamConfig>[];
    for (int i = 0; i < count; i++) {
      final ip = MulticastStreamConfig.incrementIp(startingIp, i);
      final port = incrementPort ? basePort + i : basePort;
      newStreams.add(
        MulticastStreamConfig(
          id: 'gen_tx_${DateTime.now().millisecondsSinceEpoch}_$i',
          name: 'Stream ${i + 1}',
          groupAddress: ip,
          port: port,
          packetsPerSecond: pps,
          packetSizeBytes: packetSize,
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
    notifyListeners();
  }

  void updateReceiverStream(MulticastReceiverStreamConfig stream) {
    final list = _receiverConfig.streams.map((s) => s.id == stream.id ? stream : s).toList();
    _receiverConfig = _receiverConfig.copyWith(streams: list);
    notifyListeners();
  }

  void removeReceiverStream(String streamId) {
    if (isReceiverStreamActive(streamId)) {
      _receiverService.stopStream(streamId);
    }
    final list = _receiverConfig.streams.where((s) => s.id != streamId).toList();
    _receiverConfig = _receiverConfig.copyWith(streams: list);
    notifyListeners();
  }

  Future<void> toggleIndividualReceiverStream(String streamId) async {
    _clearError();
    if (isReceiverStreamActive(streamId)) {
      await _receiverService.stopStream(streamId);
      notifyListeners();
    } else {
      final stream = _receiverConfig.streams.firstWhere((s) => s.id == streamId);
      try {
        final rawIface = _interfaceService.findRawInterface(_receiverConfig.interface ?? _selectedInterface);
        await _receiverService.startStream(
          streamConfig: stream,
          rawInterface: rawIface,
          enableLoopback: _receiverConfig.enableLoopback,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to join group ${stream.groupAddress}: $e';
        notifyListeners();
      }
    }
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
      final port = incrementPort ? basePort + i : basePort;
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

  Future<void> toggleReceiver() async {
    _clearError();
    if (isReceiverRunning) {
      await _receiverService.stop();
      notifyListeners();
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
        _errorMessage = 'Failed to start TShark IGMP sniffer on interface ${_selectedInterface?.name}.';
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

  Future<void> stopAll() async {
    await _senderService.stop();
    await _receiverService.stop();
    await _snifferService.stop();
    _watchdog.stop();
  }

  @override
  void dispose() {
    _senderSub?.cancel();
    _senderStreamSub?.cancel();
    _receiverSub?.cancel();
    _receiverStreamSub?.cancel();
    _gapSub?.cancel();
    _snifferSub?.cancel();
    _watchdogSub?.cancel();
    _senderService.dispose();
    _receiverService.dispose();
    _snifferService.dispose();
    _watchdog.dispose();
    super.dispose();
  }
}
