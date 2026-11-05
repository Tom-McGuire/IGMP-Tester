import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class SenderPanel extends StatelessWidget {
  const SenderPanel({super.key});

  void _showAddStreamDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _AddSenderStreamDialog(vm: vm),
    );
  }

  void _showBatchDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _BatchSenderStreamsDialog(vm: vm),
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
                  const SizedBox(width: 16),

                  // Add Stream button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007ACC).withValues(alpha: 0.22),
                      foregroundColor: const Color(0xFF4FC1FF),
                      side: const BorderSide(color: Color(0xFF007ACC), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add Stream',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: isRunning ? null : () => _showAddStreamDialog(context, vm),
                  ),
                  const SizedBox(width: 10),

                  // Batch Generator button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFFFFB74D),
                      side: const BorderSide(color: Color(0xFFFF9800), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.auto_awesome_motion, size: 16),
                    label: const Text(
                      'Batch Generator',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
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

class _AddSenderStreamDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  const _AddSenderStreamDialog({required this.vm});

  @override
  State<_AddSenderStreamDialog> createState() => _AddSenderStreamDialogState();
}

class _AddSenderStreamDialogState extends State<_AddSenderStreamDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _ttlCtrl;
  ProtocolPreset _selectedPreset = ProtocolPreset.custom;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Stream ${widget.vm.senderConfig.streams.length + 1}');
    _groupCtrl = TextEditingController(
      text: widget.vm.senderConfig.streams.isEmpty
          ? '239.255.0.1'
          : MulticastStreamConfig.incrementIp(widget.vm.senderConfig.streams.last.groupAddress, 1),
    );
    _portCtrl = TextEditingController(text: '5004');
    _rateCtrl = TextEditingController(text: '50');
    _sizeCtrl = TextEditingController(text: '256');
    _ttlCtrl = TextEditingController(text: '64');
  }

  void _onPresetChanged(ProtocolPreset? preset) {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      if (preset != ProtocolPreset.custom) {
        _nameCtrl.text = '${preset.name.split(' ').first} Stream ${widget.vm.senderConfig.streams.length + 1}';
        _groupCtrl.text = preset.defaultGroup;
        _portCtrl.text = preset.defaultPort.toString();
        _rateCtrl.text = preset.packetsPerSecond.toString();
        _sizeCtrl.text = preset.packetSizeBytes.toString();
        _ttlCtrl.text = preset.defaultTtl.toString();
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    _portCtrl.dispose();
    _rateCtrl.dispose();
    _sizeCtrl.dispose();
    _ttlCtrl.dispose();
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
        _errorText = 'Port must be between 1 and 65535';
      });
      return;
    }

    final ttl = int.tryParse(_ttlCtrl.text.trim());
    if (ttl == null || ttl < 1 || ttl > 255) {
      setState(() {
        _errorText = 'TTL must be between 1 and 255';
      });
      return;
    }

    final rate = int.tryParse(_rateCtrl.text.trim());
    if (rate == null || rate < 1 || rate > 5000) {
      setState(() {
        _errorText = 'Rate (PPS) must be between 1 and 5000';
      });
      return;
    }

    final size = int.tryParse(_sizeCtrl.text.trim());
    if (size == null || size < 56 || size > 1472) {
      setState(() {
        _errorText = 'Size must be between 56 and 1472 bytes (MTU safe)';
      });
      return;
    }

    final newStream = MulticastStreamConfig(
      id: 'stream_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim().isEmpty ? 'Stream' : _nameCtrl.text.trim(),
      groupAddress: group,
      port: port,
      packetsPerSecond: rate,
      packetSizeBytes: size,
      ttl: ttl,
    );
    widget.vm.addSenderStream(newStream);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_circle_outline, color: Color(0xFF007ACC), size: 20),
          SizedBox(width: 8),
          Text('Add Multicast Stream', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 440,
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
                    border: Border.all(color: const Color(0xFF007ACC).withValues(alpha: 0.4)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPreset.description,
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Bitrate: ~${_selectedPreset.approximateBitrateMbps.toStringAsFixed(2)} Mbps',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4FC1FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Stream Name', hintText: 'Stream 1'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _groupCtrl,
                decoration: const InputDecoration(labelText: 'Multicast Group IP', hintText: '239.255.0.1'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'UDP Port', hintText: '5004'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ttlCtrl,
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
                      controller: _rateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rate (PPS)', hintText: '50'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _sizeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Size (Bytes)', hintText: '256'),
                    ),
                  ),
                ],
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
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
          onPressed: _submit,
          child: const Text('Add Stream', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _BatchSenderStreamsDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  const _BatchSenderStreamsDialog({required this.vm});

  @override
  State<_BatchSenderStreamsDialog> createState() => _BatchSenderStreamsDialogState();
}

class _BatchSenderStreamsDialogState extends State<_BatchSenderStreamsDialog> {
  late final TextEditingController _countCtrl;
  late final TextEditingController _startIpCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _sizeCtrl;
  ProtocolPreset _selectedPreset = ProtocolPreset.custom;
  bool _incrementPort = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _countCtrl = TextEditingController(text: '10');
    _startIpCtrl = TextEditingController(text: '239.255.0.1');
    _portCtrl = TextEditingController(text: '5004');
    _rateCtrl = TextEditingController(text: '50');
    _sizeCtrl = TextEditingController(text: '256');
  }

  void _onPresetChanged(ProtocolPreset? preset) {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      if (preset != ProtocolPreset.custom) {
        _startIpCtrl.text = preset.defaultGroup;
        _portCtrl.text = preset.defaultPort.toString();
        _rateCtrl.text = preset.packetsPerSecond.toString();
        _sizeCtrl.text = preset.packetSizeBytes.toString();
      }
    });
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _startIpCtrl.dispose();
    _portCtrl.dispose();
    _rateCtrl.dispose();
    _sizeCtrl.dispose();
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

    final pps = int.tryParse(_rateCtrl.text.trim());
    if (pps == null || pps < 1 || pps > 5000) {
      setState(() {
        _errorText = 'Rate (PPS) must be between 1 and 5000';
      });
      return;
    }

    final size = int.tryParse(_sizeCtrl.text.trim());
    if (size == null || size < 56 || size > 1472) {
      setState(() {
        _errorText = 'Size must be between 56 and 1472 bytes';
      });
      return;
    }

    widget.vm.batchGenerateSenderStreams(
      count: count,
      startingIp: startIp,
      basePort: port,
      pps: pps,
      packetSize: size,
      incrementPort: _incrementPort,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    final pps = int.tryParse(_rateCtrl.text.trim()) ?? 0;
    final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
    final totalPps = count * pps;
    final totalBandwidthMbps = (totalPps * size * 8) / 1000000.0;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome_motion, color: Color(0xFF007ACC), size: 20),
          SizedBox(width: 8),
          Text('Batch Generate Saturation Streams', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Instantly generate multiple multicast streams across a block of addresses to test switch IGMP snooping table capacity and network saturation.',
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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF252526),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF007ACC).withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Aggregate Saturation: $totalPps pps',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4FC1FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '(~${totalBandwidthMbps.toStringAsFixed(2)} Mbps total)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Stream Count (e.g. 10)', hintText: '10'),
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Base UDP Port', hintText: '5004'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _rateCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Rate per Stream (PPS)', hintText: '50'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _sizeCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
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
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
          onPressed: _submit,
          child: const Text('Generate Streams', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
