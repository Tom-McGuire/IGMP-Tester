import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/dscp_preset.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../../../domain/models/multicast_stats.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';
import 'flooded_streams_sheet.dart';

class ReceiverPanel extends StatelessWidget {
  const ReceiverPanel({super.key});

  void _showAddGroupDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _AddReceiverGroupDialog(vm: vm),
    );
  }

  void _showEditGroupDialog(
    BuildContext context,
    IgmpTesterViewModel vm,
    MulticastReceiverStreamConfig stream,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _AddReceiverGroupDialog(vm: vm, existingStream: stream),
    );
  }

  void _openFloodingScanner(BuildContext context, IgmpTesterViewModel vm) {
    final ifaceIp = vm.selectedInterface?.ip;
    final ifaceAddress =
        (ifaceIp != null && ifaceIp.isNotEmpty) ? InternetAddress.tryParse(ifaceIp) : null;

    FloodedStreamsSheet.showDialogModal(
      context,
      scannerService: vm.floodingScannerService,
      alreadyJoinedGroups: vm.activeJoinedGroupKeys,
      interfaceAddress: ifaceAddress,
      autoStart: true,
      onAdoptStream: (entry) async {
        await Navigator.of(context).maybePop();
        await vm.adoptFloodedStream(entry);
      },
    );
  }

  void _showBatchGroupDialog(BuildContext context, IgmpTesterViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => _BatchReceiverGroupsDialog(vm: vm),
    );
  }

  void _showPassivePortDialog(BuildContext context, IgmpTesterViewModel vm) {
    final ctrl = TextEditingController(text: vm.receiverConfig.passiveListenPort.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hearing_outlined, color: Color(0xFFFF9800), size: 20),
            SizedBox(width: 8),
            Text('Configure No-Subscription Server Port', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bind a UDP socket on this port WITHOUT sending an IGMP Join to test if the network switch floods unsubscribed multicast streams.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Passive Listener UDP Port',
                  hintText: '5004',
                ),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1 && p <= 65535) {
                vm.updateReceiverPassivePort(p);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save Port', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final isRunning = vm.isReceiverRunning;
    final isMeasuringLeave = vm.isMeasuringLeave;
    final stats = vm.receiverStats;
    final lastLeave = vm.lastLeaveLatency;
    final streams = vm.receiverConfig.streams;
    final passiveOnly = vm.receiverConfig.passiveListenOnly;
    final passivePort = vm.receiverConfig.passiveListenPort;
    final isPassivePortActive = vm.activePassivePorts.contains(passivePort);
    final unsubscribed = vm.unsubscribedStreams;

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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  // No-Join Mode switch
                  Tooltip(
                    message:
                        'When enabled, binds UDP ports without sending IGMP Membership Reports to verify if switches flood multicast traffic',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: passiveOnly ? const Color(0xFFFF9800) : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'No-Join Mode:',
                          style: TextStyle(
                            fontSize: 12,
                            color: passiveOnly ? const Color(0xFFFFB74D) : Colors.grey,
                            fontWeight: passiveOnly ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: passiveOnly,
                          activeThumbColor: const Color(0xFFFF9800),
                          onChanged: isRunning ? null : (val) => vm.updateReceiverPassiveMode(val),
                        ),
                      ],
                    ),
                  ),

                  // Loopback switch
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Loopback:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 4),
                      Switch(
                        value: vm.receiverConfig.enableLoopback,
                        onChanged: (isRunning || isMeasuringLeave)
                            ? null
                            : (val) => vm.updateReceiverLoopback(val),
                      ),
                    ],
                  ),

                  // Fast-Leave Latency Measurement toggle
                  Tooltip(
                    message:
                        'When enabled, leaving keeps UDP sockets open up to 3s to measure switch IGMP Fast-Leave prune latency',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: vm.measureFastLeave
                              ? const Color(0xFF10B981)
                              : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Fast-Leave Probe:',
                          style: TextStyle(
                            fontSize: 12,
                            color: vm.measureFastLeave
                                ? const Color(0xFF6EE7B7)
                                : Colors.grey,
                            fontWeight: vm.measureFastLeave
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: vm.measureFastLeave,
                          activeThumbColor: const Color(0xFF10B981),
                          onChanged: isMeasuringLeave
                              ? null
                              : (val) => vm.updateMeasureFastLeave(val),
                        ),
                      ],
                    ),
                  ),

                  // Add Group button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3).withValues(alpha: 0.22),
                      foregroundColor: const Color(0xFF64B5F6),
                      side: const BorderSide(color: Color(0xFF2196F3), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add Group',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: (isRunning || isMeasuringLeave)
                        ? null
                        : () => _showAddGroupDialog(context, vm),
                  ),

                  // Batch Join Groups button
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
                      'Batch Join',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: (isRunning || isMeasuringLeave)
                        ? null
                        : () => _showBatchGroupDialog(context, vm),
                  ),

                  // Scan Unjoined Traffic button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4DD0E1),
                      side: BorderSide(
                        color: vm.isFloodingScanRunning
                            ? const Color(0xFF00BCD4)
                            : const Color(0xFF26A69A),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.radar, size: 16),
                    label: Text(
                      vm.floodedStreamEntries.isNotEmpty
                          ? 'Scan Unjoined Traffic (${vm.floodedStreamEntries.length})'
                          : 'Scan Unjoined Traffic',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => _openFloodingScanner(context, vm),
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
                title: 'Unsubscribed / Flooded',
                value: '${unsubscribed.length} (${stats.unsubscribedPacketsReceived})',
                unit: 'grps (pkts)',
                icon: unsubscribed.isNotEmpty ? Icons.gpp_maybe : Icons.verified_user_outlined,
                color: unsubscribed.isNotEmpty ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
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
                      backgroundColor: isMeasuringLeave
                          ? const Color(0xFFD97706)
                          : (isRunning
                              ? const Color(0xFF8B0000)
                              : (passiveOnly ? const Color(0xFFE65100) : const Color(0xFF2196F3))),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: Icon(
                      isMeasuringLeave
                          ? Icons.hourglass_top_rounded
                          : (isRunning
                              ? Icons.stop
                              : (passiveOnly ? Icons.hearing : Icons.play_arrow)),
                      size: 18,
                    ),
                    label: Text(
                      isMeasuringLeave
                          ? 'Measuring Leave...'
                          : (isRunning
                              ? 'LEAVE ALL MULTICAST GROUPS & STOP RECEIVERS'
                              : (passiveOnly
                                  ? 'START PASSIVE RECEIVER (NO IGMP JOIN) ON ${streams.length} GROUP(S)'
                                  : 'JOIN ALL MULTICAST GROUPS (${streams.length}) & START RECEIVING')),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: (!isMeasuringLeave && streams.isEmpty && !passiveOnly)
                        ? null
                        : () => vm.toggleReceiver(),
                  ),
                ),
              ),
            ],
          ),
          if (lastLeave != null ||
              stats.dscpTransitStatus != DscpTransitStatus.unverified ||
              stats.expectedDscp != null ||
              stats.senderDscpPreset != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (lastLeave != null)
                  _FastLeaveLatencyPill(
                    result: lastLeave,
                    onClear: isMeasuringLeave ? null : () => vm.clearLeaveLatencyResults(),
                  ),
                if (stats.dscpTransitStatus != DscpTransitStatus.unverified ||
                    stats.expectedDscp != null ||
                    stats.senderDscpPreset != null)
                  _ReceiverQosPill(stats: stats),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // ==================== IGMP SNOOPING & UNSUBSCRIBED STREAM VERIFICATION ====================
          _IgmpSnoopingVerificationCard(
            vm: vm,
            unsubscribed: unsubscribed,
            isReceiverRunning: isRunning,
            passivePort: passivePort,
            isPassivePortActive: isPassivePortActive,
            onConfigurePort: () => _showPassivePortDialog(context, vm),
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
                      SizedBox(width: 132, child: Text('Actions', style: _headerStyle)),
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
                      final isStreamMeasuring = vm.isStreamMeasuringLeave(stream.id);
                      final rStats = vm.streamReceiverStats[stream.id];
                      final effectiveJoin = stream.joinGroup && !passiveOnly;

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
                                  color: isStreamMeasuring
                                      ? const Color(0xFFD97706)
                                      : (isStreamActive
                                          ? (effectiveJoin ? const Color(0xFF2196F3) : const Color(0xFFFF9800))
                                          : const Color(0xFF555555)),
                                ),
                              ),
                            ),

                            // Group Name (+ optional SSM source filter or QoS note)
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stream.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  if (stream.isSsm && stream.hasSourceFilter)
                                    Text(
                                      'src: ${stream.normalizedSourceIp}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF4DD0E1),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  if (rStats != null &&
                                      rStats.dscpTransitStatus != DscpTransitStatus.unverified)
                                    Text(
                                      rStats.dscpTransitStatus == DscpTransitStatus.preserved
                                          ? 'QoS Preserved (${DscpPreset.formatDscpBadge(rStats.receivedDscp!)})'
                                          : 'QoS Alert (${rStats.receivedDscp != null ? DscpPreset.formatDscpBadge(rStats.receivedDscp!) : "Stripped"})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: rStats.dscpTransitStatus == DscpTransitStatus.preserved
                                            ? const Color(0xFF6EE7B7)
                                            : const Color(0xFFFCA5A5),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Endpoint + Join Mode Badges
                            Expanded(
                              flex: 4,
                              child: Wrap(
                                spacing: 5,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(
                                    effectiveJoin ? Icons.hub : Icons.hearing,
                                    size: 13,
                                    color: effectiveJoin ? const Color(0xFF2196F3) : const Color(0xFFFF9800),
                                  ),
                                  Text(
                                    stream.endpoint,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF64B5F6),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: (isStreamActive || isStreamMeasuring)
                                        ? null
                                        : () => vm.toggleReceiverStreamJoinMode(stream.id),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Tooltip(
                                      message: effectiveJoin
                                          ? 'Sends IGMP Join (click when stopped to switch to No-Join passive test)'
                                          : 'Passive Listen Only — No IGMP Join sent (click when stopped to enable IGMP Join)',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: effectiveJoin
                                              ? const Color(0xFF2196F3).withValues(alpha: 0.15)
                                              : const Color(0xFFFF9800).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: effectiveJoin
                                                ? const Color(0xFF2196F3).withValues(alpha: 0.5)
                                                : const Color(0xFFFF9800).withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: Text(
                                          effectiveJoin ? 'IGMP Join' : 'No Join',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: effectiveJoin
                                                ? const Color(0xFF64B5F6)
                                                : const Color(0xFFFFB74D),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (stream.isSsm)
                                    Tooltip(
                                      message: stream.hasSourceFilter
                                          ? 'Source-Specific Multicast filter: ${stream.normalizedSourceIp}${rStats?.ssmDiagnosticNote != null ? "\n${rStats!.ssmDiagnosticNote}" : ""}'
                                          : 'Source-Specific Multicast (S, G)',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: const Color(0xFF00BCD4).withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: const Text(
                                          'SSM (S, G)',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4DD0E1),
                                          ),
                                        ),
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
                                      isStreamMeasuring
                                          ? Icons.hourglass_top_rounded
                                          : (isStreamActive ? Icons.stop_circle_outlined : Icons.play_circle_fill),
                                      size: 18,
                                      color: isStreamMeasuring
                                          ? const Color(0xFFD97706)
                                          : (isStreamActive ? const Color(0xFFF44336) : const Color(0xFF2196F3)),
                                    ),
                                    tooltip: isStreamMeasuring
                                        ? 'Abort Leave Measurement'
                                        : (isStreamActive ? 'Stop Stream' : (effectiveJoin ? 'Join Group' : 'Start Passive Listen')),
                                    onPressed: () => vm.toggleIndividualReceiverStream(stream.id),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      fixedSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                                    tooltip: 'Edit Group',
                                    onPressed: (isStreamActive || isStreamMeasuring)
                                        ? null
                                        : () => _showEditGroupDialog(context, vm, stream),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      fixedSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                                    tooltip: 'Remove Group',
                                    onPressed: (isStreamActive || isStreamMeasuring)
                                        ? null
                                        : () => vm.removeReceiverStream(stream.id),
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

class _IgmpSnoopingVerificationCard extends StatelessWidget {
  final IgmpTesterViewModel vm;
  final List<UnsubscribedStreamInfo> unsubscribed;
  final bool isReceiverRunning;
  final int passivePort;
  final bool isPassivePortActive;
  final VoidCallback onConfigurePort;

  const _IgmpSnoopingVerificationCard({
    required this.vm,
    required this.unsubscribed,
    required this.isReceiverRunning,
    required this.passivePort,
    required this.isPassivePortActive,
    required this.onConfigurePort,
  });

  @override
  Widget build(BuildContext context) {
    final hasLeak = unsubscribed.isNotEmpty;

    Color borderColor = const Color(0xFF2C2C2C);
    Color headerBg = const Color(0xFF252526);
    if (hasLeak) {
      borderColor = const Color(0xFFF44336).withValues(alpha: 0.7);
      headerBg = const Color(0xFFF44336).withValues(alpha: 0.15);
    } else if (isReceiverRunning || isPassivePortActive) {
      borderColor = const Color(0xFF4CAF50).withValues(alpha: 0.5);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: hasLeak ? 1.4 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasLeak
                          ? Icons.warning_amber_rounded
                          : (isReceiverRunning ? Icons.verified_user : Icons.radar),
                      size: 17,
                      color: hasLeak
                          ? const Color(0xFFFF5252)
                          : (isReceiverRunning ? const Color(0xFF4CAF50) : const Color(0xFFFF9800)),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'IGMP Snooping & Unsubscribed Stream Verification',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasLeak
                            ? const Color(0xFFF44336).withValues(alpha: 0.25)
                            : (isReceiverRunning
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                                : const Color(0xFF3E3E42).withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        hasLeak
                            ? 'FLOODING DETECTED (${unsubscribed.length} Unsubscribed)'
                            : (isReceiverRunning ? 'IGMP Filtering Clean (0 Flooded)' : 'Standby'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: hasLeak
                              ? const Color(0xFFFF8A80)
                              : (isReceiverRunning ? const Color(0xFF81C784) : Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Port configuration chip
                    InkWell(
                      onTap: isPassivePortActive ? null : onConfigurePort,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF3E3E42)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.settings_ethernet, size: 13, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'Port: $passivePort',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Start / Stop No-Subscription Server button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPassivePortActive
                            ? const Color(0xFF8B0000)
                            : const Color(0xFFFF9800).withValues(alpha: 0.22),
                        foregroundColor: isPassivePortActive ? Colors.white : const Color(0xFFFFB74D),
                        side: BorderSide(
                          color: isPassivePortActive ? const Color(0xFFF44336) : const Color(0xFFFF9800),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                      ),
                      icon: Icon(isPassivePortActive ? Icons.stop : Icons.hearing, size: 14),
                      label: Text(
                        isPassivePortActive
                            ? 'Stop No-Subscription Server (:$passivePort)'
                            : 'Start No-Subscription Server (:$passivePort)',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => vm.togglePassiveServer(port: passivePort),
                    ),

                    if (hasLeak) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 30),
                        ),
                        icon: const Icon(Icons.clear_all, size: 14),
                        label: const Text('Clear Flood Log', style: TextStyle(fontSize: 11)),
                        onPressed: () => vm.clearUnsubscribedStreams(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Body
          if (!hasLeak)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                isPassivePortActive
                    ? 'Passive No-Subscription Server is listening on UDP port $passivePort without an IGMP Join. Any test streams arriving here indicate IGMP Snooping is disabled or flooding on the network.'
                    : 'Monitors open UDP receiver ports for multicast test streams that this host has NOT subscribed to (or streams started in No-Join mode). Start the No-Subscription Server to listen with zero IGMP joins.',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: const Color(0xFFF44336).withValues(alpha: 0.08),
                  child: const Text(
                    '⚠️ Unsubscribed multicast traffic is reaching this interface! This indicates IGMP Snooping may be disabled on the switch, or an upstream port is flooding unknown multicast.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFFF8A80)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: const Color(0xFF252526),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: Text('Flooded Group & Port', style: _headerStyle)),
                      Expanded(flex: 3, child: Text('Sender Source IP', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Session ID', style: _headerStyle)),
                      Expanded(flex: 2, child: Text('Flooded Packets', style: _headerStyle)),
                      Expanded(flex: 3, child: Text('Flood Bitrate / Rate', style: _headerStyle)),
                      SizedBox(width: 110, child: Text('Action', style: _headerStyle)),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: unsubscribed.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF282828)),
                  itemBuilder: (context, idx) {
                    final item = unsubscribed[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                const Icon(Icons.gpp_maybe, size: 14, color: Color(0xFFFF5252)),
                                const SizedBox(width: 6),
                                Text(
                                  item.endpoint,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF8A80),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.sourceIp,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Colors.white70),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.sessionId,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${item.packetsReceived} pkts',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${item.currentBitrateMbps.toStringAsFixed(2)} Mbps (${item.currentPps.toStringAsFixed(0)} pps)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Color(0xFFFFB74D),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 26),
                              ),
                              icon: const Icon(Icons.add_link, size: 13),
                              label: const Text('Add Group', style: TextStyle(fontSize: 10.5)),
                              onPressed: () => vm.subscribeToDetectedStream(item),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
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

class _FastLeaveLatencyPill extends StatelessWidget {
  final LeaveLatencyResult result;
  final VoidCallback? onClear;

  const _FastLeaveLatencyPill({required this.result, this.onClear});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String text;

    switch (result.status) {
      case FastLeaveStatus.measuring:
        color = const Color(0xFFD97706);
        icon = Icons.hourglass_top_rounded;
        text = 'Measuring Leave... (${result.trailingPacketsReceived} trailing)';
      case FastLeaveStatus.fastLeaveActive:
        color = const Color(0xFF10B981);
        icon = Icons.bolt;
        text = '${result.leaveLatencyMs} ms — Fast-Leave · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.delayedPrune:
        color = const Color(0xFFF59E0B);
        icon = Icons.schedule;
        text = '${result.leaveLatencyMs} ms — Delayed Prune · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.noFastLeave:
        color = const Color(0xFFEF4444);
        icon = Icons.warning_amber_rounded;
        text = '${result.leaveLatencyMs} ms — No Fast-Leave · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.aborted:
        color = Colors.grey;
        icon = Icons.cancel_outlined;
        text = 'Leave Measurement Aborted (${result.trailingPacketsReceived} trailing)';
      case FastLeaveStatus.notMeasured:
        color = Colors.grey;
        icon = Icons.timer_off_outlined;
        text = 'Fast-Leave Not Measured';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onClear,
              child: Icon(Icons.close, size: 13, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiverQosPill extends StatelessWidget {
  final ReceiverStats stats;

  const _ReceiverQosPill({required this.stats});

  @override
  Widget build(BuildContext context) {
    final expected = stats.expectedDscp ?? stats.senderDscpPreset;
    final expectedLabel = expected?.shortLabel ?? 'QoS';
    final rxLabel = stats.receivedDscp != null
        ? DscpPreset.formatDscpBadge(stats.receivedDscp!)
        : 'Unverified';

    final Color color;
    final IconData icon;
    final String label;

    switch (stats.dscpTransitStatus) {
      case DscpTransitStatus.preserved:
        color = const Color(0xFF10B981);
        icon = Icons.verified_outlined;
        label = 'QoS Preserved · $rxLabel';
      case DscpTransitStatus.remarkedToZero:
        color = const Color(0xFFEF4444);
        icon = Icons.gpp_bad_outlined;
        label = 'QoS Stripped · Sent $expectedLabel -> Received $rxLabel';
      case DscpTransitStatus.remarkedOrStripped:
        color = const Color(0xFFF59E0B);
        icon = Icons.warning_amber_rounded;
        label = 'QoS Remarked · Sent $expectedLabel -> Received $rxLabel';
      case DscpTransitStatus.unverified:
        color = const Color(0xFF60A5FA);
        icon = Icons.label_important_outline;
        label = 'QoS Expect $expectedLabel (OS TOS Unverified)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddReceiverGroupDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;
  final MulticastReceiverStreamConfig? existingStream;
  const _AddReceiverGroupDialog({required this.vm, this.existingStream});

  @override
  State<_AddReceiverGroupDialog> createState() => _AddReceiverGroupDialogState();
}

class _AddReceiverGroupDialogState extends State<_AddReceiverGroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _sourceIpCtrl;
  ProtocolPreset _selectedPreset = ProtocolPreset.custom;
  bool _joinGroup = true;
  IgmpJoinMode _joinMode = IgmpJoinMode.asm;
  DscpPreset? _expectedDscp;
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
      _sourceIpCtrl = TextEditingController(text: existing.normalizedSourceIp);
      _joinGroup = existing.joinGroup;
      _joinMode = existing.joinMode;
      _expectedDscp = existing.expectedDscp;
    } else {
      _nameCtrl = TextEditingController(text: 'Group ${widget.vm.receiverConfig.streams.length + 1}');
      _groupCtrl = TextEditingController(
        text: widget.vm.receiverConfig.streams.isEmpty
            ? '239.255.0.1'
            : MulticastStreamConfig.incrementIp(widget.vm.receiverConfig.streams.last.groupAddress, 1),
      );
      _portCtrl = TextEditingController(text: '5004');
      _sourceIpCtrl = TextEditingController();
    }
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
    _sourceIpCtrl.dispose();
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

    String? sourceIp;
    if (_joinMode == IgmpJoinMode.ssm) {
      final candidate = _sourceIpCtrl.text.trim();
      if (!MulticastReceiverStreamConfig.isValidUnicastSourceIp(candidate)) {
        setState(() {
          _errorText = 'SSM (S, G) requires a valid unicast IPv4 Source IP (e.g. 10.0.0.10)';
        });
        return;
      }
      sourceIp = candidate;
    }

    if (_isEditing) {
      final updated = widget.existingStream!.copyWith(
        name: _nameCtrl.text.trim().isEmpty ? 'Group' : _nameCtrl.text.trim(),
        groupAddress: group,
        port: port,
        joinGroup: _joinGroup,
        joinMode: _joinMode,
        sourceFilterIp: sourceIp,
        clearSourceFilterIp: _joinMode != IgmpJoinMode.ssm,
        expectedDscp: _expectedDscp,
        clearExpectedDscp: _expectedDscp == null,
      );
      widget.vm.updateReceiverStream(updated);
    } else {
      final newStream = MulticastReceiverStreamConfig(
        id: 'rx_stream_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameCtrl.text.trim().isEmpty ? 'Group' : _nameCtrl.text.trim(),
        groupAddress: group,
        port: port,
        joinGroup: _joinGroup,
        joinMode: _joinMode,
        sourceFilterIp: sourceIp,
        expectedDscp: _expectedDscp,
      );
      widget.vm.addReceiverStream(newStream);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final showSsmRangeHint =
        _joinMode == IgmpJoinMode.ssm &&
        _groupCtrl.text.trim().isNotEmpty &&
        MulticastStreamConfig.isValidMulticastIpv4(_groupCtrl.text.trim()) &&
        !MulticastReceiverStreamConfig.isSsmGroupIpv4(_groupCtrl.text.trim());

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            color: const Color(0xFF2196F3),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _isEditing ? 'Edit Multicast Group' : 'Add Multicast Group to Join',
            style: const TextStyle(fontSize: 15),
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
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Multicast Group IP',
                  hintText: _joinMode == IgmpJoinMode.ssm ? '232.0.1.1' : '239.255.0.1',
                ),
              ),
              if (showSsmRangeHint)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Tip: IANA designates 232.0.0.0/8 for standard IGMPv3 SSM groups.',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF4DD0E1)),
                  ),
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
                    child: DropdownButtonFormField<IgmpJoinMode>(
                      initialValue: _joinMode,
                      decoration: const InputDecoration(
                        labelText: 'Join Mode',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      dropdownColor: const Color(0xFF252526),
                      isExpanded: true,
                      items: IgmpJoinMode.values.map((mode) {
                        return DropdownMenuItem<IgmpJoinMode>(
                          value: mode,
                          child: Text(mode.label, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _joinMode = val);
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (_joinMode == IgmpJoinMode.ssm) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _sourceIpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Source IP (SSM Filter)',
                    hintText: '10.0.0.10 (232.0.0.0/8 SSM range recommended)',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<DscpPreset?>(
                initialValue: _expectedDscp,
                decoration: const InputDecoration(
                  labelText: 'Expected QoS / DSCP',
                  prefixIcon: Icon(Icons.label_important_outline, size: 16),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                dropdownColor: const Color(0xFF252526),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<DscpPreset?>(
                    value: null,
                    child: Text('Auto (Match Sender Tag)', style: TextStyle(fontSize: 12)),
                  ),
                  ...DscpPreset.values.map((preset) {
                    return DropdownMenuItem<DscpPreset?>(
                      value: preset,
                      child: Text(
                        preset.dropdownLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _expectedDscp = val);
                },
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Send IGMP Join (uncheck to listen passively for flooding)',
                  style: TextStyle(fontSize: 12),
                ),
                value: _joinGroup,
                onChanged: (val) {
                  setState(() {
                    _joinGroup = val ?? true;
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
          child: Text(
            _isEditing ? 'Save Changes' : 'Add Group',
            style: const TextStyle(color: Colors.white),
          ),
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
