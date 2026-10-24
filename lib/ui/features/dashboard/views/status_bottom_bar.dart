import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/igmp_tester_view_model.dart';

class StatusBottomBar extends StatelessWidget {
  const StatusBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: theme.dividerTheme.color ?? const Color(0xFF2C2C2C)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Interface info
            const Icon(Icons.lan_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              vm.selectedInterface != null
                  ? '${vm.selectedInterface!.name} (${vm.selectedInterface!.ip})'
                  : 'No Interface Selected',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(width: 16),
            const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(width: 16),

            // Active Group
            Text(
              'Group: ${vm.receiverConfig.groupAddress}:${vm.receiverConfig.port}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(width: 16),
            const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(width: 16),

            // Total throughput summary
            Text(
              'Tx: ${vm.senderStats.currentBitrateMbps.toStringAsFixed(2)} Mbps | Rx: ${vm.receiverStats.currentBitrateMbps.toStringAsFixed(2)} Mbps',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(width: 24),

            // TShark status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: vm.hasTShark ? const Color(0xFF1E3A1E) : const Color(0xFF332A15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: vm.hasTShark ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    vm.hasTShark ? Icons.check_circle : Icons.warning_amber,
                    size: 11,
                    color: vm.hasTShark ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    vm.hasTShark ? 'TShark Sniffer: Available' : 'TShark: Not Found',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: vm.hasTShark ? const Color(0xFF81C784) : const Color(0xFFFFB74D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
