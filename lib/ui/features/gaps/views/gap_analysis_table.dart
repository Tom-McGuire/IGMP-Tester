import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/multicast_gap_event.dart';
import '../../../theme/app_theme.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class GapAnalysisTable extends StatefulWidget {
  const GapAnalysisTable({super.key});

  @override
  State<GapAnalysisTable> createState() => _GapAnalysisTableState();
}

class _GapAnalysisTableState extends State<GapAnalysisTable> {
  final TextEditingController _searchCtrl = TextEditingController();
  final DateFormat _timeFormat = DateFormat('HH:mm:ss.SSS');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportCsv(BuildContext context, IgmpTesterViewModel vm) async {
    final defaultFileName = 'igmp_multicast_gaps_${DateTime.now().millisecondsSinceEpoch}.csv';
    final csvContent = vm.generateGapsCsvContent();

    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Multicast Gap Analysis CSV',
      fileName: defaultFileName,
      bytes: Uint8List.fromList(utf8.encode(csvContent)),
    );

    if (uri != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Gap report saved successfully.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final gaps = vm.filteredGaps;
    final stats = vm.receiverStats;

    final gapsBadgeColor = stats.totalGaps > 0 ? AppTheme.warning : AppTheme.success;
    final gapsTextColor = AppTheme.isDark
        ? gapsBadgeColor
        : (stats.totalGaps > 0 ? const Color(0xFFB45309) : const Color(0xFF047857));

    final droppedBadgeColor = stats.packetsLost > 0 ? AppTheme.error : AppTheme.success;
    final droppedTextColor = AppTheme.isDark
        ? droppedBadgeColor
        : (stats.packetsLost > 0 ? const Color(0xFFB91C1C) : const Color(0xFF047857));

    final durationBadgeColor =
        AppTheme.isDark ? const Color(0xFFF472B6) : const Color(0xFFBE185D);

    return Column(
      children: [
        // Top Toolbar: Search & Action buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(
              bottom: BorderSide(color: AppTheme.border),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  // Search input
                  SizedBox(
                    width: 280,
                    height: 34,
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textSecondary),
                        hintText: 'Filter by stream, group, or sequence...',
                        hintStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 14, color: AppTheme.textSecondary),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  vm.setGapFilter('');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => vm.setGapFilter(val),
                    ),
                  ),

                  // Gap statistics badges
                  _SummaryBadge(
                    label: 'Total Gaps',
                    value: stats.totalGaps.toString(),
                    color: gapsBadgeColor,
                    textColor: gapsTextColor,
                  ),
                  _SummaryBadge(
                    label: 'Packets Dropped',
                    value: stats.packetsLost.toString(),
                    color: droppedBadgeColor,
                    textColor: droppedTextColor,
                  ),
                  _SummaryBadge(
                    label: 'Max Gap Duration',
                    value: '${stats.maxGapDurationMs.toStringAsFixed(1)} ms',
                    color: durationBadgeColor,
                    textColor: durationBadgeColor,
                  ),
                ],
              ),

              // Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                    onPressed: (gaps.isEmpty && vm.lastLeaveLatency == null)
                        ? null
                        : () => _exportCsv(context, vm),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: BorderSide(color: AppTheme.borderStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    onPressed: gaps.isEmpty ? null : () => vm.clearGaps(),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Table Header
        Container(
          color: AppTheme.surfaceHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 45, child: Text('#', style: _headerStyle)),
              SizedBox(width: 115, child: Text('Time Detected', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Stream / Group Address', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Missing Sequence Range', style: _headerStyle)),
              Expanded(flex: 2, child: Text('Lost Count', style: _headerStyle)),
              Expanded(flex: 2, child: Text('Gap Duration (ms)', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Last Good Packet', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Resumed Packet', style: _headerStyle)),
            ],
          ),
        ),

        // Table Content
        Expanded(
          child: gaps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        stats.packetsReceived > 0 ? Icons.verified : Icons.timeline,
                        size: 48,
                        color: stats.packetsReceived > 0 ? AppTheme.success : AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        stats.packetsReceived > 0
                            ? 'No Data Gaps Detected (100% Multicast Continuity)'
                            : 'No Multicast Packets Received Yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stats.packetsReceived > 0
                            ? 'All ${stats.packetsReceived} packets across ${stats.activeStreamsCount} groups arrived sequentially.'
                            : 'Start transmitters and receivers to begin multi-stream continuity monitoring.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: gaps.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.border),
                  itemBuilder: (context, index) {
                    final gap = gaps[index];
                    return _GapTableRow(
                      gap: gap,
                      timeFormat: _timeFormat,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

TextStyle get _headerStyle => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: AppTheme.textSecondary,
    );

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color? textColor;

  const _SummaryBadge({
    required this.label,
    required this.value,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor ?? color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GapTableRow extends StatelessWidget {
  final MulticastGapEvent gap;
  final DateFormat timeFormat;

  const _GapTableRow({
    required this.gap,
    required this.timeFormat,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    final streamColor = isDark ? const Color(0xFF64B5F6) : AppTheme.info;
    final seqColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB45309);
    final lostBgColor = isDark ? const Color(0xFF5A1D1D) : const Color(0xFFFEE2E2);
    final lostTextColor = isDark ? const Color(0xFFFF8B8B) : const Color(0xFF991B1B);
    final highGapColor = isDark ? const Color(0xFFF472B6) : const Color(0xFFBE185D);

    return Container(
      color: gap.id % 2 == 0 ? AppTheme.surfaceAlt : AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              '#${gap.id}',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: 115,
            child: Text(
              timeFormat.format(gap.timestamp),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          // Stream / Group Address
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.hub, size: 12, color: AppTheme.info),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${gap.streamName} (${gap.endpoint})',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: streamColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.arrow_right, size: 14, color: AppTheme.warning),
                Text(
                  gap.sequenceRange,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: seqColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: lostBgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${gap.missingPackets} pkts lost',
                style: TextStyle(
                  fontSize: 11,
                  color: lostTextColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${gap.gapDurationMs.toStringAsFixed(1)} ms',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: gap.gapDurationMs > 50.0 ? highGapColor : AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Seq #${gap.startSeq - 1} (${timeFormat.format(gap.lastPacketTime)})',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Seq #${gap.endSeq + 1} (${timeFormat.format(gap.resumedTime)})',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
