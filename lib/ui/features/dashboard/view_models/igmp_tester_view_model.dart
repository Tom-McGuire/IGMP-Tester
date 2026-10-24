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
  StreamSubscription? _receiverSub;
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

  ReceiverStats _receiverStats = const ReceiverStats();
  ReceiverStats get receiverStats => _receiverStats;

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

  // Chart data points (last 30 samples)
  final List<double> _rxThroughputHistory = [];
  List<double> get rxThroughputHistory => List.unmodifiable(_rxThroughputHistory);

  Future<void> init() async {
    await refreshInterfaces();
    _tsharkPath = await _snifferService.findTSharkPath();

    _senderSub = _senderService.statsStream.listen((stats) {
      _senderStats = stats;
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
      // Pick first non-loopback if available
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
          g.sessionId.toLowerCase().contains(_gapFilter);
    }).toList();
  }

  void updateSenderConfig(MulticastSenderConfig config) {
    _senderConfig = config;
    notifyListeners();
  }

  void updateReceiverConfig(MulticastReceiverConfig config) {
    _receiverConfig = config;
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
        await _senderService.start(
          config: _senderConfig,
          rawInterface: rawIface,
        );
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to start multicast sender: $e';
        notifyListeners();
      }
    }
  }

  Future<void> toggleReceiver() async {
    _clearError();
    if (isReceiverRunning) {
      await _receiverService.stop();
      notifyListeners();
    } else {
      try {
        final rawIface = _interfaceService.findRawInterface(_receiverConfig.interface ?? _selectedInterface);
        await _receiverService.start(
          config: _receiverConfig,
          rawInterface: rawIface,
        );
        _gaps = _receiverService.gaps;
        _rxThroughputHistory.clear();
        notifyListeners();
      } catch (e) {
        _errorMessage = 'Failed to bind or join multicast receiver: $e';
        notifyListeners();
      }
    }
  }

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
    _receiverSub?.cancel();
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
