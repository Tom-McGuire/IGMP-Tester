import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/dscp_preset.dart';
import '../../../../domain/models/multicast_config.dart';
import '../../../../domain/models/multicast_stats.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/metric_card.dart';
import '../../../widgets/protocol_preset_icon.dart';
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
      interfaceName: vm.selectedInterface?.name,
      tsharkPath: vm.tsharkPath,
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
    showDialog(
      context: context,
      builder: (ctx) => _PassivePortDialog(vm: vm),
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

    final bool isDark = AppTheme.isDark;
    final infoText = isDark ? const Color(0xFF64B5F6) : AppTheme.info;
    final warnText = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);
    final successText = isDark ? const Color(0xFF81C784) : AppTheme.success;
    final fastLeaveLabelColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    final ssmAccent = isDark ? const Color(0xFF4DD0E1) : const Color(0xFF0E7490);
    final scanBorderColor = vm.isFloodingScanRunning
        ? (isDark ? const Color(0xFF00BCD4) : const Color(0xFF0891B2))
        : (isDark ? const Color(0xFF26A69A) : const Color(0xFF0F766E));
    final bandwidthColor = isDark ? const Color(0xFFBA68C8) : const Color(0xFF7E22CE);
    final jitterColor = isDark ? const Color(0xFF00BCD4) : const Color(0xFF0891B2);

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
                  Icon(Icons.call_received_rounded, color: AppTheme.info, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Multi-Group Multicast Receiver & IGMP Join Subscriptions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
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
                          color: passiveOnly ? AppTheme.warning : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'No-Join Mode:',
                          style: TextStyle(
                            fontSize: 12,
                            color: passiveOnly ? warnText : AppTheme.textSecondary,
                            fontWeight: passiveOnly ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: passiveOnly,
                          activeThumbColor: AppTheme.warning,
                          onChanged: isRunning ? null : (val) => vm.updateReceiverPassiveMode(val),
                        ),
                      ],
                    ),
                  ),

                  // Loopback switch
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Loopback:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Fast-Leave Probe:',
                          style: TextStyle(
                            fontSize: 12,
                            color: vm.measureFastLeave
                                ? fastLeaveLabelColor
                                : AppTheme.textSecondary,
                            fontWeight: vm.measureFastLeave
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Switch(
                          value: vm.measureFastLeave,
                          activeThumbColor: AppTheme.success,
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
                      backgroundColor: AppTheme.info.withValues(alpha: isDark ? 0.22 : 0.10),
                      foregroundColor: infoText,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      side: BorderSide(color: AppTheme.info, width: 1.2),
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
                      foregroundColor: ssmAccent,
                      side: BorderSide(
                        color: scanBorderColor,
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
              MetricCard(
                title: 'Subscribed Groups',
                value: '${stats.activeStreamsCount} / ${streams.length}',
                unit: 'groups',
                icon: Icons.hub,
                color: AppTheme.info,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Packets Received',
                value: '${stats.packetsReceived} / ${stats.expectedPackets}',
                unit: 'pkts',
                icon: Icons.check_circle_outline,
                color: AppTheme.success,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Aggregate Loss Rate',
                value: '${stats.lossRatePercent.toStringAsFixed(2)}%',
                unit: '${stats.packetsLost} dropped',
                icon: Icons.warning_amber_rounded,
                color: stats.lossRatePercent > 0
                    ? (stats.lossRatePercent > 5.0 ? AppTheme.error : AppTheme.warning)
                    : AppTheme.success,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Total Gaps Detected',
                value: stats.totalGaps.toString(),
                unit: 'drop events',
                icon: Icons.broken_image_outlined,
                color: stats.totalGaps > 0 ? AppTheme.warning : AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Inbound Rate & Network Timing
          Row(
            children: [
              MetricCard(
                title: 'Aggregate Arrival Rate',
                value: stats.currentPps.toStringAsFixed(0),
                unit: 'pps',
                icon: Icons.speed,
                color: AppTheme.info,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Total Inbound Bitrate',
                value: stats.currentBitrateMbps.toStringAsFixed(2),
                unit: 'Mbps',
                icon: Icons.network_check,
                color: bandwidthColor,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Average Jitter',
                value: stats.jitterMs.toStringAsFixed(3),
                unit: 'ms',
                icon: Icons.waves,
                color: jitterColor,
              ),
              const SizedBox(width: 12),
              MetricCard(
                title: 'Unsubscribed / Flooded',
                value: '${unsubscribed.length} (${stats.unsubscribedPacketsReceived})',
                unit: 'grps (pkts)',
                icon: unsubscribed.isNotEmpty ? Icons.gpp_maybe : Icons.verified_user_outlined,
                color: unsubscribed.isNotEmpty ? AppTheme.error : AppTheme.success,
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
                          ? const Color(0xFFB45309)
                          : (isRunning
                              ? (isDark ? const Color(0xFF8B0000) : AppTheme.error)
                              : (passiveOnly ? const Color(0xFFC2410C) : AppTheme.info)),
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              if (streams.isNotEmpty)
                Text(
                  'Monitor continuity, drops, and jitter across each individual group',
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
                      Expanded(flex: 3, child: Text('Stream / Group Name', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 4, child: Text('Multicast Address & Port', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Received', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Loss %', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Gaps', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Bitrate', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Jitter', style: AppTheme.tableHeaderStyle)),
                      SizedBox(width: 132, child: Text('Actions', style: AppTheme.tableHeaderStyle)),
                    ],
                  ),
                ),

                if (streams.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No multicast groups subscribed. Click "Add Group" or "Batch Join" above to configure groups.',
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
                      final isStreamActive = vm.isReceiverStreamActive(stream.id);
                      final isStreamMeasuring = vm.isStreamMeasuringLeave(stream.id);
                      final rStats = vm.streamReceiverStats[stream.id];
                      final effectiveJoin = stream.joinGroup && !passiveOnly;

                      final lossPct = rStats?.lossRatePercent ?? 0.0;
                      Color lossColor = isDark ? AppTheme.success : const Color(0xFF047857);
                      if (lossPct > 5.0) {
                        lossColor = isDark ? AppTheme.error : const Color(0xFFB91C1C);
                      } else if (lossPct > 0.0) {
                        lossColor = warnText;
                      }

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
                                  color: isStreamMeasuring
                                      ? AppTheme.warning
                                      : (isStreamActive
                                          ? (effectiveJoin ? AppTheme.info : AppTheme.warning)
                                          : AppTheme.textMuted),
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
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (stream.isSsm && stream.hasSourceFilter)
                                    Text(
                                      'src: ${stream.normalizedSourceIp}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: ssmAccent,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  if (rStats != null &&
                                      rStats.dscpTransitStatus != DscpTransitStatus.unverified)
                                    Builder(
                                      builder: (_) {
                                        final observedDscp =
                                            rStats.receivedDscp ?? rStats.packetHintDscp;
                                        final badge = observedDscp != null
                                            ? DscpPreset.formatDscpBadge(observedDscp)
                                            : null;
                                        final tagSuffix = rStats.dscpVerifiedByOsTos
                                            ? ''
                                            : ' · Sender Tag';
                                        final labelText = rStats.dscpTransitStatus ==
                                                DscpTransitStatus.preserved
                                            ? 'QoS Preserved (${badge ?? rStats.expectedDscp?.shortLabel ?? "OK"})$tagSuffix'
                                            : 'QoS Alert (${badge ?? "Stripped"})$tagSuffix';
                                        return Text(
                                          labelText,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: rStats.dscpTransitStatus ==
                                                    DscpTransitStatus.preserved
                                                ? fastLeaveLabelColor
                                                : (isDark
                                                    ? const Color(0xFFFCA5A5)
                                                    : AppTheme.error),
                                          ),
                                        );
                                      },
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
                                    color: effectiveJoin ? AppTheme.info : AppTheme.warning,
                                  ),
                                  Text(
                                    stream.endpoint,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: infoText,
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
                                              ? AppTheme.info.withValues(alpha: isDark ? 0.15 : 0.10)
                                              : AppTheme.warning.withValues(alpha: isDark ? 0.2 : 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: effectiveJoin
                                                ? AppTheme.info.withValues(alpha: 0.5)
                                                : AppTheme.warning.withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: Text(
                                          effectiveJoin ? 'IGMP Join' : 'No Join',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: effectiveJoin ? infoText : warnText,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (stream.isSsm)
                                    Tooltip(
                                      message: rStats?.ssmDiagnosticNote ??
                                          (stream.hasSourceFilter
                                              ? 'Source-Specific Multicast filter: ${stream.normalizedSourceIp}'
                                              : 'Source-Specific Multicast (S, G)'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: ssmAccent.withValues(alpha: isDark ? 0.15 : 0.10),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: ssmAccent.withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Text(
                                          'SSM (S, G)',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: ssmAccent,
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
                                style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
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
                                  color: isStreamActive ? lossColor : AppTheme.textSecondary,
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
                                  color: (rStats?.totalGaps ?? 0) > 0
                                      ? warnText
                                      : AppTheme.textSecondary,
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
                                  color: isStreamActive ? successText : AppTheme.textSecondary,
                                ),
                              ),
                            ),

                            // Jitter
                            Expanded(
                              flex: 2,
                              child: Text(
                                rStats != null ? '${rStats.jitterMs.toStringAsFixed(2)} ms' : '—',
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
                                      isStreamMeasuring
                                          ? Icons.hourglass_top_rounded
                                          : (isStreamActive ? Icons.stop_circle_outlined : Icons.play_circle_fill),
                                      size: 18,
                                      color: isStreamMeasuring
                                          ? AppTheme.warning
                                          : (isStreamActive ? AppTheme.error : AppTheme.info),
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
                                    icon: Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary),
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
                                    icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.textSecondary),
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
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Live Aggregate Inbound Throughput Stability (Mbps)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      'Aggregate: ${stats.currentBitrateMbps.toStringAsFixed(2)} Mbps',
                      style: TextStyle(fontSize: 11, color: AppTheme.info),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vm.rxThroughputHistory.length < 2
                      ? Center(
                          child: Text(
                            isRunning ? 'Collecting aggregate throughput telemetry...' : 'Receivers are idle',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        )
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: AppTheme.border,
                                strokeWidth: 0.8,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 38,
                                  getTitlesWidget: (value, meta) => SideTitleWidget(
                                    meta: meta,
                                    space: 6,
                                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                    child: Text(
                                      value.toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border(
                                bottom: BorderSide(color: AppTheme.border),
                                left: BorderSide(color: AppTheme.border),
                              ),
                            ),
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => AppTheme.surfaceElevated,
                                tooltipBorder: BorderSide(color: AppTheme.borderStrong),
                                getTooltipItems: (spots) => spots
                                    .map(
                                      (s) => LineTooltipItem(
                                        '${s.y.toStringAsFixed(2)} Mbps',
                                        TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: vm.rxThroughputHistory
                                    .asMap()
                                    .entries
                                    .map((e) => FlSpot(e.key.toDouble(), e.value))
                                    .toList(),
                                isCurved: true,
                                color: AppTheme.info,
                                barWidth: 2,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppTheme.info.withValues(alpha: isDark ? 0.26 : 0.20),
                                      AppTheme.info.withValues(alpha: 0.0),
                                    ],
                                  ),
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
    final bool isDark = AppTheme.isDark;
    final hasLeak = unsubscribed.isNotEmpty;
    final errorText = isDark ? const Color(0xFFFF8A80) : const Color(0xFF991B1B);
    final successText = isDark ? const Color(0xFF81C784) : const Color(0xFF047857);
    final warnText = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);

    Color borderColor = AppTheme.border;
    Color headerBg = AppTheme.surfaceHigh;
    if (hasLeak) {
      borderColor = AppTheme.error.withValues(alpha: 0.7);
      headerBg = isDark ? AppTheme.error.withValues(alpha: 0.15) : const Color(0xFFFEF2F2);
    } else if (isReceiverRunning || isPassivePortActive) {
      borderColor = AppTheme.success.withValues(alpha: 0.5);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
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
                          ? AppTheme.error
                          : (isReceiverRunning ? AppTheme.success : AppTheme.warning),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'IGMP Snooping & Unsubscribed Stream Verification',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasLeak
                            ? AppTheme.error.withValues(alpha: isDark ? 0.25 : 0.12)
                            : (isReceiverRunning
                                ? AppTheme.success.withValues(alpha: isDark ? 0.2 : 0.12)
                                : AppTheme.borderStrong.withValues(alpha: 0.5)),
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
                              ? errorText
                              : (isReceiverRunning ? successText : AppTheme.textPrimary),
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
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.borderStrong),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.settings_ethernet, size: 13, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Port: $passivePort',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: AppTheme.textPrimary,
                              ),
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
                            ? (isDark ? const Color(0xFF8B0000) : AppTheme.error)
                            : AppTheme.warning.withValues(alpha: isDark ? 0.22 : 0.10),
                        foregroundColor: isPassivePortActive ? Colors.white : warnText,
                        elevation: isPassivePortActive ? null : 0,
                        shadowColor: isPassivePortActive ? null : Colors.transparent,
                        side: BorderSide(
                          color: isPassivePortActive ? AppTheme.error : AppTheme.warning,
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
                          foregroundColor: AppTheme.textPrimary,
                          side: BorderSide(color: AppTheme.borderStrong),
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
                style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: isDark ? AppTheme.error.withValues(alpha: 0.08) : const Color(0xFFFEF2F2),
                  child: Text(
                    '⚠️ Unsubscribed multicast traffic is reaching this interface! This indicates IGMP Snooping may be disabled on the switch, or an upstream port is flooding unknown multicast.',
                    style: TextStyle(fontSize: 11.5, color: errorText),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: AppTheme.surfaceHigh,
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text('Flooded Group & Port', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 3, child: Text('Sender Source IP', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Session ID', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 2, child: Text('Flooded Packets', style: AppTheme.tableHeaderStyle)),
                      Expanded(flex: 3, child: Text('Flood Bitrate / Rate', style: AppTheme.tableHeaderStyle)),
                      SizedBox(width: 110, child: Text('Action', style: AppTheme.tableHeaderStyle)),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: unsubscribed.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.border),
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
                                Icon(Icons.gpp_maybe, size: 14, color: AppTheme.error),
                                const SizedBox(width: 6),
                                Text(
                                  item.endpoint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: errorText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              item.sourceIp,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.sessionId,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${item.packetsReceived} pkts',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${item.currentBitrateMbps.toStringAsFixed(2)} Mbps (${item.currentPps.toStringAsFixed(0)} pps)',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: warnText,
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

class _FastLeaveLatencyPill extends StatelessWidget {
  final LeaveLatencyResult result;
  final VoidCallback? onClear;

  const _FastLeaveLatencyPill({required this.result, this.onClear});

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    final Color color;
    final Color textColor;
    final IconData icon;
    final String text;

    switch (result.status) {
      case FastLeaveStatus.measuring:
        color = AppTheme.warning;
        textColor = isDark ? AppTheme.warning : const Color(0xFFB45309);
        icon = Icons.hourglass_top_rounded;
        text = 'Measuring Leave... (${result.trailingPacketsReceived} trailing)';
      case FastLeaveStatus.fastLeaveActive:
        color = AppTheme.success;
        textColor = isDark ? AppTheme.success : const Color(0xFF047857);
        icon = Icons.bolt;
        text = '${result.leaveLatencyMs} ms — Fast-Leave · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.delayedPrune:
        color = AppTheme.warning;
        textColor = isDark ? AppTheme.warning : const Color(0xFFB45309);
        icon = Icons.schedule;
        text = '${result.leaveLatencyMs} ms — Delayed Prune · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.noFastLeave:
        color = AppTheme.error;
        textColor = isDark ? AppTheme.error : const Color(0xFFB91C1C);
        icon = Icons.warning_amber_rounded;
        text = '${result.leaveLatencyMs} ms — No Fast-Leave · ${result.trailingPacketsReceived} trailing';
      case FastLeaveStatus.inconclusive:
        color = AppTheme.textSecondary;
        textColor = AppTheme.textSecondary;
        icon = Icons.info_outline;
        text = 'No Traffic Before Leave (Inconclusive)';
      case FastLeaveStatus.aborted:
        color = AppTheme.textSecondary;
        textColor = AppTheme.textSecondary;
        icon = Icons.cancel_outlined;
        text = 'Leave Measurement Aborted (${result.trailingPacketsReceived} trailing)';
      case FastLeaveStatus.notMeasured:
        color = AppTheme.textSecondary;
        textColor = AppTheme.textSecondary;
        icon = Icons.timer_off_outlined;
        text = 'Fast-Leave Not Measured';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onClear,
              child: Icon(Icons.close, size: 13, color: textColor),
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
    final bool isDark = AppTheme.isDark;
    final expected = stats.expectedDscp ?? stats.senderDscpPreset;
    final expectedLabel = expected?.shortLabel ?? 'QoS';
    final observedDscp = stats.receivedDscp ?? stats.packetHintDscp;
    final rxLabel = observedDscp != null
        ? DscpPreset.formatDscpBadge(observedDscp)
        : 'Unverified';
    final sourceTag = stats.dscpVerifiedByOsTos ? '' : ' · Sender Tag';

    final Color color;
    final Color textColor;
    final IconData icon;
    final String label;

    switch (stats.dscpTransitStatus) {
      case DscpTransitStatus.preserved:
        color = AppTheme.success;
        textColor = isDark ? AppTheme.success : const Color(0xFF047857);
        icon = Icons.verified_outlined;
        label = 'QoS Preserved · $rxLabel$sourceTag';
      case DscpTransitStatus.remarkedToZero:
        color = AppTheme.error;
        textColor = isDark ? AppTheme.error : const Color(0xFFB91C1C);
        icon = Icons.gpp_bad_outlined;
        label = 'QoS Stripped · Sent $expectedLabel -> Received $rxLabel$sourceTag';
      case DscpTransitStatus.remarkedOrStripped:
        color = AppTheme.warning;
        textColor = isDark ? AppTheme.warning : const Color(0xFFB45309);
        icon = Icons.warning_amber_rounded;
        label = 'QoS Remarked · Sent $expectedLabel -> Received $rxLabel$sourceTag';
      case DscpTransitStatus.unverified:
        color = isDark ? const Color(0xFF60A5FA) : AppTheme.info;
        textColor = color;
        icon = Icons.label_important_outline;
        final tagLabel =
            stats.senderDscpPreset?.shortLabel ?? stats.expectedDscp?.shortLabel;
        label = tagLabel != null
            ? 'Sender Tag: $tagLabel · OS TOS Unverified'
            : 'QoS Expect $expectedLabel (OS TOS Unverified)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassivePortDialog extends StatefulWidget {
  final IgmpTesterViewModel vm;

  const _PassivePortDialog({required this.vm});

  @override
  State<_PassivePortDialog> createState() => _PassivePortDialogState();
}

class _PassivePortDialogState extends State<_PassivePortDialog> {
  late final TextEditingController _portCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _portCtrl = TextEditingController(
      text: widget.vm.receiverConfig.passiveListenPort.toString(),
    );
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final p = int.tryParse(_portCtrl.text.trim());
    if (p == null || p < 1 || p > 65535) {
      setState(() {
        _errorText = 'Enter a valid UDP port (1–65535)';
      });
      return;
    }
    widget.vm.updateReceiverPassivePort(p);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.hearing_outlined, color: AppTheme.warning, size: 20),
          const SizedBox(width: 8),
          Text(
            'Configure No-Subscription Server Port',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bind a UDP socket on this port WITHOUT sending an IGMP Join to test if the network switch floods unsubscribed multicast streams.',
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
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.warning,
            foregroundColor: Colors.black,
          ),
          onPressed: _submit,
          child: const Text(
            'Save Port',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
    final bool isDark = AppTheme.isDark;
    final accentText = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;
    final ssmHintColor = isDark ? const Color(0xFF4DD0E1) : const Color(0xFF0E7490);
    final showSsmRangeHint =
        _joinMode == IgmpJoinMode.ssm &&
        _groupCtrl.text.trim().isNotEmpty &&
        MulticastStreamConfig.isValidMulticastIpv4(_groupCtrl.text.trim()) &&
        !MulticastReceiverStreamConfig.isSsmGroupIpv4(_groupCtrl.text.trim());

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      title: Row(
        children: [
          Icon(
            _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            color: AppTheme.info,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _isEditing ? 'Edit Multicast Group' : 'Add Multicast Group to Join',
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
                    border: Border.all(color: AppTheme.info.withValues(alpha: 0.4)),
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
                        child: Text(
                          _selectedPreset.description,
                          style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
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
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tip: IANA designates 232.0.0.0/8 for standard IGMPv3 SSM groups.',
                    style: TextStyle(fontSize: 10.5, color: ssmHintColor),
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
                      dropdownColor: AppTheme.surfaceElevated,
                      isExpanded: true,
                      items: IgmpJoinMode.values.map((mode) {
                        return DropdownMenuItem<IgmpJoinMode>(
                          value: mode,
                          child: Text(
                            mode.label,
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          ),
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
                dropdownColor: AppTheme.surfaceElevated,
                isExpanded: true,
                items: [
                  DropdownMenuItem<DscpPreset?>(
                    value: null,
                    child: Text(
                      'Auto (Match Sender Tag)',
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    ),
                  ),
                  ...DscpPreset.values.map((preset) {
                    return DropdownMenuItem<DscpPreset?>(
                      value: preset,
                      child: Text(
                        preset.dropdownLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
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
                title: Text(
                  'Send IGMP Join (uncheck to listen passively for flooding)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.info,
            foregroundColor: Colors.white,
          ),
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
    final bool isDark = AppTheme.isDark;
    final accentText = isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.auto_awesome_motion, color: AppTheme.info, size: 20),
          const SizedBox(width: 8),
          Text(
            'Batch Subscribe Multicast Groups',
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
              Text(
                'Quickly subscribe to multiple multicast groups to test switch IGMP snooping tables, querier capacity, and selective group pruning.',
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
              if (_selectedPreset != ProtocolPreset.custom) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.info.withValues(alpha: 0.4)),
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
                        child: Text(
                          _selectedPreset.description,
                          style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
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
                title: Text(
                  'Increment UDP port for each group (port + 1)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.info,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Generate & Add', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
