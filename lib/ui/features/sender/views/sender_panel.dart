import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/dscp_preset.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/metric_card.dart';
import '../../../widgets/protocol_preset_icon.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class SenderPanel extends StatelessWidget {
  const SenderPanel({super.key});

  void _showAddStreamDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _AddSenderStreamDialog(vm: vm),
    );
  }

  void _showEditStreamDialog(
    BuildContext context,
    IgmpTesterViewModel vm,
    MulticastStreamConfig stream,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _AddSenderStreamDialog(vm: vm, existingStream: stream),
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
    final bool isDark = AppTheme.isDark;
    final accentText = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
    final warnText = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);
    final successText = isDark ? const Color(0xFF81C784) : AppTheme.success;
    final bandwidthColor = isDark ? const Color(0xFFBA68C8) : const Color(0xFF7E22CE);

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, color: AppTheme.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Multicast Transmission & Saturation Control',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
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
                      Text('Loopback:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                      backgroundColor: AppTheme.accent.withValues(alpha: isDark ? 0.22 : 0.10),
                      foregroundColor: accentText,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      side: BorderSide(color: AppTheme.accent, width: 1.2),
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
                      backgroundColor: AppTheme.warning.withValues(alpha: isDark ? 0.2 : 0.10),
                      foregroundColor: warnText,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      side: BorderSide(color: AppTheme.warning, width: 1.2),
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
              MetricCard(
                title: 'Active Streams',
                value: '${stats.activeStreamsCount} / ${streams.length}',
                unit: 'streams',
                icon: Icons.layers_outlined,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Combined Rate',
                value: stats.currentPps.toStringAsFixed(0),
                unit: 'pps',
                icon: Icons.speed,
                color: AppTheme.info,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Aggregate Bandwidth',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: bandwidthColor,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Total Outbound',
                value: (stats.bytesSent / (1024 * 1024)).toStringAsFixed(2),
                unit: 'MB (${stats.packetsSent} pkts)',
                icon: Icons.data_usage,
                color: AppTheme.success,
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
                      backgroundColor: isRunning
                          ? (isDark ? const Color(0xFF8B0000) : AppTheme.error)
                          : AppTheme.accent,
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              if (streams.isNotEmpty)
                Text(
                  'Individual controls allow starting or pausing specific groups',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Table Content
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                // Table Columns
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text('Status', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 3, child: Text('Stream Name', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 4, child: Text('Multicast Group & Port', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Rate', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Payload', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('QoS / DSCP', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Bitrate', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Sent Pkts', style: AppTheme.tableHeaderStyle)),
                      SizedBox(width: 132, child: Text('Actions', style: AppTheme.tableHeaderStyle)),
                    ],
                  ),
                ),

                if (streams.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No multicast streams defined. Click "Add Stream" or "Batch Generator" above to configure test streams.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: streams.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.border),
                    itemBuilder: (context, index) {
                      final stream = streams[index];
                      final isStreamActive = vm.isSenderStreamActive(stream.id);
                      final sStats = vm.streamSenderStats[stream.id];

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: index % 2 == 0 ? AppTheme.surface : AppTheme.surfaceAlt,
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
                                  color: isStreamActive ? AppTheme.success : AppTheme.textMuted,
                                ),
                              ),
                            ),

                            // Stream Name
                            Expanded(
                              flex: 3,
                              child: Text(
                                stream.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),

                            // Endpoint
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  Icon(Icons.hub_outlined, size: 13, color: AppTheme.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    stream.endpoint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: accentText,
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
                                style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                              ),
                            ),

                            // Payload size
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${stream.packetSizeBytes} B',
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),

                            // QoS / DSCP Tag
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _DscpTagPill(
                                  preset: stream.dscpPreset,
                                  socketApplied: isStreamActive ? sStats?.dscpSocketApplied : null,
                                  warning: sStats?.dscpWarning,
                                ),
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
                                  color: isStreamActive ? successText : AppTheme.textSecondary,
                                ),
                              ),
                            ),

                            // Packets sent
                            Expanded(
                              flex: 2,
                              child: Text(
                                sStats != null ? sStats.packetsSent.toString() : '0',
                                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ),

                            // Actions
                            SizedBox(
                              width: 132,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      fixedSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(
                                      isStreamActive ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                      size: 18,
                                      color: isStreamActive ? AppTheme.warning : AppTheme.success,
                                    ),
                                    tooltip: isStreamActive ? 'Pause Stream' : 'Start Stream',
                                    onPressed: () => vm.toggleIndividualSenderStream(stream.id),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      fixedSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary),
                                    tooltip: 'Edit Stream',
                                    onPressed: isStreamActive
                                        ? null
                                        : () => _showEditStreamDialog(context, vm, stream),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      fixedSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.textSecondary),
                                    tooltip: 'Remove Stream',
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

class _DscpTagPill extends StatelessWidget {
  final DscpPreset preset;
  final bool? socketApplied;
  final String? warning;

  const _DscpTagPill({
    required this.preset,
    this.socketApplied,
    this.warning,
  });

  Color _pillColor() {
    final bool isDark = AppTheme.isDark;
    switch (preset) {
      case DscpPreset.bestEffort:
        return AppTheme.textSecondary;
      case DscpPreset.cs3:
        return isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
      case DscpPreset.af41:
        return isDark ? const Color(0xFF81C784) : AppTheme.success;
      case DscpPreset.ef:
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);
      case DscpPreset.cs7:
        return isDark ? const Color(0xFFE57373) : AppTheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _pillColor();
    final hasSocketWarning = socketApplied == false && warning != null;
    final tooltip = hasSocketWarning
        ? '${preset.dropdownLabel}\nWarning: $warning'
        : preset.dropdownLabel;

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppTheme.isDark ? 0.14 : 0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasSocketWarning
                ? AppTheme.warning
                : color.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                preset.shortLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (hasSocketWarning) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.warning_amber_rounded,
                size: 11,
                color: AppTheme.isDark ? const Color(0xFFFFB74D) : AppTheme.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddSenderStreamDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  final MulticastStreamConfig? existingStream;
  const _AddSenderStreamDialog({required this.vm, this.existingStream});

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
  DscpPreset _selectedDscp = DscpPreset.bestEffort;
  String? _errorText;

  bool get _isEditing => widget.existingStream != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingStream;
    if (existing != null) {
      _nameCtrl = TextEditingController(text: existing.name);
      _groupCtrl = TextEditingController(text: existing.groupAddress);
      _portCtrl = TextEditingController(text: existing.port.toString());
      _rateCtrl = TextEditingController(text: existing.packetsPerSecond.toString());
      _sizeCtrl = TextEditingController(text: existing.packetSizeBytes.toString());
      _ttlCtrl = TextEditingController(text: existing.ttl.toString());
      _selectedDscp = existing.dscpPreset;
    } else {
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

    if (_isEditing) {
      final updated = widget.existingStream!.copyWith(
        name: _nameCtrl.text.trim().isEmpty ? 'Stream' : _nameCtrl.text.trim(),
        groupAddress: group,
        port: port,
        packetsPerSecond: rate,
        packetSizeBytes: size,
        ttl: ttl,
        dscpPreset: _selectedDscp,
      );
      widget.vm.updateSenderStream(updated);
    } else {
      final newStream = MulticastStreamConfig(
        id: 'stream_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameCtrl.text.trim().isEmpty ? 'Stream' : _nameCtrl.text.trim(),
        groupAddress: group,
        port: port,
        packetsPerSecond: rate,
        packetSizeBytes: size,
        ttl: ttl,
        dscpPreset: _selectedDscp,
      );
      widget.vm.addSenderStream(newStream);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    final accentText = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      title: Row(
        children: [
          Icon(
            _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            color: AppTheme.accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _isEditing ? 'Edit Multicast Stream' : 'Add Multicast Stream',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
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
                    color: AppTheme.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: AppTheme.error, fontSize: 12),
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
                dropdownColor: AppTheme.surfaceElevated,
                isExpanded: true,
                items: ProtocolPreset.all.map((p) {
                  return DropdownMenuItem<ProtocolPreset>(
                    value: p,
                    child: Row(
                      children: [
                        Icon(iconForProtocolPreset(p), size: 14, color: accentText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
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
                    color: AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        iconForProtocolPreset(_selectedPreset),
                        size: 16,
                        color: accentText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPreset.description,
                              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Bitrate: ~${_selectedPreset.approximateBitrateMbps.toStringAsFixed(2)} Mbps',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: accentText,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<DscpPreset>(
                initialValue: _selectedDscp,
                decoration: const InputDecoration(
                  labelText: 'QoS / DSCP Tag',
                  prefixIcon: Icon(Icons.label_important_outline, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                dropdownColor: AppTheme.surfaceElevated,
                isExpanded: true,
                items: DscpPreset.values.map((preset) {
                  return DropdownMenuItem<DscpPreset>(
                    value: preset,
                    child: Text(
                      preset.dropdownLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDscp = val);
                  }
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text(
            _isEditing ? 'Save Changes' : 'Add Stream',
            style: const TextStyle(color: Colors.white),
          ),
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
  DscpPreset _selectedDscp = DscpPreset.bestEffort;
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
      dscpPreset: _selectedDscp,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    final accentText = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    final pps = int.tryParse(_rateCtrl.text.trim()) ?? 0;
    final size = int.tryParse(_sizeCtrl.text.trim()) ?? 0;
    final totalPps = count * pps;
    final totalBandwidthMbps = (totalPps * size * 8) / 1000000.0;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.auto_awesome_motion, color: AppTheme.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Batch Generate Saturation Streams',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Instantly generate multiple multicast streams across a block of addresses to test switch IGMP snooping table capacity and network saturation.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: AppTheme.error, fontSize: 12),
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
                dropdownColor: AppTheme.surfaceElevated,
                isExpanded: true,
                items: ProtocolPreset.all.map((p) {
                  return DropdownMenuItem<ProtocolPreset>(
                    value: p,
                    child: Row(
                      children: [
                        Icon(iconForProtocolPreset(p), size: 14, color: accentText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
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
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          iconForProtocolPreset(_selectedPreset),
                          size: 16,
                          color: accentText,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedPreset.description,
                            style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Aggregate Saturation: $totalPps pps',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: accentText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '(~${totalBandwidthMbps.toStringAsFixed(2)} Mbps total)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.greenAccent.shade400 : AppTheme.success,
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
                title: Text(
                  'Increment UDP port for each stream (port + 1)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
                value: _incrementPort,
                onChanged: (val) {
                  setState(() {
                    _incrementPort = val ?? false;
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<DscpPreset>(
                initialValue: _selectedDscp,
                decoration: const InputDecoration(
                  labelText: 'QoS / DSCP Tag (all streams)',
                  prefixIcon: Icon(Icons.label_important_outline, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                dropdownColor: AppTheme.surfaceElevated,
                isExpanded: true,
                items: DscpPreset.values.map((preset) {
                  return DropdownMenuItem<DscpPreset>(
                    value: preset,
                    child: Text(
                      preset.dropdownLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDscp = val);
                  }
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Generate Streams', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
