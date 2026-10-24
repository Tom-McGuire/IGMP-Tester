import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../domain/models/igmp_query_event.dart';
import '../../../domain/models/network_interface_info.dart';

class IgmpQuerySnifferService {
  IgmpQuerySnifferService({this.customTSharkPath});

  final String? customTSharkPath;
  Process? _process;
  bool _isRunning = false;
  String? _lastError;
  String? get lastError => _lastError;

  final _queryEventsController = StreamController<IgmpQueryEvent>.broadcast();
  Stream<IgmpQueryEvent> get queryStream => _queryEventsController.stream;

  final List<IgmpQueryEvent> _events = [];
  List<IgmpQueryEvent> get events => List.unmodifiable(_events);

  bool get isRunning => _isRunning;

  DateTime? _lastQueryTime;
  DateTime? get lastQueryTime => _lastQueryTime;
  String? _querierIp;
  String? get querierIp => _querierIp;

  Future<String?> findTSharkPath() async {
    if (customTSharkPath != null && customTSharkPath!.isNotEmpty) {
      if (await File(customTSharkPath!).exists()) {
        return customTSharkPath;
      }
    }

    if (Platform.isWindows) {
      const candidates = [
        r'C:\Program Files\Wireshark\tshark.exe',
        r'C:\Program Files (x86)\Wireshark\tshark.exe',
      ];
      for (final p in candidates) {
        if (await File(p).exists()) return p;
      }

      try {
        final res = await Process.run('where.exe', [r'$PATH:tshark']);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          final lines = res.stdout.toString().trim().split(RegExp(r'[\r\n]+'));
          final cwd = Directory.current.path.toLowerCase();
          for (final raw in lines) {
            final candidate = raw.trim();
            if (candidate.isEmpty) continue;
            final lower = candidate.toLowerCase();
            // Ensure candidate is outside CWD to prevent binary hijacking
            if (!lower.startsWith(cwd) && await File(candidate).exists()) {
              return candidate;
            }
          }
        }
      } catch (_) {}
    } else {
      const candidates = [
        '/usr/bin/tshark',
        '/usr/local/bin/tshark',
        '/opt/homebrew/bin/tshark',
      ];
      for (final p in candidates) {
        if (await File(p).exists()) return p;
      }

      try {
        final res = await Process.run('which', ['tshark']);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          final lines = res.stdout.toString().trim().split(RegExp(r'[\r\n]+'));
          for (final raw in lines) {
            final candidate = raw.trim();
            if (candidate.isNotEmpty && await File(candidate).exists()) {
              return candidate;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<bool> start({
    required NetworkInterfaceInfo? iface,
  }) async {
    if (_isRunning) await stop();

    final tsharkPath = await findTSharkPath();
    if (tsharkPath == null) {
      _lastError = 'tshark executable not found. Please install Wireshark.';
      return false;
    }

    final args = <String>[
      '-l', // line-buffered stdout
      '-n', // no name resolution
      '-f', 'igmp', // capture filter
      '-T', 'fields',
      '-E', 'separator=\t',
      '-e', 'frame.time_epoch',
      '-e', 'ip.src',
      '-e', 'ip.dst',
      '-e', 'igmp.type',
      '-e', 'igmp.max_resp_time',
      '-e', 'igmp.maddr',
      '-e', 'igmp.version',
    ];

    // Select interface if specified
    if (iface != null && iface.ip != '0.0.0.0') {
      args.addAll(['-i', iface.name]);
    }

    try {
      _process = await Process.start(tsharkPath, args);
      _isRunning = true;
      _lastError = null;

      _process?.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_parseLine, onError: (_) {});

      // Drain stderr to prevent child process stalling on full buffer
      _process?.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((errLine) {
            final trimmed = errLine.trim();
            if (trimmed.isNotEmpty) {
              _lastError = trimmed;
            }
          }, onError: (_) {});

      _process?.exitCode.then((_) {
        _isRunning = false;
      });

      return true;
    } catch (e) {
      _lastError = e.toString();
      _isRunning = false;
      return false;
    }
  }

  void _parseLine(String line) {
    final parts = line.split('\t');
    if (parts.length < 4) return;

    final epochStr = parts[0].trim();
    final srcIp = parts[1].trim();
    final dstIp = parts[2].trim();
    final typeRaw = parts[3].trim();
    final maxRespRaw = parts.length > 4 ? parts[4].trim() : '';
    final maddr = parts.length > 5 ? parts[5].trim() : '';
    final ver = parts.length > 6 ? parts[6].trim() : '';

    DateTime ts = DateTime.now();
    final epoch = double.tryParse(epochStr);
    if (epoch != null) {
      ts = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round());
    }

    final typeCode = int.tryParse(typeRaw.startsWith('0x') ? typeRaw : '0x$typeRaw') ??
        int.tryParse(typeRaw) ??
        0;

    String typeName = 'Unknown ($typeRaw)';
    String typeHex = '0x${typeCode.toRadixString(16).padLeft(2, '0')}';
    double maxRespSec = 0.0;

    final maxRespDeci = int.tryParse(maxRespRaw) ?? 0;
    maxRespSec = maxRespDeci / 10.0;

    if (typeCode == 0x11) {
      if (maddr.isEmpty || maddr == '0.0.0.0' || dstIp == '224.0.0.1') {
        typeName = 'General Query';
      } else {
        typeName = 'Group-Specific Query';
      }
      _lastQueryTime = ts;
      _querierIp = srcIp;
    } else if (typeCode == 0x12) {
      typeName = 'IGMPv1 Report';
    } else if (typeCode == 0x16) {
      typeName = 'IGMPv2 Report';
    } else if (typeCode == 0x17) {
      typeName = 'IGMPv2 Leave';
    } else if (typeCode == 0x22) {
      typeName = 'IGMPv3 Report';
    }

    final event = IgmpQueryEvent(
      timestamp: ts,
      querierIp: srcIp,
      destinationIp: dstIp,
      typeHex: typeHex,
      typeName: typeName,
      groupAddress: maddr.isEmpty ? (dstIp == '224.0.0.1' ? 'All Systems (224.0.0.1)' : dstIp) : maddr,
      maxRespTimeSeconds: maxRespSec,
      version: ver.isEmpty ? (typeCode == 0x22 ? 'v3' : 'v2') : ver,
      interfaceName: '',
      rawSummary: line,
    );

    _events.insert(0, event);
    if (_events.length > 1000) {
      _events.removeLast();
    }
    _queryEventsController.add(event);
  }

  Future<void> stop() async {
    _isRunning = false;
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;
  }

  void clearEvents() {
    _events.clear();
    _lastQueryTime = null;
    _querierIp = null;
  }

  void dispose() {
    stop();
    _queryEventsController.close();
  }
}
