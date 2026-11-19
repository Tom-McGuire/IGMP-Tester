import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';
import '../../../../domain/models/igmp_query_event.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/csv_export_helper.dart';
import '../view_models/igmp_tester_view_model.dart';
import 'dialogs/device_library_dialog.dart';

class TopControlBar extends StatelessWidget {
  final GlobalKey? interfaceSelectorKey;
  final GlobalKey? masterStartStopKey;

  const TopControlBar({
    super.key,
    this.interfaceSelectorKey,
    this.masterStartStopKey,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isAnyRunning = vm.isAnyRunning;
    final canClear = !isAnyRunning &&
        (vm.gaps.isNotEmpty ||
            vm.igmpEvents.isNotEmpty ||
            vm.lastLeaveLatency != null);
    final canExport = vm.gaps.isNotEmpty ||
        vm.igmpEvents.isNotEmpty ||
        vm.senderConfig.streams.isNotEmpty ||
        vm.lastLeaveLatency != null;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveMinWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - 24).clamp(0.0, double.infinity)
              : 0.0;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: effectiveMinWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ==================== LEFT CLUSTER (ZONES 1, 2, 3) ====================
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ==================== ZONE 1: BRANDING ====================
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 28,
                            height: 28,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.hub_outlined, color: AppTheme.accent, size: 17),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IGMP & Multicast Tester',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Multi-Stream & Saturation Engine',
                            style: TextStyle(fontSize: 9.5, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),

                      // ==================== ZONE 2: INTERFACE & TARGET ====================
                      Container(
                        key: interfaceSelectorKey,
                        width: 175,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.borderStrong),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.settings_ethernet, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 5),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<NetworkInterfaceInfo>(
                                  value: vm.selectedInterface,
                                  isDense: true,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceElevated,
                                  iconEnabledColor: AppTheme.textSecondary,
                                  style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
                                  items: vm.interfaces.map((iface) {
                                    return DropdownMenuItem<NetworkInterfaceInfo>(
                                      value: iface,
                                      child: Text(
                                        iface.displayName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) vm.selectInterface(val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(Icons.refresh, size: 16, color: AppTheme.textSecondary),
                        tooltip: 'Refresh Interfaces',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => vm.refreshInterfaces(),
                      ),
                      const SizedBox(width: 8),

                      // ==================== ZONE 3: PRIMARY ACTIONS ====================
                      FilledButton.icon(
                        key: masterStartStopKey,
                        onPressed: () {
                          if (isAnyRunning) {
                            vm.stopAll();
                          } else {
                            vm.startAll();
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isAnyRunning
                              ? AppTheme.error // Active Red
                              : AppTheme.success, // Idle Emerald Green
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: Icon(isAnyRunning ? Icons.stop : Icons.play_arrow, size: 16),
                        label: Text(
                          isAnyRunning ? 'Stop All' : 'Start All',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _QuerierVersionPill(status: vm.querierStatus),
                    ],
                  ),

                  const SizedBox(width: 8),

                  // ==================== RIGHT CLUSTER (ZONES 4, 5) ====================
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
                      OutlinedButton.icon(
                        onPressed: () => DeviceLibraryDialog.show(context),
                        icon: const Icon(Icons.devices, size: 14),
                        label: const Text('Device Library', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: BorderSide(color: AppTheme.borderStrong),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: vm.isDemoMode
                            ? () => vm.endDemoWalkthrough()
                            : (isAnyRunning ? null : () => vm.startDemoWalkthrough()),
                        icon: Icon(
                          vm.isDemoMode
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          size: 15,
                          color: vm.isDemoMode ? AppTheme.warning : null,
                        ),
                        label: Text(
                          vm.isDemoMode ? 'Exit Demo' : 'Load Demo',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              vm.isDemoMode ? AppTheme.warning : AppTheme.textPrimary,
                          side: BorderSide(
                            color: vm.isDemoMode ? AppTheme.warning : AppTheme.borderStrong,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // ==================== ZONE 5: CLEAR & EXPORT ====================
                      OutlinedButton.icon(
                        onPressed: !canClear
                            ? null
                            : () {
                                vm.clearGaps();
                                vm.clearIgmpLogs();
                                vm.clearLeaveLatencyResults();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cleared gap logs and IGMP events'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                        label: const Text('Clear', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: BorderSide(
                            color: canClear ? AppTheme.borderStrong : AppTheme.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Export Menu (Styled as bordered chip per specification)
                      PopupMenuButton<String>(
                        tooltip: 'Export',
                        enabled: canExport,
                        constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
                        onSelected: (val) async {
                          if (val == 'csv') {
                            await exportGapsCsvWithFeedback(
                              context,
                              vm,
                              dialogTitle: 'Export Gaps CSV',
                            );
                          } else if (val == 'clipboard') {
                            await copyGapsCsvToClipboard(context, vm);
                          } else if (val == 'igmp_json') {
                            await copyIgmpLogJsonToClipboard(context, vm);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'csv',
                            child: Row(
                              children: [
                                Icon(Icons.table_chart, size: 16),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Export Gaps as CSV...',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clipboard',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Copy Gaps CSV to Clipboard',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'igmp_json',
                            child: Row(
                              children: [
                                Icon(Icons.data_object, size: 16),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Copy IGMP Log as JSON',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: canExport ? AppTheme.borderStrong : AppTheme.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download,
                                size: 14,
                                color: canExport ? AppTheme.textPrimary : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Export',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: canExport ? AppTheme.textPrimary : AppTheme.textMuted,
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 14,
                                color: canExport ? AppTheme.textPrimary : AppTheme.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuerierVersionPill extends StatelessWidget {
  final QuerierStatus status;

  const _QuerierVersionPill({required this.status});

  Color _versionColor(IgmpProtocolVersion version) {
    switch (version) {
      case IgmpProtocolVersion.igmpv3:
        return AppTheme.success;
      case IgmpProtocolVersion.igmpv2:
        return AppTheme.warning;
      case IgmpProtocolVersion.igmpv1:
        return AppTheme.isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C);
      case IgmpProtocolVersion.unknown:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthColor = status.health == QuerierHealth.idle
        ? AppTheme.textMuted
        : Color(status.health.colorHex);
    final versionColor = _versionColor(status.querierVersion);
    final hostLabel = status.querierIp != null
        ? 'Querier: ${status.querierIp}'
        : 'Querier: Idle';

    return Tooltip(
      message: '${status.statusMessage} (${status.displayBadge})',
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: versionColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: healthColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                hostLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: versionColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status.displayBadge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: versionColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
