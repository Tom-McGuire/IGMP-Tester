import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class SenderPanel extends StatefulWidget {
  const SenderPanel({super.key});

  @override
  State<SenderPanel> createState() => _SenderPanelState();
}

class _SenderPanelState extends State<SenderPanel> {
  late TextEditingController _groupCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _rateCtrl;
  late TextEditingController _sizeCtrl;
  late TextEditingController _ttlCtrl;

  @override
  void initState() {
    super.initState();
    final vm = context.read<IgmpTesterViewModel>();
    _groupCtrl = TextEditingController(text: vm.senderConfig.groupAddress);
    _portCtrl = TextEditingController(text: vm.senderConfig.port.toString());
    _rateCtrl = TextEditingController(text: vm.senderConfig.packetsPerSecond.toString());
    _sizeCtrl = TextEditingController(text: vm.senderConfig.packetSizeBytes.toString());
    _ttlCtrl = TextEditingController(text: vm.senderConfig.ttl.toString());
  }

  @override
  void dispose() {
    _groupCtrl.dispose();
    _portCtrl.dispose();
    _rateCtrl.dispose();
    _sizeCtrl.dispose();
    _ttlCtrl.dispose();
    super.dispose();
  }

  void _applyConfig() {
    final vm = context.read<IgmpTesterViewModel>();
    final newConfig = vm.senderConfig.copyWith(
      groupAddress: _groupCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 5004,
      packetsPerSecond: int.tryParse(_rateCtrl.text.trim()) ?? 50,
      packetSizeBytes: int.tryParse(_sizeCtrl.text.trim()) ?? 256,
      ttl: int.tryParse(_ttlCtrl.text.trim()) ?? 64,
    );
    vm.updateSenderConfig(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isRunning = vm.isSenderRunning;
    final stats = vm.senderStats;

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
                  Icon(Icons.send_rounded, color: Color(0xFF007ACC), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Multicast Transmitter Configuration',
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

          // Config Cards
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Multicast Group IP
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Multicast Group Address',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _groupCtrl,
                              enabled: !isRunning,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.group_work, size: 16),
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

                      // TTL / Hops
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Multicast TTL (Hops)',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ttlCtrl,
                              enabled: !isRunning,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.timeline, size: 16),
                                hintText: '64',
                              ),
                              onChanged: (_) => _applyConfig(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Loopback Toggle
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
                                value: vm.senderConfig.enableLoopback,
                                onChanged: isRunning
                                    ? null
                                    : (val) {
                                        vm.updateSenderConfig(
                                          vm.senderConfig.copyWith(enableLoopback: val),
                                        );
                                      },
                              ),
                              Text(
                                vm.senderConfig.enableLoopback ? 'Local Rx On' : 'Off',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Packet Rate and Packet Size
                  Row(
                    children: [
                      // Packet Rate
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Transmission Rate (Packets / Second)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  '${vm.senderConfig.packetsPerSecond} pps',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF007ACC),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: vm.senderConfig.packetsPerSecond.toDouble().clamp(1.0, 1000.0),
                              min: 1.0,
                              max: 1000.0,
                              divisions: 100,
                              onChanged: isRunning
                                  ? null
                                  : (val) {
                                      _rateCtrl.text = val.round().toString();
                                      _applyConfig();
                                    },
                            ),
                            // Quick buttons
                            Row(
                              children: [10, 50, 100, 250, 500].map((rate) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: isRunning
                                        ? null
                                        : () {
                                            _rateCtrl.text = rate.toString();
                                            _applyConfig();
                                          },
                                    child: Text('$rate pps', style: const TextStyle(fontSize: 10)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),

                      // Packet Size
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Packet Payload Size (Bytes)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  '${vm.senderConfig.packetSizeBytes} bytes',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF007ACC),
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: vm.senderConfig.packetSizeBytes.toDouble().clamp(64.0, 1472.0),
                              min: 64.0,
                              max: 1472.0,
                              divisions: 44,
                              onChanged: isRunning
                                  ? null
                                  : (val) {
                                      _sizeCtrl.text = val.round().toString();
                                      _applyConfig();
                                    },
                            ),
                            // Quick sizes
                            Row(
                              children: [64, 128, 256, 512, 1400].map((sz) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: isRunning
                                        ? null
                                        : () {
                                            _sizeCtrl.text = sz.toString();
                                            _applyConfig();
                                          },
                                    child: Text('$sz B', style: const TextStyle(fontSize: 10)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Control Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? const Color(0xFF8B0000) : const Color(0xFF007ACC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 20),
              label: Text(
                isRunning ? 'STOP TRANSMITTING' : 'START TRANSMITTING MULTICAST STREAM',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              onPressed: () => vm.toggleSender(),
            ),
          ),
          const SizedBox(height: 24),

          // Live Metrics Section
          const Text(
            'Live Transmission Telemetry',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              _MetricCard(
                title: 'Packets Sent',
                value: stats.packetsSent.toString(),
                unit: 'packets',
                icon: Icons.upload_file,
                color: const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Current Send Rate',
                value: stats.currentPps.toStringAsFixed(1),
                unit: 'pps',
                icon: Icons.speed,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Bandwidth Out',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: const Color(0xFF9C27B0),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Total Volume',
                value: (stats.bytesSent / (1024 * 1024)).toStringAsFixed(2),
                unit: 'MB',
                icon: Icons.data_usage,
                color: const Color(0xFFFF9800),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Session Info Banner
          if (stats.activeSessionId.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Active Session ID: ${stats.activeSessionId}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                  ),
                  const Spacer(),
                  Text(
                    'Uptime: ${stats.duration.inMinutes}:${(stats.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
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
          color: selected ? const Color(0xFF007ACC).withValues(alpha: 0.2) : const Color(0xFF252526),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? const Color(0xFF007ACC) : const Color(0xFF3E3E42),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? const Color(0xFF4FC1FF) : Colors.white70,
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
