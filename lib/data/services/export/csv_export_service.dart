import 'dart:io';
import 'package:csv/csv.dart';
import '../../../domain/models/dscp_preset.dart';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_stats.dart';

class CsvExportService {
  /// Sanitize cell against CSV / spreadsheet formula injection
  static String sanitizeForCsv(String value) {
    if (value.isEmpty) return value;
    final first = value[0];
    if (first == '=' || first == '+' || first == '-' || first == '@' || first == '\t' || first == '\r') {
      return "'$value";
    }
    return value;
  }

  String generateGapsCsv({
    required List<MulticastGapEvent> gaps,
    ReceiverStats? stats,
  }) {
    final List<List<dynamic>> rows = [];

    // Table header
    rows.add([
      'Gap_ID',
      'Stream_Name',
      'Group_Address',
      'UDP_Port',
      'Session_ID',
      'Timestamp',
      'Start_Sequence',
      'End_Sequence',
      'Lost_Packets',
      'Gap_Duration_MS',
      'Last_Packet_Time',
      'Resumed_Time',
      'Last_Leave_Latency_Ms',
      'Fast_Leave_Status',
      'Trailing_Packets_After_Leave',
    ]);

    for (final gap in gaps) {
      final matchedLeave = _findLeaveResultForGap(gap, stats);
      rows.add([
        gap.id,
        sanitizeForCsv(gap.streamName),
        gap.groupAddress,
        gap.port,
        sanitizeForCsv(gap.sessionId),
        gap.timestamp.toIso8601String(),
        gap.startSeq,
        gap.endSeq,
        gap.missingPackets,
        double.parse(gap.gapDurationMs.toStringAsFixed(3)),
        gap.lastPacketTime.toIso8601String(),
        gap.resumedTime.toIso8601String(),
        matchedLeave?.leaveLatencyMs ?? '',
        matchedLeave != null ? sanitizeForCsv(matchedLeave.status.label) : '',
        matchedLeave?.trailingPacketsReceived ?? '',
      ]);
    }

    final csvBody = csv.encode(rows);

    final buffer = StringBuffer();
    if (stats != null) {
      buffer.writeln('# IGMP Multicast Tester Report');
      buffer.writeln('# Generated at,${DateTime.now().toIso8601String()}');
      buffer.writeln('# Active Streams,${stats.activeStreamsCount}');
      buffer.writeln('# Packets Received,${stats.packetsReceived}');
      buffer.writeln('# Packets Expected,${stats.expectedPackets}');
      buffer.writeln('# Packets Lost,${stats.packetsLost}');
      buffer.writeln('# Loss Rate %,${stats.lossRatePercent.toStringAsFixed(2)}%');
      buffer.writeln('# Total Gaps,${stats.totalGaps}');
      buffer.writeln('# Max Gap Duration (ms),${stats.maxGapDurationMs.toStringAsFixed(2)}');
      buffer.writeln('# Average Gap Duration (ms),${stats.avgGapDurationMs.toStringAsFixed(2)}');
      buffer.writeln('# RFC 3550 Jitter (ms),${stats.jitterMs.toStringAsFixed(3)}');
      final leaveResult = stats.lastLeaveLatency;
      if (leaveResult != null) {
        buffer.writeln('# Leave Latency (ms),${leaveResult.leaveLatencyMs}');
        buffer.writeln('# Fast-Leave Status,${leaveResult.status.label}');
        buffer.writeln('# Trailing Packets After Leave,${leaveResult.trailingPacketsReceived}');
      }
      if (stats.expectedDscp != null ||
          stats.senderDscpPreset != null ||
          stats.receivedDscp != null ||
          stats.dscpTransitStatus != DscpTransitStatus.unverified) {
        final expectedLabel =
            stats.expectedDscp?.shortLabel ??
            stats.senderDscpPreset?.shortLabel ??
            'Unset';
        final receivedLabel = stats.receivedDscp != null
            ? DscpPreset.formatDscpBadge(stats.receivedDscp!)
            : 'Unverified';
        buffer.writeln('# Expected DSCP,$expectedLabel');
        buffer.writeln('# Received DSCP,$receivedLabel');
        buffer.writeln('# DSCP Transit Status,${stats.dscpTransitStatus.name}');
      }
      buffer.writeln();
    }
    buffer.write(csvBody);

    return buffer.toString();
  }

  LeaveLatencyResult? _findLeaveResultForGap(
    MulticastGapEvent gap,
    ReceiverStats? stats,
  ) {
    if (stats == null) return null;
    for (final entry in stats.leaveLatencyByStream.values) {
      if (entry.groupIp == gap.groupAddress && entry.port == gap.port) {
        return entry;
      }
    }
    final last = stats.lastLeaveLatency;
    if (last != null &&
        last.groupIp == gap.groupAddress &&
        last.port == gap.port) {
      return last;
    }
    return null;
  }

  Future<void> saveCsvToFile(String filePath, String csvContent) async {
    final file = File(filePath);
    await file.writeAsString(csvContent);
  }
}
