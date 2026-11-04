import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class ReceiverPanel extends StatelessWidget {
  const ReceiverPanel({super.key});

  void _showAddGroupDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _AddReceiverGroupDialog(vm: vm),
    );
  }

  void _showBatchGroupDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _BatchReceiverGroupsDialog(vm: vm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isRunning = vm.isReceiverRunning;
    final stats = vm.receiverStats;
    final streams = vm.receiverConfig.streams;

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
                  Icon(Icons.call_received_rounded, color: Color(0xFF2196F3), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Multi-Group Multicast Receiver & IGMP Join Subscriptions',
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
                        value: vm.receiverConfig.enableLoopback,
                        onChanged: isRunning ? null : (val) => vm.updateReceiverLoopback(val),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Add Group button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64B5F6),
                      side: const BorderSide(color: Color(0xFF2196F3)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Group', style: TextStyle(fontSize: 11)),
                    onPressed: isRunning ? null : () => _showAddGroupDialog(context, vm),
                  ),
                  const SizedBox(width: 8),

                  // Batch Join Groups button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFB74D),
                      side: const BorderSide(color: Color(0xFFFF9800)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.auto_awesome_motion, size: 14),
                    label: const Text('Batch Join', style: TextStyle(fontSize: 11)),
                    onPressed: isRunning ? null : () => _showBatchGroupDialog(context, vm),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Aggregate Reception Telemetry
          Row(
            children: [
              _MetricCard(
                title: 'Subscribed Groups',
                value: '${stats.activeStreamsCount} / ${streams.length}',
                unit: 'groups',
                icon: Icons.hub,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Packets Received',
                value: '${stats.packetsReceived} / ${stats.expectedPackets}',
                unit: 'pkts',
                icon: Icons.check_circle_outline,
                color: const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Aggregate Loss Rate',
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
                unit: 'drop events',
                icon: Icons.broken_image_outlined,
                color: stats.totalGaps > 0 ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Inbound Rate & Network Timing
          Row(
            children: [
              _MetricCard(
                title: 'Aggregate Arrival Rate',
                value: stats.currentPps.toStringAsFixed(0),
                unit: 'pps',
                icon: Icons.speed,
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Total Inbound Bitrate',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: const Color(0xFF9C27B0),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                title: 'Average Jitter',
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

          // Master Receiver Action Button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRunning ? const Color(0xFF8B0000) : const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 18),
                    label: Text(
                      isRunning
                          ? 'LEAVE ALL MULTICAST GROUPS & STOP RECEIVERS'
                          : 'JOIN ALL MULTICAST GROUPS (${streams.length}) & START RECEIVING',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: streams.isEmpty ? null : () => vm.toggleReceiver(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stream Subscriptions Table Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subscribed Multicast Groups (${streams.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              if (streams.isNotEmpty)
                Text(
                  'Monitor continuity, drops, and jitter across each individual group',
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
                      Expanded(flex: 3, child: Text('Stream / Group Name', style: _headerStyle)),
                      Expanded(flex: 4, child: Text('Multicast Address & Port', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Received', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Loss %', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Gaps', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Bitrate', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Jitter', style: _headerStyle)),
                      SizedBox(width: 100, child: Text('Actions', style: _headerStyle)),
                    ],
                  ),
                ),

                if (streams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No multicast groups subscribed. Click "Add Group" or "Batch Join" above to configure groups.',
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
                      final isStreamActive = vm.isReceiverStreamActive(stream.id);
                      final rStats = vm.streamReceiverStats[stream.id];

                      final lossPct = rStats?.lossRatePercent ?? 0.0;
                      Color lossColor = const Color(0xFF4CAF50);
                      if (lossPct > 5.0) {
                        lossColor = const Color(0xFFF44336);
                      } else if (lossPct > 0.0) {
                        lossColor = const Color(0xFFFF9800);
                      }

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
                                  color: isStreamActive ? const Color(0xFF2196F3) : const Color(0xFF555555),
                                ),
                              ),
                            ),

                            // Group Name
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
                                  const Icon(Icons.hub, size: 13, color: Color(0xFF2196F3)),
                                  const SizedBox(width: 4),
                                  Text(
                                    stream.endpoint,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF64B5F6),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Received count
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null ? '${rStats.packetsReceived}' : '0',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ),

                            // Loss %
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null ? '${lossPct.toStringAsFixed(1)}%' : '0.0%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isStreamActive ? lossColor : Colors.grey,
                                ),
                              ),
                            ),

                            // Gaps count
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null ? '${rStats.totalGaps}' : '0',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (rStats?.totalGaps ?? 0) > 0 ? const Color(0xFFFF9800) : Colors.grey,
                                ),
                              ),
                            ),

                            // Bitrate
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null
                                    ? '${rStats.currentBitrateMbps.toStringAsFixed(2)} Mbps'
                                    : '0.00 Mbps',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: isStreamActive ? const Color(0xFF81C784) : Colors.grey,
                                ),
                              ),
                            ),

                            // Jitter
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null ? '${rStats.jitterMs.toStringAsFixed(2)} ms' : '—',
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
                                      isStreamActive ? Icons.stop_circle_outlined : Icons.play_circle_fill,
                                      size: 18,
                                      color: isStreamActive ? const Color(0xFFF44336) : const Color(0xFF2196F3),
                                    ),
                                    tooltip: isStreamActive ? 'Leave Group' : 'Join Group',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () => vm.toggleIndividualReceiverStream(stream.id),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                                    tooltip: 'Remove Group',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: isStreamActive ? null : () => vm.removeReceiverStream(stream.id),
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
          const SizedBox(height: 16),

          // Live Inbound Bitrate Sparkline Chart
          Container(
            height: 130,
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
                      'Live Aggregate Inbound Throughput Stability (Mbps)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    Text(
                      'Aggregate: ${stats.currentBitrateMbps.toStringAsFixed(2)} Mbps',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2196F3)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vm.rxThroughputHistory.length < 2
                      ? Center(
                          child: Text(
                            isRunning ? 'Collecting aggregate throughput telemetry...' : 'Receivers are idle',
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

IconData _getProtocolPresetIcon(ProtocolPreset preset) {
  switch (preset.category) {
    case 'Lighting':
      return Icons.lightbulb_outline;
    case 'Audio':
      return Icons.volume_up_outlined;
    case 'Video':
      return Icons.videocam_outlined;
    default:
      return Icons.tune;
  }
}

class _AddReceiverGroupDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  const _AddReceiverGroupDialog({required this.vm});

  @override
  State<_AddReceiverGroupDialog> createState() => _AddReceiverGroupDialogState();
}

class _AddReceiverGroupDialogState extends State<_AddReceiverGroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _portCtrl;
  ProtocolPreset _selectedPreset = ProtocolPreset.custom;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Group ${widget.vm.receiverConfig.streams.length + 1}');
    _groupCtrl = TextEditingController(
      text: widget.vm.receiverConfig.streams.isEmpty
          ? '239.255.0.1'
          : MulticastStreamConfig.incrementIp(widget.vm.receiverConfig.streams.last.groupAddress, 1),
    );
    _portCtrl = TextEditingController(text: '5004');
  }

  void _onPresetChanged(ProtocolPreset? preset) {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      if (preset != ProtocolPreset.custom) {
        _nameCtrl.text = '${preset.name.split(' ').first} Group ${widget.vm.receiverConfig.streams.length + 1}';
        _groupCtrl.text = preset.defaultGroup;
        _portCtrl.text = preset.defaultPort.toString();
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final group = _groupCtrl.text.trim();
    if (!MulticastStreamConfig.isValidMulticastIpv4(group)) {
      setState(() {
        _errorText = 'Invalid multicast IPv4 address ($group). Must be 224.0.0.0 – 239.255.255.255';
      });
      return;
    }

    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _errorText = 'UDP port must be between 1 and 65535';
      });
      return;
    }

    final newStream = MulticastReceiverStreamConfig(
      id: 'rx_stream_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim().isEmpty ? 'Group' : _nameCtrl.text.trim(),
      groupAddress: group,
      port: port,
    );
    widget.vm.addReceiverStream(newStream);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_circle_outline, color: Color(0xFF2196F3), size: 20),
          SizedBox(width: 8),
          Text('Add Multicast Group to Join', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
              DropdownButtonFormField<ProtocolPreset>(
                initialValue: _selectedPreset,
                decoration: const InputDecoration(
                  labelText: 'Protocol Profile / Preset',
                  prefixIcon: Icon(Icons.tune, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                dropdownColor: const Color(0xFF252526),
                isExpanded: true,
                items: ProtocolPreset.all.map((p) {
                  return DropdownMenuItem<ProtocolPreset>(
                    value: p,
                    child: Row(
                      children: [
                        Icon(_getProtocolPresetIcon(p), size: 14, color: const Color(0xFF4FC1FF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: _onPresetChanged,
              ),
              if (_selectedPreset != ProtocolPreset.custom) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getProtocolPresetIcon(_selectedPreset),
                        size: 16,
                        color: const Color(0xFF4FC1FF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedPreset.description,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Stream / Group Name', hintText: 'Group 1'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _groupCtrl,
                decoration: const InputDecoration(labelText: 'Multicast Group IP', hintText: '239.255.0.1'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'UDP Port', hintText: '5004'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
          onPressed: _submit,
          child: const Text('Add Group', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _BatchReceiverGroupsDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  const _BatchReceiverGroupsDialog({required this.vm});

  @override
  State<_BatchReceiverGroupsDialog> createState() => _BatchReceiverGroupsDialogState();
}

class _BatchReceiverGroupsDialogState extends State<_BatchReceiverGroupsDialog> {
  late final TextEditingController _countCtrl;
  late final TextEditingController _startIpCtrl;
  late final TextEditingController _portCtrl;
  ProtocolPreset _selectedPreset = ProtocolPreset.custom;
  bool _incrementPort = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _countCtrl = TextEditingController(text: '10');
    _startIpCtrl = TextEditingController(text: '239.255.0.1');
    _portCtrl = TextEditingController(text: '5004');
  }

  void _onPresetChanged(ProtocolPreset? preset) {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      if (preset != ProtocolPreset.custom) {
        _startIpCtrl.text = preset.defaultGroup;
        _portCtrl.text = preset.defaultPort.toString();
      }
    });
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _startIpCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final count = int.tryParse(_countCtrl.text.trim());
    if (count == null || count < 1 || count > 100) {
      setState(() {
        _errorText = 'Count must be between 1 and 100';
      });
      return;
    }

    final startIp = _startIpCtrl.text.trim();
    if (!MulticastStreamConfig.isValidMulticastIpv4(startIp)) {
      setState(() {
        _errorText = 'Invalid starting multicast IPv4 address ($startIp)';
      });
      return;
    }

    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _errorText = 'Base UDP port must be between 1 and 65535';
      });
      return;
    }

    if (_incrementPort && (port + count - 1 > 65535)) {
      setState(() {
        _errorText = 'Port range would exceed maximum port 65535';
      });
      return;
    }

    widget.vm.batchGenerateReceiverStreams(
      count: count,
      startingIp: startIp,
      basePort: port,
      incrementPort: _incrementPort,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_motion, color: Color(0xFF2196F3), size: 20),
          SizedBox(width: 8),
          Text('Batch Subscribe Multicast Groups', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quickly subscribe to multiple multicast groups to test switch IGMP snooping tables, querier capacity, and selective group pruning.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
              DropdownButtonFormField<ProtocolPreset>(
                initialValue: _selectedPreset,
                decoration: const InputDecoration(
                  labelText: 'Protocol Profile / Preset',
                  prefixIcon: Icon(Icons.tune, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                dropdownColor: const Color(0xFF252526),
                isExpanded: true,
                items: ProtocolPreset.all.map((p) {
                  return DropdownMenuItem<ProtocolPreset>(
                    value: p,
                    child: Row(
                      children: [
                        Icon(_getProtocolPresetIcon(p), size: 14, color: const Color(0xFF4FC1FF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: _onPresetChanged,
              ),
              if (_selectedPreset != ProtocolPreset.custom) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getProtocolPresetIcon(_selectedPreset),
                        size: 16,
                        color: const Color(0xFF4FC1FF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedPreset.description,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Group Count', hintText: '10'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _startIpCtrl,
                      decoration: const InputDecoration(labelText: 'Starting Group IP', hintText: '239.255.0.1'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Base UDP Port', hintText: '5004'),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Increment UDP port for each group (port + 1)', style: TextStyle(fontSize: 12)),
                value: _incrementPort,
                onChanged: (val) {
                  setState(() {
                    _incrementPort = val ?? false;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
          onPressed: _submit,
          child: const Text('Generate & Add', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
