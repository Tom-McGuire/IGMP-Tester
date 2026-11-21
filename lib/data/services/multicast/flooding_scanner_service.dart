import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;
import '../../../domain/models/flooded_stream_entry.dart';
import '../../../domain/models/multicast_packet.dart';
import '../igmp/igmp_query_sniffer.dart';

/// Optional socket binder callback used to override passive UDP binding in tests.
typedef PassiveSocketBinder = Future<RawDatagramSocket> Function(int port);

/// Optional callback to resolve the `tshark` executable path in tests.
typedef TSharkPathResolver = Future<String?> Function();

/// Optional callback to spawn a `tshark` process in tests.
typedef TSharkProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Capture backend currently used by [FloodingScannerService].
enum FloodingScanMode {
  /// Layer-2 promiscuous capture via `tshark` (`libpcap`/`Npcap`). Sees all
  /// flooded multicast traffic hitting the NIC without sending IGMP Joins.
  tsharkL2,

  /// Fallback userspace UDP socket listener. OS kernels typically drop
  /// unjoined multicast frames unless another socket on the host joined.
  udpSocketFallback,
}

/// Passive unjoined multicast flooding scanner.
///
/// Binds [RawDatagramSocket] listeners on target UDP ports using
/// [InternetAddress.anyIPv4] (`0.0.0.0`) with `reuseAddress: true` and
/// **never calls `joinMulticast()`**. Any non-control multicast traffic arriving
/// on these sockets indicates unregistered multicast flooding on the network
/// port (for example when switch IGMP snooping is disabled or misconfigured).
class FloodingScannerService extends ChangeNotifier {
  /// Default AV and multicast diagnostic UDP ports:
  /// - `5568`: sACN (ANSI E1.31)
  /// - `6454`: Art-Net DMX
  /// - `4321`: IGMP Tester / auxiliary audio
  /// - `5004`: Dante / AES67 RTP
  static const List<int> defaultPorts = [5568, 6454, 4321, 5004];

  /// UDP ports checked for Dante / AES67 / RTP traffic (`V=2` / `0x80` header).
  static const Set<int> rtpAudioPorts = {5004, 4321};

  /// Default maximum number of distinct stream keys tracked concurrently.
  static const int defaultMaxTrackedStreams = 500;

  /// Explicit link-local control multicast addresses always ignored by default:
  /// - `224.0.0.1`: All Systems on this Subnet (IGMP queries)
  /// - `224.0.0.2`: All Routers on this Subnet (IGMPv2 leave)
  /// - `224.0.0.22`: IGMPv3 Membership Reports
  /// - `224.0.0.251`: mDNS / Bonjour
  /// - `224.0.0.252`: LLMNR
  static const Set<String> knownControlMulticastGroups = {
    '224.0.0.1',
    '224.0.0.2',
    '224.0.0.22',
    '224.0.0.251',
    '224.0.0.252',
  };

  static const List<int> _sacnMagicBytes = [
    0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, // 'ASC-E1.17'
  ];
  static const List<int> _artNetMagicBytes = [
    0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00, // 'Art-Net\0'
  ];

  final PassiveSocketBinder? _socketBinder;
  final TSharkPathResolver? _tsharkPathResolver;
  final TSharkProcessStarter? _processStarter;
  final int _maxTrackedStreams;

  final Map<int, RawDatagramSocket> _boundSockets = {};
  final Map<int, StreamSubscription<RawSocketEvent>> _socketSubscriptions = {};
  final Map<int, String> _portErrors = {};
  final Map<String, FloodedStreamEntry> _entriesByKey = {};

  Process? _tsharkProcess;
  StreamSubscription<String>? _tsharkStdoutSub;
  StreamSubscription<String>? _tsharkStderrSub;
  FloodingScanMode _activeScanMode = FloodingScanMode.udpSocketFallback;
  String? _captureNotice;
  String? _activeInterfaceName;

  final StreamController<List<FloodedStreamEntry>> _entriesController =
      StreamController<List<FloodedStreamEntry>>.broadcast();

  List<int> _monitoredPorts = List<int>.from(defaultPorts);
  Set<String> _alreadyJoinedGroups = {};
  InternetAddress? _interfaceAddress;
  bool _ignoreControlGroups = true;
  bool _ignoreUnicast = true;
  bool _ignoreAlreadyJoinedGroups = true;

  bool _isScanning = false;
  bool _hasCompletedScan = false;
  bool _disposed = false;
  int _scanGeneration = 0;

  DateTime? _scanStartTime;
  Duration _scanDuration = const Duration(seconds: 10);
  Duration _scanElapsed = Duration.zero;
  Timer? _tickTimer;
  Timer? _durationTimer;

  int _ignoredControlPacketCount = 0;
  int _ignoredJoinedPacketCount = 0;
  int _ignoredUnicastPacketCount = 0;
  int _evictedEntryCount = 0;

  FloodingScannerService({
    PassiveSocketBinder? socketBinder,
    TSharkPathResolver? tsharkPathResolver,
    TSharkProcessStarter? processStarter,
    int maxTrackedStreams = defaultMaxTrackedStreams,
  }) :
       // ignore: prefer_initializing_formals
       _socketBinder = socketBinder,
       // ignore: prefer_initializing_formals
       _tsharkPathResolver = tsharkPathResolver,
       // ignore: prefer_initializing_formals
       _processStarter = processStarter,
       _maxTrackedStreams = maxTrackedStreams < 1 ? 1 : maxTrackedStreams;

  /// Active capture backend (`tsharkL2` when `tshark` is available, otherwise
  /// `udpSocketFallback`).
  FloodingScanMode get activeScanMode => _activeScanMode;

  /// Informational or warning notice explaining fallback capture limitations
  /// (for example when `tshark` is unavailable or lacks capture permissions).
  String? get captureNotice => _captureNotice;

  /// Selected OS network interface name passed to `tshark -i`, if any.
  String? get activeInterfaceName => _activeInterfaceName;

  /// Broadcast stream of discovered flooded stream snapshots.
  Stream<List<FloodedStreamEntry>> get entriesStream =>
      _entriesController.stream;

  /// Whether a passive scan is currently active.
  bool get isScanning => _isScanning;

  /// Whether at least one scan has run and finished (or been stopped).
  bool get hasCompletedScan => _hasCompletedScan;

  /// Configured maximum duration for the current/last scan.
  Duration get scanDuration => _scanDuration;

  /// Elapsed duration of the current/last scan.
  Duration get scanElapsed => _scanElapsed;

  /// Selected network interface metadata (informative; sockets always bind
  /// `0.0.0.0` so multicast packets are not filtered out by unicast bind).
  InternetAddress? get interfaceAddress => _interfaceAddress;

  /// Normalized scan progress in `[0.0, 1.0]`.
  double get scanProgress {
    if (_scanDuration <= Duration.zero) {
      return _hasCompletedScan ? 1.0 : 0.0;
    }
    if (_hasCompletedScan && !_isScanning) {
      return 1.0;
    }
    return (_scanElapsed.inMilliseconds / _scanDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// Target UDP ports configured for the current/last scan.
  List<int> get monitoredPorts => List.unmodifiable(_monitoredPorts);

  /// UDP ports that were actively bound without errors during the scan.
  List<int> get boundPorts => List.unmodifiable(_boundSockets.keys);

  /// Per-port socket bind errors encountered during [startScan].
  Map<int, String> get portErrors => Map.unmodifiable(_portErrors);

  /// Discovered unjoined streams ordered by packet count descending, then
  /// first-seen timestamp ascending.
  List<FloodedStreamEntry> get entries {
    final list = _entriesByKey.values.toList()
      ..sort((a, b) {
        final pktCmp = b.packetCount.compareTo(a.packetCount);
        if (pktCmp != 0) return pktCmp;
        return a.firstSeen.compareTo(b.firstSeen);
      });
    return List.unmodifiable(list);
  }

  /// Total packets across all tracked [entries].
  int get totalPacketsSeen =>
      _entriesByKey.values.fold(0, (sum, entry) => sum + entry.packetCount);

  /// Count of control-plane packets (`224.0.0.x`) ignored during the scan.
  int get ignoredControlPacketCount => _ignoredControlPacketCount;

  /// Count of packets dropped because their group was in `alreadyJoinedGroups`.
  int get ignoredJoinedPacketCount => _ignoredJoinedPacketCount;

  /// Count of packets dropped because a unicast destination or indeterminate
  /// UDP payload was seen.
  int get ignoredUnicastPacketCount => _ignoredUnicastPacketCount;

  /// Count of oldest stream entries evicted because the tracked map reached
  /// capacity.
  int get evictedEntryCount => _evictedEntryCount;

  /// Parses dotted-quad IPv4 into 4 octets `[0..255]`, or returns `null`.
  static List<int>? _parseIpv4Octets(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      octets.add(value);
    }
    return octets;
  }

  /// Returns `true` if [ip] is a valid IPv4 multicast address (`224.0.0.0/4`).
  static bool isMulticastIpv4(String ip) {
    final octets = _parseIpv4Octets(ip);
    if (octets == null) return false;
    return octets[0] >= 224 && octets[0] <= 239;
  }

  /// Returns `true` if [ip] is a link-local control multicast group that
  /// switches normally flood or consume in the control plane regardless of
  /// IGMP snooping.
  ///
  /// Specifically returns `true` for IGMP/mDNS/router control groups such as
  /// `224.0.0.1`, `224.0.0.2`, `224.0.0.22`, `224.0.0.251`, and (when
  /// [includeLinkLocalBlock] is `true`, the default) any address in the RFC
  /// 5771 Local Network Control Block `224.0.0.0/24`. Data multicast ranges
  /// such as `239.x.x.x` or `224.0.1.x` (e.g. PTP) return `false`.
  static bool isControlMulticastGroup(
    String ip, {
    bool includeLinkLocalBlock = true,
  }) {
    final trimmed = ip.trim();
    final octets = _parseIpv4Octets(trimmed);
    if (octets == null) return false;

    final normalized = octets.join('.');
    if (knownControlMulticastGroups.contains(normalized)) {
      return true;
    }
    if (includeLinkLocalBlock &&
        octets[0] == 224 &&
        octets[1] == 0 &&
        octets[2] == 0) {
      return true;
    }
    return false;
  }

  /// Identifies common AV/lighting/test protocols from a UDP [payload] and
  /// destination [port], returning `(protocol, detail)`.
  ///
  /// Supported signatures:
  /// - `'IGMP Tester'`: decoded via [MulticastPacket.decode] (`'IGMPTEST'`)
  /// - `'sACN'`: `'ASC-E1.17'` at bytes `4..12`, extracting big-endian uint16
  ///   universe at bytes `113..114` when `payload.length >= 115`
  /// - `'Art-Net'`: `'Art-Net\0'` at bytes `0..7`, extracting little-endian
  ///   uint16 Port-Address/universe at bytes `14..15` when `payload.length >= 16`
  /// - `'Dante / RTP'`: port `5004` or `4321` with RTP v2 version bits
  ///   `(payload[0] & 0xC0) == 0x80`
  /// - `'Unknown UDP'`: fallback when no signature matches
  static (String protocol, String? detail) identifyProtocol(
    Uint8List payload,
    int port,
  ) {
    // 1. IGMP Tester native telemetry packet ('IGMPTEST' magic + >= 56 bytes)
    final igmpPacket = MulticastPacket.decode(payload);
    if (igmpPacket != null) {
      final session = igmpPacket.sessionId;
      final seq = igmpPacket.sequenceNumber;
      final detail = session.isNotEmpty ? '$session · seq $seq' : 'seq $seq';
      return ('IGMP Tester', detail);
    }

    // 2. sACN (ANSI E1.31): 'ASC-E1.17' at bytes 4..12
    if (_matchesBytesAt(payload, 4, _sacnMagicBytes)) {
      if (payload.length >= 115) {
        final universe =
            ByteData.sublistView(payload).getUint16(113, Endian.big);
        return ('sACN', 'Univ $universe');
      }
      return ('sACN', 'E1.31');
    }

    // 3. Art-Net: 'Art-Net\0' at bytes 0..7
    if (_matchesBytesAt(payload, 0, _artNetMagicBytes)) {
      if (payload.length >= 16) {
        final universe =
            ByteData.sublistView(payload).getUint16(14, Endian.little);
        return ('Art-Net', 'Univ $universe');
      }
      return ('Art-Net', null);
    }

    // 4. Dante / AES67 / RTP on audio RTP ports (5004, 4321)
    if (rtpAudioPorts.contains(port) &&
        payload.isNotEmpty &&
        (payload[0] & 0xC0) == 0x80) {
      if (payload.length >= 12) {
        final byteData = ByteData.sublistView(payload);
        final payloadType = payload[1] & 0x7F;
        final seq = byteData.getUint16(2, Endian.big);
        return ('Dante / RTP', 'RTP v2 PT $payloadType · seq $seq');
      }
      if (payload.length >= 2) {
        final payloadType = payload[1] & 0x7F;
        return ('Dante / RTP', 'RTP v2 PT $payloadType');
      }
      return ('Dante / RTP', 'RTP v2');
    }

    // 5. Fallback
    return ('Unknown UDP', null);
  }

  static bool _matchesBytesAt(
    Uint8List payload,
    int offset,
    List<int> expected,
  ) {
    if (payload.length < offset + expected.length) return false;
    for (int i = 0; i < expected.length; i++) {
      if (payload[offset + i] != expected[i]) return false;
    }
    return true;
  }

  /// Builds `tshark` CLI arguments for passive Layer-2 promiscuous capture of
  /// all IPv4 multicast UDP frames (`224.0.0.0/4`) without sending IGMP Joins.
  @visibleForTesting
  static List<String> buildTSharkArgs({String? interfaceName}) {
    final args = <String>[
      '-l', // line-buffered stdout
      '-n', // disable DNS/name resolution
      '-f', 'udp and dst net 224.0.0.0/4',
      '-T', 'fields',
      '-E', 'separator=\t',
      '-e', 'frame.time_epoch',
      '-e', 'ip.src',
      '-e', 'ip.dst',
      '-e', 'udp.dstport',
      '-e', 'udp.length',
      '-e', 'udp.payload',
    ];
    final trimmedIface = interfaceName?.trim();
    if (trimmedIface != null &&
        trimmedIface.isNotEmpty &&
        trimmedIface != 'Default (Any)') {
      args.addAll(['-i', trimmedIface]);
    }
    return args;
  }

  /// Decodes a hex-encoded `tshark` `udp.payload` field (either contiguous hex
  /// or colon-separated bytes) into raw payload bytes.
  @visibleForTesting
  static Uint8List decodeHexPayload(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length < 2) return Uint8List(0);
    final byteCount = cleaned.length ~/ 2;
    final bytes = Uint8List(byteCount);
    for (int i = 0; i < byteCount; i++) {
      bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Starts a passive unjoined scan for [duration].
  ///
  /// Prefers Layer-2 promiscuous capture via `tshark` (`libpcap`/`Npcap`) when
  /// available so unjoined multicast frames (e.g., sACN `239.255.x.x:5568`)
  /// are captured before the OS kernel drops them. Falls back to passive UDP
  /// sockets on [ports] (without ever calling `joinMulticast()`) when `tshark`
  /// is unavailable or when a custom `socketBinder` is injected for tests.
  Future<void> startScan({
    List<int> ports = defaultPorts,
    Duration duration = const Duration(seconds: 10),
    InternetAddress? interfaceAddress,
    String? interfaceName,
    String? tsharkPath,
    Set<String> alreadyJoinedGroups = const {},
    bool ignoreControlGroups = true,
    bool ignoreUnicast = true,
    bool ignoreAlreadyJoinedGroups = true,
  }) async {
    if (_disposed) return;

    await _teardownSocketsAndTimers();
    final generation = ++_scanGeneration;

    final sanitizedPorts = <int>[];
    final seenPorts = <int>{};
    _portErrors.clear();
    _captureNotice = null;

    for (final port in ports) {
      if (port < 1 || port > 65535) {
        _portErrors[port] = 'Invalid UDP port ($port); must be 1–65535';
        continue;
      }
      if (seenPorts.add(port)) {
        sanitizedPorts.add(port);
      }
    }

    _entriesByKey.clear();
    _ignoredControlPacketCount = 0;
    _ignoredJoinedPacketCount = 0;
    _ignoredUnicastPacketCount = 0;
    _evictedEntryCount = 0;

    _monitoredPorts = sanitizedPorts;
    _interfaceAddress = interfaceAddress;
    _activeInterfaceName = interfaceName;
    _alreadyJoinedGroups = Set<String>.from(alreadyJoinedGroups);
    _ignoreControlGroups = ignoreControlGroups;
    _ignoreUnicast = ignoreUnicast;
    _ignoreAlreadyJoinedGroups = ignoreAlreadyJoinedGroups;

    _scanDuration = duration;
    _scanElapsed = Duration.zero;
    _scanStartTime = DateTime.now();
    _hasCompletedScan = false;
    _isScanning = true;

    _emitEntriesAndNotify();

    // Prefer Layer-2 promiscuous capture via tshark unless a custom UDP socket
    // binder was injected (used by unit tests).
    bool startedTShark = false;
    if (_socketBinder == null) {
      String? resolvedTShark =
          (tsharkPath != null && tsharkPath.trim().isNotEmpty)
              ? tsharkPath.trim()
              : null;
      if (resolvedTShark == null) {
        try {
          resolvedTShark = _tsharkPathResolver != null
              ? await _tsharkPathResolver()
              : await IgmpQuerySnifferService().findTSharkPath();
        } catch (_) {
          resolvedTShark = null;
        }
      }

      if (_disposed || generation != _scanGeneration) return;

      if (resolvedTShark != null && resolvedTShark.isNotEmpty) {
        startedTShark = await _startTSharkL2Capture(
          executable: resolvedTShark,
          interfaceName: interfaceName,
          generation: generation,
          fallbackPorts: sanitizedPorts,
        );
      } else {
        _captureNotice =
            'TShark/Wireshark not found — using UDP socket fallback. OS kernels '
            'typically drop unjoined multicast frames without Layer-2 capture '
            '(install Wireshark/Npcap for full unregistered multicast detection).';
      }
    }

    if (_disposed || generation != _scanGeneration) return;

    if (!startedTShark) {
      _activeScanMode = FloodingScanMode.udpSocketFallback;
      await _bindAllFallbackSockets(sanitizedPorts, generation);
      if (_disposed || generation != _scanGeneration) return;

      // If no ports could be bound, conclude scan immediately with recorded errors.
      if (_boundSockets.isEmpty) {
        _isScanning = false;
        _hasCompletedScan = true;
        _emitEntriesAndNotify();
        return;
      }
    }

    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed || !_isScanning || _scanStartTime == null) return;
      _scanElapsed = DateTime.now().difference(_scanStartTime!);
      if (_scanDuration > Duration.zero && _scanElapsed > _scanDuration) {
        _scanElapsed = _scanDuration;
      }
      _notifySafe();
    });

    if (duration > Duration.zero) {
      _durationTimer = Timer(duration, () {
        if (_disposed || generation != _scanGeneration) return;
        stopScan(completedNaturally: true);
      });
    }

    _notifySafe();
  }

  Future<bool> _startTSharkL2Capture({
    required String executable,
    required String? interfaceName,
    required int generation,
    required List<int> fallbackPorts,
  }) async {
    final args = buildTSharkArgs(interfaceName: interfaceName);
    String? lastStderr;

    try {
      final process = _processStarter != null
          ? await _processStarter(executable, args)
          : await Process.start(executable, args);

      if (_disposed || generation != _scanGeneration) {
        try {
          process.kill();
        } catch (_) {}
        return false;
      }

      _tsharkProcess = process;
      _activeScanMode = FloodingScanMode.tsharkL2;
      _captureNotice = null;

      _tsharkStdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_disposed || generation != _scanGeneration) return;
              _parseTSharkLine(line);
            },
            onError: (_) {},
          );

      _tsharkStderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                lastStderr = trimmed;
              }
            },
            onError: (_) {},
          );

      process.exitCode.then((code) async {
        if (_disposed || generation != _scanGeneration || !_isScanning) return;
        if (code != 0 && totalPacketsSeen == 0 && _boundSockets.isEmpty) {
          final reason =
              lastStderr ?? 'tshark exited with status $code';
          _captureNotice =
              'TShark L2 capture failed ($reason) — fell back to UDP sockets. '
              'OS kernels may drop unjoined multicast without capture privileges.';
          _activeScanMode = FloodingScanMode.udpSocketFallback;
          _tsharkProcess = null;
          await _bindAllFallbackSockets(fallbackPorts, generation);
          if (_disposed || generation != _scanGeneration) return;
          if (_boundSockets.isEmpty) {
            await stopScan(completedNaturally: false);
          } else {
            _notifySafe();
          }
        }
      });

      return true;
    } catch (e) {
      _captureNotice =
          'Could not launch TShark L2 capture ($e) — fell back to UDP sockets. '
          'OS kernels may drop unjoined multicast without Layer-2 capture.';
      return false;
    }
  }

  Future<void> _bindAllFallbackSockets(
    List<int> sanitizedPorts,
    int generation,
  ) async {
    // Bind each requested port passively (NEVER call joinMulticast).
    for (final port in sanitizedPorts) {
      if (_disposed || generation != _scanGeneration) return;

      try {
        final socket = await _bindPassiveSocket(port);
        if (_disposed || generation != _scanGeneration) {
          try {
            socket.close();
          } catch (_) {}
          return;
        }

        _boundSockets[port] = socket;
        _socketSubscriptions[port] = socket.listen(
          (event) {
            if (event == RawSocketEvent.read) {
              while (true) {
                final datagram = socket.receive();
                if (datagram == null) break;
                _processDatagram(datagram, port);
              }
            }
          },
          onError: (Object error) {
            _portErrors[port] = error.toString();
            _notifySafe();
          },
        );
      } on SocketException catch (e) {
        _portErrors[port] = e.message.isNotEmpty ? e.message : e.toString();
      } catch (e) {
        _portErrors[port] = e.toString();
      }
    }
  }

  Future<RawDatagramSocket> _bindPassiveSocket(int port) async {
    if (_socketBinder != null) {
      return _socketBinder(port);
    }

    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } on SocketException {
      return RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
    } on UnsupportedError {
      return RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
    }
  }

  /// Stops an active scan and closes all passively bound sockets.
  Future<void> stopScan({bool completedNaturally = false}) async {
    if (_disposed) return;
    ++_scanGeneration;

    final wasActiveOrStarted = _isScanning || _scanStartTime != null;
    if (_scanStartTime != null) {
      final elapsed = DateTime.now().difference(_scanStartTime!);
      _scanElapsed = completedNaturally && _scanDuration > Duration.zero
          ? _scanDuration
          : elapsed;
    }

    await _teardownSocketsAndTimers();
    _isScanning = false;
    if (wasActiveOrStarted) {
      _hasCompletedScan = true;
    }
    _emitEntriesAndNotify();
  }

  Future<void> _teardownSocketsAndTimers() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    final stdoutSub = _tsharkStdoutSub;
    _tsharkStdoutSub = null;
    if (stdoutSub != null) {
      try {
        await stdoutSub.cancel();
      } catch (_) {}
    }

    final stderrSub = _tsharkStderrSub;
    _tsharkStderrSub = null;
    if (stderrSub != null) {
      try {
        await stderrSub.cancel();
      } catch (_) {}
    }

    final proc = _tsharkProcess;
    _tsharkProcess = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }

    final subs = _socketSubscriptions.values.toList();
    _socketSubscriptions.clear();
    for (final sub in subs) {
      try {
        await sub.cancel();
      } catch (_) {}
    }

    final sockets = _boundSockets.values.toList();
    _boundSockets.clear();
    for (final socket in sockets) {
      try {
        socket.close();
      } catch (_) {}
    }
  }

  /// Clears all discovered streams, port errors, and filter counters.
  void clear() {
    if (_disposed) return;
    _entriesByKey.clear();
    _portErrors.clear();
    _captureNotice = null;
    _ignoredControlPacketCount = 0;
    _ignoredJoinedPacketCount = 0;
    _ignoredUnicastPacketCount = 0;
    _evictedEntryCount = 0;
    _scanElapsed = Duration.zero;
    if (_isScanning) {
      _scanStartTime = DateTime.now();
    } else {
      _scanStartTime = null;
      _hasCompletedScan = false;
    }
    _emitEntriesAndNotify();
  }

  /// Updates filtering options for unit tests without binding OS sockets.
  @visibleForTesting
  void configureFiltersForTesting({
    Set<String>? alreadyJoinedGroups,
    bool? ignoreControlGroups,
    bool? ignoreUnicast,
    bool? ignoreAlreadyJoinedGroups,
  }) {
    if (alreadyJoinedGroups != null) {
      _alreadyJoinedGroups = Set<String>.from(alreadyJoinedGroups);
    }
    if (ignoreControlGroups != null) {
      _ignoreControlGroups = ignoreControlGroups;
    }
    if (ignoreUnicast != null) {
      _ignoreUnicast = ignoreUnicast;
    }
    if (ignoreAlreadyJoinedGroups != null) {
      _ignoreAlreadyJoinedGroups = ignoreAlreadyJoinedGroups;
    }
  }

  /// Sets completed-scan state synchronously for deterministic widget/unit
  /// tests without binding OS sockets inside a `FakeAsync` zone.
  @visibleForTesting
  void markScanCompletedForTesting({
    List<int>? ports,
    Duration duration = const Duration(seconds: 10),
    Duration? elapsed,
    FloodingScanMode? scanMode,
    String? captureNotice,
  }) {
    if (_disposed) return;
    if (ports != null) {
      _monitoredPorts = List<int>.from(ports);
    }
    if (scanMode != null) {
      _activeScanMode = scanMode;
    }
    if (captureNotice != null) {
      _captureNotice = captureNotice;
    }
    _scanDuration = duration;
    _scanElapsed = elapsed ?? duration;
    _isScanning = false;
    _hasCompletedScan = true;
    _emitEntriesAndNotify();
  }

  /// Public testing hook to feed a single tab-separated `tshark -T fields` line
  /// (`frame.time_epoch\tip.src\tip.dst\tudp.dstport\tudp.length\tudp.payload`).
  @visibleForTesting
  void processTSharkLineForTesting(
    String line, {
    Set<String>? alreadyJoinedGroups,
  }) {
    if (alreadyJoinedGroups != null) {
      _alreadyJoinedGroups = Set<String>.from(alreadyJoinedGroups);
    }
    _parseTSharkLine(line);
  }

  /// Public testing hook to simulate an arriving [datagram] on [destinationPort]
  /// without network hardware or bound OS sockets.
  @visibleForTesting
  void processDatagramForTesting(
    Datagram datagram,
    int destinationPort, {
    String? destinationGroup,
    DateTime? timestamp,
    Set<String>? alreadyJoinedGroups,
  }) {
    if (alreadyJoinedGroups != null) {
      _alreadyJoinedGroups = Set<String>.from(alreadyJoinedGroups);
    }
    _processDatagram(
      datagram,
      destinationPort,
      destinationGroup: destinationGroup,
      timestamp: timestamp,
    );
  }

  void _parseTSharkLine(String line) {
    if (_disposed) return;
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final parts = line.split('\t');
    if (parts.length < 4) return;

    final epochSec = double.tryParse(parts[0].trim());
    final timestamp = epochSec != null
        ? DateTime.fromMillisecondsSinceEpoch((epochSec * 1000).round())
        : DateTime.now();

    final sourceIp = parts[1].trim();
    final destIp = parts[2].trim();
    final dstPort = int.tryParse(parts[3].trim());
    if (sourceIp.isEmpty || destIp.isEmpty || dstPort == null || dstPort <= 0) {
      return;
    }

    final udpLength = parts.length > 4 ? int.tryParse(parts[4].trim()) : null;
    final hexPayload = parts.length > 5 ? parts[5].trim() : '';
    final payload = hexPayload.isNotEmpty
        ? decodeHexPayload(hexPayload)
        : Uint8List(0);
    final byteLen = payload.isNotEmpty
        ? payload.length
        : (udpLength != null ? (udpLength - 8).clamp(0, 65535) : 0);

    _processPacket(
      sourceIp: sourceIp,
      destinationPort: dstPort,
      payload: payload,
      explicitDestinationGroup: destIp,
      byteLengthOverride: byteLen,
      timestamp: timestamp,
    );
  }

  void _processDatagram(
    Datagram datagram,
    int destinationPort, {
    String? destinationGroup,
    DateTime? timestamp,
  }) {
    _processPacket(
      sourceIp: datagram.address.address,
      destinationPort: destinationPort,
      payload: datagram.data,
      explicitDestinationGroup: destinationGroup,
      timestamp: timestamp,
    );
  }

  void _processPacket({
    required String sourceIp,
    required int destinationPort,
    required Uint8List payload,
    String? explicitDestinationGroup,
    int? byteLengthOverride,
    DateTime? timestamp,
  }) {
    if (_disposed) return;

    final now = timestamp ?? DateTime.now();

    final igmpPacket = MulticastPacket.decode(payload);
    final (protocol, detail) = igmpPacket != null
        ? (
            'IGMP Tester',
            igmpPacket.sessionId.isNotEmpty
                ? '${igmpPacket.sessionId} · seq ${igmpPacket.sequenceNumber}'
                : 'seq ${igmpPacket.sequenceNumber}',
          )
        : identifyProtocol(payload, destinationPort);

    final resolvedGroup = _resolveGroupIp(
      explicitDestinationGroup: explicitDestinationGroup,
      igmpPacket: igmpPacket,
      protocol: protocol,
      payload: payload,
    );

    if (_ignoreControlGroups && isControlMulticastGroup(resolvedGroup)) {
      _ignoredControlPacketCount++;
      _notifySafe();
      return;
    }

    final isExplicitUnicast =
        _parseIpv4Octets(resolvedGroup) != null && !isMulticastIpv4(resolvedGroup);
    final isIndeterminateUnknownUdp =
        resolvedGroup == 'Unknown Group' && protocol == 'Unknown UDP';
    if (_ignoreUnicast && (isExplicitUnicast || isIndeterminateUnknownUdp)) {
      _ignoredUnicastPacketCount++;
      _notifySafe();
      return;
    }

    final isJoined = _alreadyJoinedGroups.contains(resolvedGroup) ||
        _alreadyJoinedGroups.contains('$resolvedGroup:$destinationPort');
    if (_ignoreAlreadyJoinedGroups && isJoined) {
      _ignoredJoinedPacketCount++;
      _notifySafe();
      return;
    }

    final key = '$sourceIp|$resolvedGroup|$destinationPort';
    final existing = _entriesByKey[key];
    final byteLen = byteLengthOverride ?? payload.length;

    if (existing == null) {
      _evictOldestIfFull();
      _entriesByKey[key] = FloodedStreamEntry(
        groupIp: resolvedGroup,
        destinationPort: destinationPort,
        sourceIp: sourceIp,
        detectedProtocol: protocol,
        protocolDetail: detail,
        packetCount: 1,
        bytesReceived: byteLen,
        firstSeen: now,
        lastSeen: now,
        estimatedBitrateBps: 0.0,
        isAlreadyJoined: isJoined,
      );
    } else {
      final firstSeen =
          now.isBefore(existing.firstSeen) ? now : existing.firstSeen;
      final lastSeen =
          now.isAfter(existing.lastSeen) ? now : existing.lastSeen;
      final totalBytes = existing.bytesReceived + byteLen;
      final elapsedUs = lastSeen.difference(firstSeen).inMicroseconds;
      final bitrateBps = elapsedUs > 0
          ? (totalBytes * 8.0) / (elapsedUs / 1000000.0)
          : existing.estimatedBitrateBps;

      final nextProtocol =
          protocol != 'Unknown UDP' ? protocol : existing.detectedProtocol;
      final nextDetail = detail ?? existing.protocolDetail;

      _entriesByKey[key] = existing.copyWith(
        detectedProtocol: nextProtocol,
        protocolDetail: nextDetail,
        packetCount: existing.packetCount + 1,
        bytesReceived: totalBytes,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
        estimatedBitrateBps: bitrateBps,
        isAlreadyJoined: existing.isAlreadyJoined || isJoined,
      );
    }

    _emitEntriesAndNotify();
  }

  void _evictOldestIfFull() {
    while (_entriesByKey.length >= _maxTrackedStreams &&
        _entriesByKey.isNotEmpty) {
      var oldest = _entriesByKey.entries.first;
      for (final mapEntry in _entriesByKey.entries.skip(1)) {
        if (mapEntry.value.lastSeen.isBefore(oldest.value.lastSeen)) {
          oldest = mapEntry;
        }
      }
      _entriesByKey.remove(oldest.key);
      _evictedEntryCount++;
    }
  }

  String _resolveGroupIp({
    required String? explicitDestinationGroup,
    required MulticastPacket? igmpPacket,
    required String protocol,
    required Uint8List payload,
  }) {
    if (explicitDestinationGroup != null &&
        explicitDestinationGroup.trim().isNotEmpty) {
      return explicitDestinationGroup.trim();
    }

    if (igmpPacket != null &&
        _parseIpv4Octets(igmpPacket.destinationGroup) != null) {
      return igmpPacket.destinationGroup;
    }

    // ANSI E1.31 Section 9.3.1: sACN universe U maps to 239.255.(U>>8).(U&0xFF)
    if (protocol == 'sACN' && payload.length >= 115) {
      final universe = ByteData.sublistView(payload).getUint16(113, Endian.big);
      if (universe >= 1 && universe <= 63999) {
        return '239.255.${(universe >> 8) & 0xFF}.${universe & 0xFF}';
      }
    }

    return 'Unknown Group';
  }

  void _emitEntriesAndNotify() {
    if (_disposed) return;
    if (!_entriesController.isClosed) {
      _entriesController.add(entries);
    }
    notifyListeners();
  }

  void _notifySafe() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_scanGeneration;
    _tickTimer?.cancel();
    _tickTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      _tsharkStdoutSub?.cancel();
    } catch (_) {}
    _tsharkStdoutSub = null;

    try {
      _tsharkStderrSub?.cancel();
    } catch (_) {}
    _tsharkStderrSub = null;

    try {
      _tsharkProcess?.kill();
    } catch (_) {}
    _tsharkProcess = null;

    for (final sub in _socketSubscriptions.values) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _socketSubscriptions.clear();

    for (final socket in _boundSockets.values) {
      try {
        socket.close();
      } catch (_) {}
    }
    _boundSockets.clear();

    _entriesController.close();
    super.dispose();
  }
}
