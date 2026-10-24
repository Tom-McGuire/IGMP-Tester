import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/multicast_gap_event.dart';
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
        const SnackBar(
          content: Text('Gap report saved successfully.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final gaps = vm.filteredGaps;
    final stats = vm.receiverStats;

    return Column(
      children: [
        // Top Toolbar: Search & Action buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? const Color(0xFF2C2C2C)),
            ),
          ),
          child: Row(
            children: [
              // Search input
              SizedBox(
                width: 280,
                height: 34,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 16),
                    hintText: 'Filter by sequence or session...',
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
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
              const SizedBox(width: 16),

              // Gap statistics badges
              _SummaryBadge(
                label: 'Total Gaps',
                value: stats.totalGaps.toString(),
                color: stats.totalGaps > 0 ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 8),
              _SummaryBadge(
                label: 'Packets Dropped',
                value: stats.packetsLost.toString(),
                color: stats.packetsLost > 0 ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 8),
              _SummaryBadge(
                label: 'Max Gap Duration',
                value: '${stats.maxGapDurationMs.toStringAsFixed(1)} ms',
                color: const Color(0xFFE91E63),
              ),

              const Spacer(),

              // Export CSV Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007ACC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                onPressed: gaps.isEmpty ? null : () => _exportCsv(context, vm),
              ),
              const SizedBox(width: 8),

              // Clear Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Color(0xFF3E3E42)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('Clear', style: TextStyle(fontSize: 12)),
                onPressed: gaps.isEmpty ? null : () => vm.clearGaps(),
              ),
            ],
          ),
        ),

        // Table Header
        Container(
          color: const Color(0xFF252526),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            children: [
              SizedBox(width: 50, child: Text('#', style: _headerStyle)),
              SizedBox(width: 120, child: Text('Time Detected', style: _headerStyle)),
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
                        color: stats.packetsReceived > 0 ? const Color(0xFF4CAF50) : Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        stats.packetsReceived > 0
                            ? 'No Data Gaps Detected (100% Packet Continuity)'
                            : 'No Multicast Packets Received Yet',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stats.packetsReceived > 0
                            ? 'All ${stats.packetsReceived} packets arrived sequentially without drops.'
                            : 'Start the receiver or transmitter to begin monitoring sequence continuity.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: gaps.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF282828)),
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

const TextStyle _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.bold,
  color: Colors.grey,
);

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryBadge({
    required this.label,
    required this.value,
    required this.color,
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
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
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
    return Container(
      color: gap.id % 2 == 0 ? const Color(0xFF1A1A1A) : const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '#${gap.id}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              timeFormat.format(gap.timestamp),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(Icons.arrow_right, size: 14, color: Color(0xFFFF9800)),
                Text(
                  gap.sequenceRange,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: Color(0xFFFFB74D),
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
                color: const Color(0xFF5A1D1D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${gap.missingPackets} pkts lost',
                style: const TextStyle(fontSize: 11, color: Color(0xFFFF8B8B), fontWeight: FontWeight.bold),
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
                color: gap.gapDurationMs > 50.0 ? const Color(0xFFE91E63) : Colors.white70,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Seq #${gap.startSeq - 1} (${timeFormat.format(gap.lastPacketTime)})',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Seq #${gap.endSeq + 1} (${timeFormat.format(gap.resumedTime)})',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
