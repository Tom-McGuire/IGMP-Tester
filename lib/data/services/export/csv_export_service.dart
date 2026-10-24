import 'dart:io';
import '../../../domain/models/multicast_gap_event.dart';
import '../../../domain/models/multicast_stats.dart';

class CsvExportService {
  String generateGapsCsv({
    required List<MulticastGapEvent> gaps,
    ReceiverStats? stats,
  }) {
    final buffer = StringBuffer();

    // If summary stats provided, write summary block
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
      buffer.writeln();
    }

    // CSV Table headers
    buffer.writeln('Gap_ID,Stream_Name,Group_Address,UDP_Port,Session_ID,Timestamp,Start_Sequence,End_Sequence,Lost_Packets,Gap_Duration_MS,Last_Packet_Time,Resumed_Time');

    for (final gap in gaps) {
      buffer.writeln(
        '${gap.id},"${gap.streamName}",${gap.groupAddress},${gap.port},${gap.sessionId},${gap.timestamp.toIso8601String()},${gap.startSeq},${gap.endSeq},${gap.missingPackets},${gap.gapDurationMs.toStringAsFixed(3)},${gap.lastPacketTime.toIso8601String()},${gap.resumedTime.toIso8601String()}',
      );
    }

    return buffer.toString();
  }

  Future<void> saveCsvToFile(String filePath, String csvContent) async {
    final file = File(filePath);
    await file.writeAsString(csvContent);
  }
}
