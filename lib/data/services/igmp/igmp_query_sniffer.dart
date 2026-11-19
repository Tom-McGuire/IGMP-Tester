import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  final List<IgmpQueryEvent> _events = [];
  List<IgmpQueryEvent> get events => List.unmodifiable(_events);

  bool get isRunning => _isRunning;

  DateTime? _lastQueryTime;
  DateTime? get lastQueryTime => _lastQueryTime;
  String? _querierIp;
  String? get querierIp => _querierIp;
  IgmpProtocolVersion _querierVersion = IgmpProtocolVersion.unknown;
  IgmpProtocolVersion get querierVersion => _querierVersion;
  String _activeInterfaceName = '';

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

    _activeInterfaceName = iface?.name ?? '';

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
      '-e', 'igmp.max_resp',
      '-e', 'igmp.maddr',
      '-e', 'igmp.version',
      '-e', 'igmp.qrv',
      '-e', 'igmp.qqic',
      '-e', 'igmp.s',
      '-e', 'igmp.saddr',
    ];

    // Select interface if specified
    if (iface != null && iface.ip != '0.0.0.0') {
      args.addAll(['-i', iface.name]);
    }

    try {
      _process = await Process.start(tsharkPath, args);
      _isRunning = true;
      _lastError = null;
      _statusController.add(true);

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

      _process?.exitCode.then((code) {
        _isRunning = false;
        _statusController.add(false);
      });

      return true;
    } catch (e) {
      _lastError = e.toString();
      _isRunning = false;
      _statusController.add(false);
      return false;
    }
  }

  static int? _parseIntFlexible(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      return int.tryParse(trimmed.substring(2), radix: 16);
    }
    return int.tryParse(trimmed);
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
    final qrvRaw = parts.length > 7 ? parts[7].trim() : '';
    final qqicRaw = parts.length > 8 ? parts[8].trim() : '';
    final sRaw = parts.length > 9 ? parts[9].trim() : '';
    final saddrRaw = parts.length > 10 ? parts[10].trim() : '';

    DateTime ts = DateTime.now();
    final epoch = double.tryParse(epochStr);
    if (epoch != null) {
      ts = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round());
    }

    final typeCode = int.tryParse(typeRaw.startsWith('0x') ? typeRaw : '0x$typeRaw') ??
        int.tryParse(typeRaw) ??
        0;

    final maxRespRawInt = _parseIntFlexible(maxRespRaw);
    final hasV3Fields =
        qrvRaw.isNotEmpty || qqicRaw.isNotEmpty || sRaw.isNotEmpty || saddrRaw.isNotEmpty;

    IgmpProtocolVersion protocolVersion = IgmpProtocolVersion.parse(ver);
    if (typeCode == 0x11 && hasV3Fields) {
      protocolVersion = IgmpProtocolVersion.igmpv3;
    } else if (protocolVersion == IgmpProtocolVersion.unknown) {
      if (typeCode == 0x22) {
        protocolVersion = IgmpProtocolVersion.igmpv3;
      } else if (typeCode == 0x12) {
        protocolVersion = IgmpProtocolVersion.igmpv1;
      } else if (typeCode == 0x16 || typeCode == 0x17) {
        protocolVersion = IgmpProtocolVersion.igmpv2;
      } else if (typeCode == 0x11) {
        protocolVersion = maxRespRawInt == 0
            ? IgmpProtocolVersion.igmpv1
            : IgmpProtocolVersion.igmpv2;
      }
    }

    final isV3 = protocolVersion == IgmpProtocolVersion.igmpv3;
    final maxRespSec = maxRespRawInt != null
        ? IgmpQueryEvent.decodeMaxRespSeconds(maxRespRawInt, isV3: isV3)
        : 0.0;

    final sourceAddresses = saddrRaw.isEmpty
        ? const <String>[]
        : saddrRaw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

    final parsedQrv = isV3 ? _parseIntFlexible(qrvRaw) : null;
    final qrv = parsedQrv != null ? (parsedQrv & 0x07) : null;
    final parsedQqic = isV3 ? _parseIntFlexible(qqicRaw) : null;
    final qqicSeconds =
        parsedQqic != null ? IgmpQueryEvent.decodeQqic(parsedQqic) : null;
    final sNorm = sRaw.toLowerCase();
    final suppress = isV3 && (sNorm == '1' || sNorm == 'true');

    String typeName = 'Unknown ($typeRaw)';
    final String typeHex = '0x${typeCode.toRadixString(16).padLeft(2, '0')}';

    if (typeCode == 0x11) {
      if (maddr.isEmpty || maddr == '0.0.0.0' || dstIp == '224.0.0.1') {
        typeName = 'General Query';
      } else if (sourceAddresses.isNotEmpty) {
        typeName = 'Group-and-Source-Specific Query';
      } else {
        typeName = 'Group-Specific Query';
      }
    } else if (typeCode == 0x12) {
      typeName = 'IGMPv1 Report';
    } else if (typeCode == 0x16) {
      typeName = 'IGMPv2 Report';
    } else if (typeCode == 0x17) {
      typeName = 'IGMPv2 Leave';
    } else if (typeCode == 0x22) {
      typeName = 'IGMPv3 Report';
    }

    final versionLabel = protocolVersion != IgmpProtocolVersion.unknown
        ? protocolVersion.label
        : (ver.isEmpty ? 'Unknown' : ver);

    final event = IgmpQueryEvent(
      timestamp: ts,
      querierIp: srcIp,
      destinationIp: dstIp,
      typeHex: typeHex,
      typeName: typeName,
      groupAddress: maddr.isEmpty
          ? (dstIp == '224.0.0.1' ? 'All Systems (224.0.0.1)' : dstIp)
          : maddr,
      maxRespTimeSeconds: maxRespSec,
      version: versionLabel,
      protocolVersion: protocolVersion,
      qrv: qrv,
      qqicSeconds: qqicSeconds,
      suppressRouterProcessing: suppress,
      sourceAddresses: List.unmodifiable(sourceAddresses),
      interfaceName: _activeInterfaceName,
      rawSummary: line,
    );

    _recordEvent(event);
  }

  void _recordEvent(IgmpQueryEvent event) {
    if (event.isQuery) {
      _lastQueryTime = event.timestamp;
      _querierIp = event.querierIp;
      _querierVersion = event.protocolVersion;
    }

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
    _statusController.add(false);
  }

  void clearEvents() {
    _events.clear();
    _lastQueryTime = null;
    _querierIp = null;
    _querierVersion = IgmpProtocolVersion.unknown;
  }

  @visibleForTesting
  void parseLineForTesting(String line) => _parseLine(line);

  /// Parses raw IGMP wire bytes into an [IgmpQueryEvent], recording and emitting it if valid.
  @visibleForTesting
  IgmpQueryEvent? parseRawPayloadForTesting(
    Uint8List payload, {
    DateTime? timestamp,
    String querierIp = '',
    String? destinationIp,
    String interfaceName = '',
  }) {
    final event = IgmpQueryEvent.fromRawIgmpBytes(
      payload,
      timestamp: timestamp,
      querierIp: querierIp,
      destinationIp: destinationIp,
      interfaceName: interfaceName,
    );
    if (event != null) {
      _recordEvent(event);
    }
    return event;
  }

  void dispose() {
    stop();
    _queryEventsController.close();
    _statusController.close();
  }
}
