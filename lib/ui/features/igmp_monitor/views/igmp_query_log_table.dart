import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/igmp_query_event.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';
import '../../../theme/app_theme.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class IgmpQueryLogTable extends StatelessWidget {
  const IgmpQueryLogTable({super.key});

  Color _healthColor(QuerierHealth health) {
    switch (health) {
      case QuerierHealth.active:
        return AppTheme.success;
      case QuerierHealth.warning:
        return AppTheme.warning;
      case QuerierHealth.critical:
        return AppTheme.error;
      case QuerierHealth.idle:
        return AppTheme.textSecondary;
    }
  }

  Color _healthTextColor(QuerierHealth health) {
    if (AppTheme.isDark) return _healthColor(health);
    switch (health) {
      case QuerierHealth.active:
        return const Color(0xFF047857);
      case QuerierHealth.warning:
        return const Color(0xFFB45309);
      case QuerierHealth.critical:
        return const Color(0xFFB91C1C);
      case QuerierHealth.idle:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final events = vm.igmpEvents;
    final querierStatus = vm.querierStatus;
    final timeFormat = DateFormat('HH:mm:ss.SSS');
    final healthColor = _healthColor(querierStatus.health);
    final healthTextColor = _healthTextColor(querierStatus.health);
    final accentHighlight = AppTheme.isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;

    return Column(
      children: [
        // Querier Health & Watchdog Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(
              bottom: BorderSide(color: AppTheme.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: healthColor.withValues(alpha: AppTheme.isDark ? 0.15 : 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: healthColor.withValues(alpha: AppTheme.isDark ? 1.0 : 0.65)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                querierStatus.health == QuerierHealth.active
                                    ? Icons.check_circle
                                    : (querierStatus.health == QuerierHealth.warning
                                        ? Icons.warning_amber
                                        : Icons.info_outline),
                                size: 15,
                                color: healthColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                querierStatus.health.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: healthTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (querierStatus.querierIp != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Querier IP: ',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              Text(
                                querierStatus.querierIp!,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (querierStatus.querierVersion != IgmpProtocolVersion.unknown) ...[
                                const SizedBox(width: 8),
                                _IgmpVersionPill(version: querierStatus.querierVersion),
                              ],
                            ],
                          ),
                        if (querierStatus.secondsSinceLastQuery != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Last Query: ',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              Text(
                                '${querierStatus.secondsSinceLastQuery}s ago',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: accentHighlight,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // TShark Sniffer Toggle
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vm.isSnifferRunning
                          ? (AppTheme.isDark ? const Color(0xFF8B0000) : AppTheme.error)
                          : AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: Icon(vm.isSnifferRunning ? Icons.stop : Icons.radar, size: 14),
                    label: Text(
                      vm.isSnifferRunning ? 'Stop IGMP Sniffer' : 'Start IGMP Sniffer',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => vm.toggleSniffer(),
                  ),
                  const SizedBox(width: 8),

                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.borderStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Clear Log', style: TextStyle(fontSize: 12)),
                    onPressed: events.isEmpty ? null : () => vm.clearIgmpLogs(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                querierStatus.statusMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: querierStatus.health == QuerierHealth.critical
                      ? (AppTheme.isDark ? const Color(0xFFFF8B8B) : AppTheme.error)
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Table Header
        Container(
          color: AppTheme.surfaceHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 96, child: Text('Timestamp', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Text('Querier / Sender IP', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Text('Destination IP', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Text('IGMP Message Type', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Text('Group Address', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SizedBox(width: 82, child: Text('Max Resp', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SizedBox(width: 82, child: Text('Version', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Text('QQIC / QRV', style: AppTheme.tableHeaderStyle, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),

        // Table List
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radar, size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text(
                        'No IGMP Packets Logged Yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vm.isSnifferRunning
                            ? 'Listening for periodic IGMP Membership Queries (sent every 60s–125s by your switch/router)...'
                            : (vm.hasTShark
                                ? 'Click "Start IGMP Sniffer" above to start live packet capture.'
                                : 'Wireshark/TShark not found on PATH. Install Wireshark to enable raw IGMP capture.'),
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.border),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return _IgmpTableRow(event: event, timeFormat: timeFormat, index: index);
                  },
                ),
        ),
      ],
    );
  }
}

class _IgmpVersionPill extends StatelessWidget {
  final IgmpProtocolVersion version;
  final String? fallbackLabel;

  const _IgmpVersionPill({
    required this.version,
    this.fallbackLabel,
  });

  Color _colorForVersion(IgmpProtocolVersion ver) {
    final bool isDark = AppTheme.isDark;
    switch (ver) {
      case IgmpProtocolVersion.igmpv1:
        return isDark ? const Color(0xFFFF9800) : const Color(0xFFB45309);
      case IgmpProtocolVersion.igmpv2:
        return isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
      case IgmpProtocolVersion.igmpv3:
        return isDark ? const Color(0xFF10B981) : const Color(0xFF047857);
      case IgmpProtocolVersion.unknown:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForVersion(version);
    final label = version != IgmpProtocolVersion.unknown
        ? version.label
        : (fallbackLabel != null && fallbackLabel!.isNotEmpty ? fallbackLabel! : version.label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppTheme.isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class _IgmpTableRow extends StatelessWidget {
  final IgmpQueryEvent event;
  final DateFormat timeFormat;
  final int index;

  const _IgmpTableRow({
    required this.event,
    required this.timeFormat,
    required this.index,
  });

  String _formatV3Details() {
    final details = <String>[];
    if (event.qqicSeconds != null) {
      details.add('QQIC ${event.qqicSeconds}s');
    }
    if (event.qrv != null) {
      details.add('QRV ${event.qrv}');
    }
    if (event.suppressRouterProcessing) {
      details.add('S');
    }
    if (event.sourceAddresses.isNotEmpty) {
      details.add('${event.sourceAddresses.length} src');
    }
    return details.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    Color typeColor = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
    if (event.isGeneralQuery) {
      typeColor = isDark ? const Color(0xFF4CAF50) : AppTheme.success;
    } else if (event.typeName.contains('Leave')) {
      typeColor = isDark ? const Color(0xFFFF9800) : const Color(0xFFB45309);
    }

    final v3DetailsColor = isDark ? const Color(0xFF80CBC4) : const Color(0xFF0F766E);
    final v3Details = _formatV3Details();
    final tooltipParts = <String>[
      if (v3Details.isNotEmpty) v3Details,
      if (event.suppressRouterProcessing) 'Suppress Router-Side Processing (S=1)',
      if (event.sourceAddresses.isNotEmpty) 'Sources: ${event.sourceAddresses.join(', ')}',
    ];

    Widget v3DetailsCell = v3Details.isEmpty
        ? Text('—', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary))
        : Text(
            v3Details,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: v3DetailsColor,
            ),
          );

    if (tooltipParts.isNotEmpty) {
      v3DetailsCell = Tooltip(
        message: tooltipParts.join('\n'),
        child: v3DetailsCell,
      );
    }

    return Container(
      color: index.isEven ? AppTheme.surface : AppTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              timeFormat.format(event.timestamp),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              event.querierIp,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              event.destinationIp,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: typeColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event.typeName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              event.groupAddress,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              event.isQuery ? '${event.maxRespTimeSeconds.toStringAsFixed(1)} s' : '—',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _IgmpVersionPill(
                version: event.protocolVersion,
                fallbackLabel: event.version,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: v3DetailsCell,
          ),
        ],
      ),
    );
  }
}
