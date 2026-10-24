import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class SenderPanel extends StatelessWidget {
  const SenderPanel({super.key});

  void _showAddStreamDialog(BuildContext context, IgmpTesterViewModel vm) {
    final nameCtrl = TextEditingController(text: 'Stream ${vm.senderConfig.streams.length + 1}');
    final groupCtrl = TextEditingController(
      text: vm.senderConfig.streams.isEmpty
          ? '239.255.0.1'
          : MulticastStreamConfig.incrementIp(vm.senderConfig.streams.last.groupAddress, 1),
    );
    final portCtrl = TextEditingController(text: '5004');
    final rateCtrl = TextEditingController(text: '50');
    final sizeCtrl = TextEditingController(text: '256');
    final ttlCtrl = TextEditingController(text: '64');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: Color(0xFF007ACC), size: 20),
            SizedBox(width: 8),
            Text('Add Multicast Stream', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Stream Name', hintText: 'Stream 1'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: groupCtrl,
                decoration: const InputDecoration(labelText: 'Multicast Group IP', hintText: '239.255.0.1'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'UDP Port', hintText: '5004'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ttlCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'TTL (Hops)', hintText: '64'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rate (PPS)', hintText: '50'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sizeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Size (Bytes)', hintText: '256'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
            onPressed: () {
              final newStream = MulticastStreamConfig(
                id: 'stream_${DateTime.now().millisecondsSinceEpoch}',
                name: nameCtrl.text.trim().isEmpty ? 'Stream' : nameCtrl.text.trim(),
                groupAddress: groupCtrl.text.trim().isEmpty ? '239.255.0.1' : groupCtrl.text.trim(),
                port: int.tryParse(portCtrl.text.trim()) ?? 5004,
                packetsPerSecond: int.tryParse(rateCtrl.text.trim()) ?? 50,
                packetSizeBytes: int.tryParse(sizeCtrl.text.trim()) ?? 256,
                ttl: int.tryParse(ttlCtrl.text.trim()) ?? 64,
              );
              vm.addSenderStream(newStream);
              Navigator.pop(ctx);
            },
            child: const Text('Add Stream', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBatchDialog(BuildContext context, IgmpTesterViewModel vm) {
    final countCtrl = TextEditingController(text: '10');
    final startIpCtrl = TextEditingController(text: '239.255.0.1');
    final portCtrl = TextEditingController(text: '5004');
    final rateCtrl = TextEditingController(text: '50');
    final sizeCtrl = TextEditingController(text: '256');
    bool incrementPort = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome_motion, color: Color(0xFF007ACC), size: 20),
              SizedBox(width: 8),
              Text('Batch Generate Saturation Streams', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Instantly generate multiple multicast streams across a block of addresses to test switch IGMP snooping table capacity and network saturation.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: countCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stream Count (e.g. 10)', hintText: '10'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: startIpCtrl,
                        decoration: const InputDecoration(labelText: 'Starting Group IP', hintText: '239.255.0.1'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: portCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Base UDP Port', hintText: '5004'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Rate per Stream (PPS)', hintText: '50'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: sizeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Packet Size (Bytes)', hintText: '256'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Increment UDP port for each stream (port + 1)', style: TextStyle(fontSize: 12)),
                  value: incrementPort,
                  onChanged: (val) {
                    setDialogState(() {
                      incrementPort = val ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
              onPressed: () {
                final count = int.tryParse(countCtrl.text.trim()) ?? 10;
                final startIp = startIpCtrl.text.trim().isEmpty ? '239.255.0.1' : startIpCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ?? 5004;
                final pps = int.tryParse(rateCtrl.text.trim()) ?? 50;
                final size = int.tryParse(sizeCtrl.text.trim()) ?? 256;

                vm.batchGenerateSenderStreams(
                  count: count.clamp(1, 100),
                  startingIp: startIp,
                  basePort: port,
                  pps: pps.clamp(1, 2000),
                  packetSize: size.clamp(64, 1472),
                  incrementPort: incrementPort,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Generate Streams', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isRunning = vm.isSenderRunning;
    final stats = vm.senderStats;
    final streams = vm.senderConfig.streams;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Toolbar
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
                    'Multicast Transmission & Saturation Control',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Loopback switch
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Loopback:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 4),
                      Switch(
                        value: vm.senderConfig.enableLoopback,
                        onChanged: isRunning ? null : (val) => vm.updateSenderLoopback(val),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Add Stream button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4FC1FF),
                      side: const BorderSide(color: Color(0xFF007ACC)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Stream', style: TextStyle(fontSize: 11)),
                    onPressed: isRunning ? null : () => _showAddStreamDialog(context, vm),
                  ),
                  const SizedBox(width: 8),

                  // Batch Generator button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFB74D),
                      side: const BorderSide(color: Color(0xFFFF9800)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.auto_awesome_motion, size: 14),
                    label: const Text('Batch Generator', style: TextStyle(fontSize: 11)),
                    onPressed: isRunning ? null : () => _showBatchDialog(context, vm),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Aggregate Metrics Section
          Row(
            children: [
              _MetricCard(
                title: 'Active Streams',
                value: '${stats.activeStreamsCount} / ${streams.length}',
                unit: 'streams',
                icon: Icons.layers_outlined,
                color: const Color(0xFF007ACC),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Combined Rate',
                value: stats.currentPps.toStringAsFixed(0),
                unit: 'pps',
                icon: Icons.speed,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Aggregate Bandwidth',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: const Color(0xFF9C27B0),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Total Outbound',
                value: (stats.bytesSent / (1024 * 1024)).toStringAsFixed(2),
                unit: 'MB (${stats.packetsSent} pkts)',
                icon: Icons.data_usage,
                color: const Color(0xFF4CAF50),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Master Action Bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRunning ? const Color(0xFF8B0000) : const Color(0xFF007ACC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 18),
                    label: Text(
                      isRunning
                          ? 'STOP ALL TRANSMITTING STREAMS'
                          : 'START TRANSMITTING ALL STREAMS (${streams.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: streams.isEmpty ? null : () => vm.toggleSender(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stream Registry Table Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Configured Multicast Streams (${streams.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              if (streams.isNotEmpty)
                Text(
                  'Individual controls allow starting or pausing specific groups',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Table Content
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: Column(
              children: [
                // Table Columns
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF252526),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 40, child: Text('Status', style: _headerStyle)),
                      Expanded(flex: 3, child: Text('Stream Name', style: _headerStyle)),
                      Expanded(flex: 4, child: Text('Multicast Group & Port', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Rate', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Payload', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Bitrate', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Sent Pkts', style: _headerStyle)),
                      SizedBox(width: 100, child: Text('Actions', style: _headerStyle)),
                    ],
                  ),
                ),

                if (streams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No multicast streams defined. Click "Add Stream" or "Batch Generator" above to configure test streams.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: streams.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF282828)),
                    itemBuilder: (context, index) {
                      final stream = streams[index];
                      final isStreamActive = vm.isSenderStreamActive(stream.id);
                      final sStats = vm.streamSenderStats[stream.id];

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: index % 2 == 0 ? const Color(0xFF1E1E1E) : const Color(0xFF1A1A1A),
                        child: Row(
                          children: [
                            // Status Indicator
                            SizedBox(
                              width: 40,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isStreamActive ? const Color(0xFF4CAF50) : const Color(0xFF555555),
                                ),
                              ),
                            ),

                            // Stream Name
                            Expanded(
                              flex: 3,
                              child: Text(
                                stream.name,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),

                            // Endpoint
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  const Icon(Icons.hub_outlined, size: 13, color: Color(0xFF007ACC)),
                                  const SizedBox(width: 4),
                                  Text(
                                    stream.endpoint,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF4FC1FF),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Rate
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${stream.packetsPerSecond} pps',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ),

                            // Payload size
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${stream.packetSizeBytes} B',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ),

                            // Bitrate
                            Expanded(
                              flex: 2,
                              child: Text(
                                sStats != null
                                    ? '${sStats.currentBitrateMbps.toStringAsFixed(2)} Mbps'
                                    : '0.00 Mbps',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: isStreamActive ? const Color(0xFF81C784) : Colors.grey,
                                ),
                              ),
                            ),

                            // Packets sent
                            Expanded(
                              flex: 2,
                              child: Text(
                                sStats != null ? sStats.packetsSent.toString() : '0',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ),

                            // Actions
                            SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      isStreamActive ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                      size: 18,
                                      color: isStreamActive ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
                                    ),
                                    tooltip: isStreamActive ? 'Pause Stream' : 'Start Stream',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () => vm.toggleIndividualSenderStream(stream.id),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                                    tooltip: 'Remove Stream',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: isStreamActive ? null : () => vm.removeSenderStream(stream.id),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: Colors.grey,
);

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
