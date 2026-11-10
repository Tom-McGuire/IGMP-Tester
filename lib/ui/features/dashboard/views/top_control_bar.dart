import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../view_models/igmp_tester_view_model.dart';
import 'dialogs/device_library_dialog.dart';

class TopControlBar extends StatelessWidget {
  const TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isAnyRunning = vm.isAnyRunning;

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C), width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveMinWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - 32).clamp(0.0, double.infinity)
              : 0.0;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 32,
                            height: 32,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007ACC).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.hub_outlined, color: Color(0xFF007ACC), size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IGMP & Multicast Tester',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Multi-Stream & Saturation Engine',
                            style: TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),

                      // ==================== ZONE 2: INTERFACE & TARGET ====================
                      Container(
                        width: 200,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252526),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF3E3E42)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.settings_ethernet, size: 15, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<NetworkInterfaceInfo>(
                                  value: vm.selectedInterface,
                                  isDense: true,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF252526),
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
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
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                        tooltip: 'Refresh Interfaces',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => vm.refreshInterfaces(),
                      ),
                      const SizedBox(width: 12),

                      // ==================== ZONE 3: PRIMARY ACTIONS ====================
                      FilledButton.icon(
                        onPressed: () {
                          if (isAnyRunning) {
                            vm.stopAll();
                          } else {
                            vm.startAll();
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: isAnyRunning
                              ? const Color(0xFFEF4444) // Active Red
                              : const Color(0xFF10B981), // Idle Emerald Green (from ARP Scout)
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: Icon(isAnyRunning ? Icons.stop : Icons.play_arrow, size: 17),
                        label: Text(
                          isAnyRunning ? 'Stop All' : 'Start All',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  // ==================== RIGHT CLUSTER (ZONES 4, 5) ====================
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
                      OutlinedButton.icon(
                        onPressed: () => DeviceLibraryDialog.show(context),
                        icon: const Icon(Icons.devices, size: 15),
                        label: const Text('Device Library', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: isAnyRunning
                            ? null
                            : () {
                                vm.loadDemo();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Loaded 10 demo multicast test streams (Tx & Rx)'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.play_circle_outline, size: 15),
                        label: const Text('Load Demo', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ==================== ZONE 5: CLEAR & EXPORT ====================
                      OutlinedButton.icon(
                        onPressed: (isAnyRunning || (vm.gaps.isEmpty && vm.igmpEvents.isEmpty))
                            ? null
                            : () {
                                vm.clearGaps();
                                vm.clearIgmpLogs();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cleared gap logs and IGMP events'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                        label: const Text('Clear', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Export Menu (Styled as bordered chip per specification)
                      PopupMenuButton<String>(
                        tooltip: 'Export',
                        enabled: vm.gaps.isNotEmpty ||
                            vm.igmpEvents.isNotEmpty ||
                            vm.senderConfig.streams.isNotEmpty,
                        onSelected: (val) async {
                          if (val == 'csv') {
                            try {
                              final defaultFileName =
                                  'multicast_gaps_${DateTime.now().millisecondsSinceEpoch}.csv';
                              final csvContent = vm.generateGapsCsvContent();
                              final uri = await FilePicker.saveFile(
                                dialogTitle: 'Export Gaps CSV',
                                fileName: defaultFileName,
                                bytes: Uint8List.fromList(utf8.encode(csvContent)),
                              );
                              if (uri != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Gap report saved successfully.'),
                                    backgroundColor: Color(0xFF2E7D32),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          } else if (val == 'clipboard') {
                            final csv = vm.generateGapsCsvContent();
                            await Clipboard.setData(ClipboardData(text: csv));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Gaps CSV copied to clipboard')),
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'csv',
                            child: Row(
                              children: [
                                Icon(Icons.table_chart, size: 16),
                                SizedBox(width: 8),
                                Text('Export Gaps as CSV...', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clipboard',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Copy Gaps CSV to Clipboard', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2C2C2C)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 15, color: Colors.white70),
                              SizedBox(width: 6),
                              Text('Export', style: TextStyle(fontSize: 11, color: Colors.white70)),
                              Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
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
