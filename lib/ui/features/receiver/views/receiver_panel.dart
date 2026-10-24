import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class ReceiverPanel extends StatefulWidget {
  const ReceiverPanel({super.key});

  @override
  State<ReceiverPanel> createState() => _ReceiverPanelState();
}

class _ReceiverPanelState extends State<ReceiverPanel> {
  late TextEditingController _groupCtrl;
  late TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    final vm = context.read<IgmpTesterViewModel>();
    _groupCtrl = TextEditingController(text: vm.receiverConfig.groupAddress);
    _portCtrl = TextEditingController(text: vm.receiverConfig.port.toString());
  }

  @override
  void dispose() {
    _groupCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _applyConfig() {
    final vm = context.read<IgmpTesterViewModel>();
    final newConfig = vm.receiverConfig.copyWith(
      groupAddress: _groupCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 5004,
    );
    vm.updateReceiverConfig(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isRunning = vm.isReceiverRunning;
    final stats = vm.receiverStats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Presets
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_received_rounded, color: Color(0xFF2196F3), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Multicast Receiver & IGMP Join Configuration',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              // Presets
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _PresetChip(
                    label: 'Org-Local (239.255.0.1)',
                    selected: _groupCtrl.text == '239.255.0.1',
                    onTap: isRunning
                        ? null
                        : () {
                            _groupCtrl.text = '239.255.0.1';
                            _applyConfig();
                          },
                  ),
                  _PresetChip(
                    label: 'Site-Local (239.192.0.1)',
                    selected: _groupCtrl.text == '239.192.0.1',
                    onTap: isRunning
                        ? null
                        : () {
                            _groupCtrl.text = '239.192.0.1';
                            _applyConfig();
                          },
                  ),
                  _PresetChip(
                    label: 'Test Group (239.1.1.1)',
                    selected: _groupCtrl.text == '239.1.1.1',
                    onTap: isRunning
                        ? null
                        : () {
                            _groupCtrl.text = '239.1.1.1';
                            _applyConfig();
                          },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Receiver Config Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Multicast Group Address
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Multicast Group to Join (IGMP Membership Report)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _groupCtrl,
                          enabled: !isRunning,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.hub, size: 16),
                            hintText: '239.255.0.1',
                          ),
                          onChanged: (_) => _applyConfig(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // UDP Port
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UDP Port',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _portCtrl,
                          enabled: !isRunning,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.numbers, size: 16),
                            hintText: '5004',
                          ),
                          onChanged: (_) => _applyConfig(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Loopback switch
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Multicast Loopback',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Switch(
                            value: vm.receiverConfig.enableLoopback,
                            onChanged: isRunning
                                ? null
                                : (val) {
                                    vm.updateReceiverConfig(
                                      vm.receiverConfig.copyWith(enableLoopback: val),
                                    );
                                  },
                          ),
                          Text(
                            vm.receiverConfig.enableLoopback ? 'Local Rx On' : 'Off',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Receiver Master Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? const Color(0xFF8B0000) : const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 20),
              label: Text(
                isRunning
                    ? 'LEAVE GROUP & STOP RECEIVER'
                    : 'JOIN MULTICAST GROUP & START RECEIVING',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              onPressed: () => vm.toggleReceiver(),
            ),
          ),
          const SizedBox(height: 24),

          // Telemetry Cards Grid
          const Text(
            'Live Reception Quality & Gap Metrics',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          // Row 1: Primary Delivery Health
          Row(
            children: [
              _MetricCard(
                title: 'Packets Received',
                value: '${stats.packetsReceived} / ${stats.expectedPackets}',
                unit: 'pkts',
                icon: Icons.check_circle_outline,
                color: const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Packet Loss Rate',
                value: '${stats.lossRatePercent.toStringAsFixed(2)}%',
                unit: '${stats.packetsLost} dropped',
                icon: Icons.warning_amber_rounded,
                color: stats.lossRatePercent > 0
                    ? (stats.lossRatePercent > 5.0 ? const Color(0xFFF44336) : const Color(0xFFFF9800))
                    : const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Total Gaps Detected',
                value: stats.totalGaps.toString(),
                unit: 'loss events',
                icon: Icons.broken_image_outlined,
                color: stats.totalGaps > 0 ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Worst / Max Gap',
                value: stats.maxGapDurationMs.toStringAsFixed(1),
                unit: 'ms (${stats.maxGapPackets} pkts)',
                icon: Icons.timer_outlined,
                color: const Color(0xFFE91E63),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Inbound Rate & Network Timing
          Row(
            children: [
              _MetricCard(
                title: 'Arrival Rate',
                value: stats.currentPps.toStringAsFixed(1),
                unit: 'pps',
                icon: Icons.speed,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Inbound Throughput',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: const Color(0xFF9C27B0),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'RFC 3550 Jitter',
                value: stats.jitterMs.toStringAsFixed(3),
                unit: 'ms',
                icon: Icons.waves,
                color: const Color(0xFF00BCD4),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Duplicates / OoO',
                value: '${stats.duplicatePackets} / ${stats.outOfOrderPackets}',
                unit: 'frames',
                icon: Icons.repeat,
                color: Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Inbound Bitrate Sparkline Chart
          Container(
            height: 140,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Live Inbound Throughput Stability (Mbps)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    Text(
                      'Current: ${stats.currentBitrateMbps.toStringAsFixed(2)} Mbps',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2196F3)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vm.rxThroughputHistory.length < 2
                      ? Center(
                          child: Text(
                            isRunning ? 'Collecting throughput telemetry...' : 'Receiver is idle',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        )
                      : LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: vm.rxThroughputHistory
                                    .asMap()
                                    .entries
                                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                                    .toList(),
                                isCurved: true,
                                color: const Color(0xFF2196F3),
                                barWidth: 2,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2196F3).withValues(alpha: 0.2) : const Color(0xFF252526),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? const Color(0xFF2196F3) : const Color(0xFF3E3E42),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? const Color(0xFF64B5F6) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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
