import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../view_models/igmp_tester_view_model.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';

class TopControlBar extends StatelessWidget {
  const TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? const Color(0xFF2C2C2C)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // App Title & Brand
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF007ACC).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.hub_outlined, color: Color(0xFF007ACC), size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IGMP & Multicast Tester',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Multi-Stream & Saturation Engine',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(width: 24),

            // Network Interface Selector
            const Icon(Icons.settings_ethernet, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            const Text(
              'Interface:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<NetworkInterfaceInfo>(
                  value: vm.selectedInterface,
                  isDense: true,
                  dropdownColor: const Color(0xFF252526),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  items: vm.interfaces.map((iface) {
                    return DropdownMenuItem<NetworkInterfaceInfo>(
                      value: iface,
                      child: Text(iface.displayName),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) vm.selectInterface(val);
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
              tooltip: 'Refresh Network Interfaces',
              onPressed: () => vm.refreshInterfaces(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            const SizedBox(width: 24),

            // Status Badges
            _StatusPill(
              icon: Icons.upload,
              label: vm.isSenderRunning
                  ? 'Tx: ${vm.senderStats.activeStreamsCount} active (${vm.senderStats.currentBitrateMbps.toStringAsFixed(1)}M)'
                  : 'Tx Idle (${vm.senderConfig.streams.length} strms)',
              isActive: vm.isSenderRunning,
              activeColor: const Color(0xFF4CAF50),
            ),
            const SizedBox(width: 8),

            _StatusPill(
              icon: Icons.download,
              label: vm.isReceiverRunning
                  ? 'Rx: ${vm.receiverStats.activeStreamsCount} grps (${vm.receiverStats.lossRatePercent.toStringAsFixed(1)}% loss)'
                  : 'Rx Idle (${vm.receiverConfig.streams.length} grps)',
              isActive: vm.isReceiverRunning,
              activeColor: vm.receiverStats.lossRatePercent > 0
                  ? const Color(0xFFFF9800)
                  : const Color(0xFF2196F3),
            ),
            const SizedBox(width: 8),

            _StatusPill(
              icon: Icons.router,
              label: vm.querierStatus.health.label,
              isActive: vm.querierStatus.health == QuerierHealth.active,
              activeColor: Color(vm.querierStatus.health.colorHex),
            ),
            const SizedBox(width: 12),

            // Stop all button if any active
            if (vm.isSenderRunning || vm.isReceiverRunning || vm.isSnifferRunning)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B0000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.stop, size: 14),
                label: const Text('Stop All', style: TextStyle(fontSize: 12)),
                onPressed: () => vm.stopAll(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withValues(alpha: 0.12) : const Color(0xFF252526),
        border: Border.all(
          color: isActive ? activeColor.withValues(alpha: 0.6) : const Color(0xFF3E3E42),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isActive ? activeColor : Colors.grey.shade400,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? activeColor : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
