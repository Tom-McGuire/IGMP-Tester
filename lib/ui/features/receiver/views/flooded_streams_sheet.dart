import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../../../data/services/multicast/flooding_scanner_service.dart';
import '../../../../domain/models/flooded_stream_entry.dart';
import '../../../theme/app_theme.dart';

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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
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
              Divider(height: 1, color: AppTheme.border),
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
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.radar, size: 20, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unjoined Multicast Flooding Scanner',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Passive UDP listener without IGMP Membership Reports (zero IGMP Joins sent)',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (canClose)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
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
    final bool isDark = AppTheme.isDark;
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
      color: AppTheme.surfaceAlt,
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
                      color: isDark ? AppTheme.surfaceHigh : AppTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.borderStrong),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.settings_ethernet,
                          size: 13,
                          color: isDark ? const Color(0xFF64B5F6) : AppTheme.info,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ports: $portsText',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: AppTheme.textPrimary,
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
                          ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309))
                          : (hasCompleted
                              ? (isDark ? const Color(0xFF81C784) : const Color(0xFF047857))
                              : AppTheme.textSecondary),
                    ),
                  ),
                  if (_scanner.ignoredControlPacketCount > 0 ||
                      _scanner.ignoredJoinedPacketCount > 0)
                    Text(
                      'Filtered: ${_scanner.ignoredControlPacketCount} control, ${_scanner.ignoredJoinedPacketCount} joined',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
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
                          ? (isDark ? const Color(0xFF8B0000) : AppTheme.error)
                          : (hasCompleted
                              ? const Color(0xFFC2410C)
                              : AppTheme.info),
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
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(color: AppTheme.borderStrong),
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
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isScanning
                      ? AppTheme.warning
                      : (entriesCount > 0
                          ? AppTheme.error
                          : AppTheme.success),
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
    final bool isDark = AppTheme.isDark;

    if (entries.isNotEmpty) {
      final streamWord = entries.length == 1 ? 'Stream' : 'Streams';
      final titleColor = isDark ? const Color(0xFFFF8A80) : const Color(0xFFDC2626);
      final bodyColor = isDark ? const Color(0xFFFFCCBC) : const Color(0xFF991B1B);

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFFF44336).withValues(alpha: 0.14)
              : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark
                ? const Color(0xFFF44336).withValues(alpha: 0.65)
                : AppTheme.error.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: titleColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unregistered Multicast Flooding Detected (${entries.length} $streamWord)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Switch or upstream port may be flooding unregistered multicast traffic to this NIC without an active IGMP Join.',
                    style: TextStyle(fontSize: 11.5, color: bodyColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (hasCompleted && !isScanning) {
      final titleColor = isDark ? const Color(0xFF81C784) : const Color(0xFF059669);
      final bodyColor = isDark ? const Color(0xFFC8E6C9) : const Color(0xFF065F46);

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF4CAF50).withValues(alpha: 0.14)
              : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark
                ? const Color(0xFF4CAF50).withValues(alpha: 0.65)
                : AppTheme.success.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: titleColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Port Clean — 0 Flooded Streams',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No unjoined multicast flooding detected — IGMP snooping appears active on this port',
                    style: TextStyle(fontSize: 11.5, color: bodyColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isScanning) {
      final warnTextColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFF92400E);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFFFF9800).withValues(alpha: 0.12)
              : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark
                ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                : AppTheme.warning.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? const Color(0xFFFFB74D) : AppTheme.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Listening passively on UDP ports ${ports.join(', ')} with zero IGMP Joins...',
                style: TextStyle(
                  fontSize: 12,
                  color: warnTextColor,
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
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderStrong),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? const Color(0xFF64B5F6) : AppTheme.info,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Click "Start Scan" to listen passively on ports ${ports.join(', ')} without sending IGMP Membership Reports.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortErrorsNotice(Map<int, String> errors) {
    final bool isDark = AppTheme.isDark;
    final summary =
        errors.entries.map((e) => '${e.key} (${e.value})').join('; ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFFF9800).withValues(alpha: 0.1)
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark
              ? const Color(0xFFFF9800).withValues(alpha: 0.35)
              : AppTheme.warning.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: isDark ? const Color(0xFFFFB74D) : AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Skipped unavailable port(s): $summary',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFFFFCC80) : const Color(0xFF92400E),
              ),
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
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
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
                      Divider(height: 1, color: AppTheme.border),
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
                    Divider(height: 1, color: AppTheme.border),
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
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
      ),
      child: Row(
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
    final bool isDark = AppTheme.isDark;
    final groupColor = isDark ? const Color(0xFFFF8A80) : AppTheme.error;
    final portColor = isDark ? const Color(0xFF64B5F6) : AppTheme.info;
    final protoColor = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
    final rateColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);

    return Container(
      color: index.isEven ? AppTheme.surface : AppTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  Icons.gpp_maybe,
                  size: 14,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    entry.groupIp,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: groupColor,
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
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: portColor,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.protocolDisplay,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: protoColor,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              entry.sourceIp,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${entry.packetCount} pkts',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.formattedBitrate,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: rateColor,
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
    final bool isDark = AppTheme.isDark;
    final groupColor = isDark ? const Color(0xFFFF8A80) : AppTheme.error;
    final protoColor = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;

    return Container(
      color: index.isEven ? AppTheme.surface : AppTheme.surfaceAlt,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gpp_maybe, size: 14, color: AppTheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.endpoint,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: groupColor,
                  ),
                ),
              ),
              Text(
                entry.protocolDisplay,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: protoColor,
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
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
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
    final bool isDark = AppTheme.isDark;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.info.withValues(alpha: isDark ? 0.22 : 0.10),
        foregroundColor: isDark ? const Color(0xFF64B5F6) : AppTheme.info,
        elevation: 0,
        shadowColor: Colors.transparent,
        side: BorderSide(color: AppTheme.info),
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

TextStyle get _tableHeaderStyle => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: AppTheme.textSecondary,
    );
