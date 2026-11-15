import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../../../data/services/multicast/flooding_scanner_service.dart';
import '../../../../domain/models/flooded_stream_entry.dart';

/// Modal sheet / dialog panel displaying passive unjoined multicast flooding
/// scan controls, snooping health verdict banners, and discovered streams with
/// one-click `Adopt & Track` actions.
///
/// Designed to work inside [showDialog], [showModalBottomSheet], or embedded
/// directly inside a panel/test scaffold.
class FloodedStreamsSheet extends StatefulWidget {
  /// Optional external scanner instance; when omitted an internal
  /// [FloodingScannerService] is created and disposed automatically.
  final FloodingScannerService? scannerService;

  /// Invoked when the user clicks `Adopt & Track` on a discovered stream.
  final ValueChanged<FloodedStreamEntry>? onAdoptStream;

  /// Optional close callback; defaults to `Navigator.of(context).maybePop()`.
  final VoidCallback? onClose;

  /// UDP ports monitored during passive scans.
  final List<int> scanPorts;

  /// Passive scan duration before auto-stop.
  final Duration scanDuration;

  /// Optional interface metadata passed to [FloodingScannerService.startScan].
  final InternetAddress? interfaceAddress;

  /// Multicast group IPs (or `group:port` keys) already subscribed by the
  /// receiver so they are excluded from flooding alerts.
  final Set<String> alreadyJoinedGroups;

  /// Whether to automatically start scanning when the widget mounts.
  final bool autoStart;

  const FloodedStreamsSheet({
    super.key,
    this.scannerService,
    this.onAdoptStream,
    this.onClose,
    this.scanPorts = FloodingScannerService.defaultPorts,
    this.scanDuration = const Duration(seconds: 10),
    this.interfaceAddress,
    this.alreadyJoinedGroups = const {},
    this.autoStart = false,
  });

  /// Convenience helper to open [FloodedStreamsSheet] inside a centered dialog.
  static Future<void> showDialogModal(
    BuildContext context, {
    FloodingScannerService? scannerService,
    ValueChanged<FloodedStreamEntry>? onAdoptStream,
    List<int> scanPorts = FloodingScannerService.defaultPorts,
    Duration scanDuration = const Duration(seconds: 10),
    InternetAddress? interfaceAddress,
    Set<String> alreadyJoinedGroups = const {},
    bool autoStart = true,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
          child: FloodedStreamsSheet(
            scannerService: scannerService,
            onAdoptStream: onAdoptStream,
            onClose: () => Navigator.of(ctx).pop(),
            scanPorts: scanPorts,
            scanDuration: scanDuration,
            interfaceAddress: interfaceAddress,
            alreadyJoinedGroups: alreadyJoinedGroups,
            autoStart: autoStart,
          ),
        ),
      ),
    );
  }

  /// Convenience helper to open [FloodedStreamsSheet] as a modal bottom sheet.
  static Future<void> showBottomSheetModal(
    BuildContext context, {
    FloodingScannerService? scannerService,
    ValueChanged<FloodedStreamEntry>? onAdoptStream,
    List<int> scanPorts = FloodingScannerService.defaultPorts,
    Duration scanDuration = const Duration(seconds: 10),
    InternetAddress? interfaceAddress,
    Set<String> alreadyJoinedGroups = const {},
    bool autoStart = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: FloodedStreamsSheet(
            scannerService: scannerService,
            onAdoptStream: onAdoptStream,
            onClose: () => Navigator.of(ctx).pop(),
            scanPorts: scanPorts,
            scanDuration: scanDuration,
            interfaceAddress: interfaceAddress,
            alreadyJoinedGroups: alreadyJoinedGroups,
            autoStart: autoStart,
          ),
        ),
      ),
    );
  }

  @override
  State<FloodedStreamsSheet> createState() => _FloodedStreamsSheetState();
}

class _FloodedStreamsSheetState extends State<FloodedStreamsSheet> {
  FloodingScannerService? _ownedScanner;

  FloodingScannerService get _scanner =>
      widget.scannerService ?? _ownedScanner!;

  @override
  void initState() {
    super.initState();
    if (widget.scannerService == null) {
      _ownedScanner = FloodingScannerService();
    }
    _scanner.addListener(_onScannerChanged);

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startScan();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FloodedStreamsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scannerService != widget.scannerService) {
      (oldWidget.scannerService ?? _ownedScanner)
          ?.removeListener(_onScannerChanged);
      if (widget.scannerService == null && _ownedScanner == null) {
        _ownedScanner = FloodingScannerService();
      } else if (widget.scannerService != null && _ownedScanner != null) {
        _ownedScanner!.dispose();
        _ownedScanner = null;
      }
      _scanner.addListener(_onScannerChanged);
    }
  }

  @override
  void dispose() {
    _scanner.removeListener(_onScannerChanged);
    _ownedScanner?.dispose();
    super.dispose();
  }

  void _onScannerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startScan() async {
    await _scanner.startScan(
      ports: widget.scanPorts,
      duration: widget.scanDuration,
      interfaceAddress: widget.interfaceAddress,
      alreadyJoinedGroups: widget.alreadyJoinedGroups,
    );
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _scanner.entries;
    final isScanning = _scanner.isScanning;
    final hasCompleted = _scanner.hasCompletedScan;
    final ports = _scanner.monitoredPorts.isNotEmpty
        ? _scanner.monitoredPorts
        : widget.scanPorts;
    final canClose = widget.onClose != null || Navigator.canPop(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isBoundedHeight = constraints.hasBoundedHeight;
          final isWide = constraints.maxWidth >= 680;

          return Column(
            mainAxisSize: isBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(canClose: canClose),
              const Divider(height: 1, color: Color(0xFF2C2C2C)),
              _buildStatusBar(
                ports: ports,
                isScanning: isScanning,
                hasCompleted: hasCompleted,
                entriesCount: entries.length,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildResultBanner(
                  entries: entries,
                  isScanning: isScanning,
                  hasCompleted: hasCompleted,
                  ports: ports,
                ),
              ),
              if (_scanner.portErrors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildPortErrorsNotice(_scanner.portErrors),
                ),
              const SizedBox(height: 12),
              if (isBoundedHeight)
                Expanded(
                  child: _buildStreamsSection(
                    entries: entries,
                    isWide: isWide,
                    scrollable: true,
                  ),
                )
              else
                _buildStreamsSection(
                  entries: entries,
                  isWide: isWide,
                  scrollable: false,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader({required bool canClose}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.radar, size: 20, color: Color(0xFFFF9800)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unjoined Multicast Flooding Scanner',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Passive UDP listener without IGMP Membership Reports (zero IGMP Joins sent)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          if (canClose)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              tooltip: 'Close',
              onPressed: _handleClose,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar({
    required List<int> ports,
    required bool isScanning,
    required bool hasCompleted,
    required int entriesCount,
  }) {
    final elapsedSec =
        (_scanner.scanElapsed.inMilliseconds / 1000.0).toStringAsFixed(1);
    final totalSec =
        (_scanner.scanDuration.inMilliseconds / 1000.0).toStringAsFixed(0);
    final portsText = ports.join(', ');

    final statusLabel = isScanning
        ? 'Scanning... ${elapsedSec}s / ${totalSec}s'
        : (hasCompleted
            ? 'Scan completed (${elapsedSec}s)'
            : 'Ready to scan');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252526),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF3E3E42)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.settings_ethernet,
                          size: 13,
                          color: Color(0xFF64B5F6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ports: $portsText',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isScanning
                          ? const Color(0xFFFFB74D)
                          : (hasCompleted
                              ? const Color(0xFF81C784)
                              : Colors.grey.shade400),
                    ),
                  ),
                  if (_scanner.ignoredControlPacketCount > 0 ||
                      _scanner.ignoredJoinedPacketCount > 0)
                    Text(
                      'Filtered: ${_scanner.ignoredControlPacketCount} control, ${_scanner.ignoredJoinedPacketCount} joined',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isScanning
                          ? const Color(0xFF8B0000)
                          : (hasCompleted
                              ? const Color(0xFFE65100)
                              : const Color(0xFF2196F3)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    icon: Icon(
                      isScanning
                          ? Icons.stop
                          : (hasCompleted ? Icons.refresh : Icons.radar),
                      size: 15,
                    ),
                    label: Text(
                      isScanning
                          ? 'Stop Scan'
                          : (hasCompleted ? 'Rescan' : 'Start Scan'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: isScanning ? () => _scanner.stopScan() : _startScan,
                  ),
                  if (!isScanning &&
                      (entriesCount > 0 ||
                          hasCompleted ||
                          _scanner.portErrors.isNotEmpty)) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF3E3E42)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.clear_all, size: 15),
                      label: const Text('Clear', style: TextStyle(fontSize: 12)),
                      onPressed: () => _scanner.clear(),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (isScanning || hasCompleted) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _scanner.scanProgress,
                minHeight: 4,
                backgroundColor: const Color(0xFF2C2C2C),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isScanning
                      ? const Color(0xFFFF9800)
                      : (entriesCount > 0
                          ? const Color(0xFFF44336)
                          : const Color(0xFF4CAF50)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultBanner({
    required List<FloodedStreamEntry> entries,
    required bool isScanning,
    required bool hasCompleted,
    required List<int> ports,
  }) {
    if (entries.isNotEmpty) {
      final streamWord = entries.length == 1 ? 'Stream' : 'Streams';
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF44336).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFF44336).withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF8A80),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unregistered Multicast Flooding Detected (${entries.length} $streamWord)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8A80),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Switch or upstream port may be flooding unregistered multicast traffic to this NIC without an active IGMP Join.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFFFCCBC)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (hasCompleted && !isScanning) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.65),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF81C784),
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Port Clean — 0 Flooded Streams',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF81C784),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'No unjoined multicast flooding detected — IGMP snooping appears active on this port',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFC8E6C9)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isScanning) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFFF9800).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Listening passively on UDP ports ${ports.join(', ')} with zero IGMP Joins...',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFFB74D),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3E3E42)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF64B5F6), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Click "Start Scan" to listen passively on ports ${ports.join(', ')} without sending IGMP Membership Reports.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortErrorsNotice(Map<int, String> errors) {
    final summary =
        errors.entries.map((e) => '${e.key} (${e.value})').join('; ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Color(0xFFFFB74D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Skipped unavailable port(s): $summary',
              style: const TextStyle(fontSize: 11, color: Color(0xFFFFCC80)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsSection({
    required List<FloodedStreamEntry> entries,
    required bool isWide,
    required bool scrollable,
  }) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Center(
          child: Text(
            _scanner.isScanning
                ? 'Awaiting incoming unjoined multicast datagrams...'
                : 'No unjoined streams recorded.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Column(
          mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (isWide) _buildTableHeader(),
            if (scrollable)
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFF282828)),
                  itemBuilder: (_, index) => isWide
                      ? _buildWideRow(entries[index], index)
                      : _buildCompactCardRow(entries[index], index),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF282828)),
                itemBuilder: (_, index) => isWide
                    ? _buildWideRow(entries[index], index)
                    : _buildCompactCardRow(entries[index], index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Group IP', style: _tableHeaderStyle)),
          SizedBox(width: 64, child: Text('Port', style: _tableHeaderStyle)),
          Expanded(
            flex: 3,
            child: Text('Detected Protocol', style: _tableHeaderStyle),
          ),
          Expanded(flex: 3, child: Text('Source IP', style: _tableHeaderStyle)),
          Expanded(flex: 2, child: Text('Packets', style: _tableHeaderStyle)),
          Expanded(flex: 2, child: Text('Rate', style: _tableHeaderStyle)),
          SizedBox(width: 128, child: Text('Action', style: _tableHeaderStyle)),
        ],
      ),
    );
  }

  Widget _buildWideRow(FloodedStreamEntry entry, int index) {
    return Container(
      color: index.isEven ? const Color(0xFF1E1E1E) : const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(
                  Icons.gpp_maybe,
                  size: 14,
                  color: Color(0xFFFF5252),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.groupIp,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8A80),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              entry.destinationPort.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF64B5F6),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.protocolDisplay,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4FC1FF),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.sourceIp,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${entry.packetCount} pkts',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.formattedBitrate,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: Color(0xFFFFB74D),
              ),
            ),
          ),
          SizedBox(
            width: 128,
            child: _buildAdoptButton(entry),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCardRow(FloodedStreamEntry entry, int index) {
    return Container(
      color: index.isEven ? const Color(0xFF1E1E1E) : const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe, size: 14, color: Color(0xFFFF5252)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.endpoint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF8A80),
                  ),
                ),
              ),
              Text(
                entry.protocolDisplay,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4FC1FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Src: ${entry.sourceIp} · ${entry.packetCount} pkts · ${entry.formattedBitrate}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildAdoptButton(entry),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdoptButton(FloodedStreamEntry entry) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2196F3).withValues(alpha: 0.22),
        foregroundColor: const Color(0xFF64B5F6),
        side: const BorderSide(color: Color(0xFF2196F3)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      icon: const Icon(Icons.add_task, size: 14),
      label: const Text(
        'Adopt & Track',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      onPressed: widget.onAdoptStream != null
          ? () => widget.onAdoptStream!(entry)
          : null,
    );
  }
}

const TextStyle _tableHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: Colors.grey,
);
