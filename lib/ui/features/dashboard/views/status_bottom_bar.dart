import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../view_models/igmp_tester_view_model.dart';

class StatusBottomBar extends StatelessWidget {
  const StatusBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final tsharkColor = vm.hasTShark ? AppTheme.success : AppTheme.warning;
    final tsharkLabelColor = vm.hasTShark
        ? (AppTheme.isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : (AppTheme.isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        border: Border(
          top: BorderSide(color: AppTheme.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Interface info
            Icon(Icons.lan_outlined, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              vm.selectedInterface != null
                  ? '${vm.selectedInterface!.name} (${vm.selectedInterface!.ip})'
                  : 'No Interface Selected',
              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 16),
            Text('•', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            const SizedBox(width: 16),

            // Active Groups
            Text(
              'Streams: ${vm.senderConfig.streams.length} Tx | ${vm.receiverConfig.streams.length} Rx Groups',
              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 16),
            Text('•', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            const SizedBox(width: 16),

            // Total throughput summary
            Text(
              'Tx: ${vm.senderStats.activeStreamsCount} active (${vm.senderStats.currentBitrateMbps.toStringAsFixed(2)} Mbps) | Rx: ${vm.receiverStats.activeStreamsCount} active (${vm.receiverStats.currentBitrateMbps.toStringAsFixed(2)} Mbps)',
              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 24),

            // TShark status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tsharkColor.withValues(alpha: AppTheme.isDark ? 0.16 : 0.12),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: tsharkColor.withValues(alpha: AppTheme.isDark ? 0.7 : 0.55),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    vm.hasTShark ? Icons.check_circle : Icons.warning_amber,
                    size: 11,
                    color: tsharkColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    vm.hasTShark ? 'TShark Sniffer: Available' : 'TShark: Not Found',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: tsharkLabelColor,
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
