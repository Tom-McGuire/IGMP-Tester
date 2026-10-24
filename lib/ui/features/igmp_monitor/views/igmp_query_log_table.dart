import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/igmp_query_event.dart';
import '../../../../data/services/igmp/igmp_querier_watchdog.dart';
import '../../dashboard/view_models/igmp_tester_view_model.dart';

class IgmpQueryLogTable extends StatelessWidget {
  const IgmpQueryLogTable({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final events = vm.igmpEvents;
    final querierStatus = vm.querierStatus;
    final timeFormat = DateFormat('HH:mm:ss.SSS');

    return Column(
      children: [
        // Querier Health & Watchdog Banner
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Color(querierStatus.health.colorHex).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Color(querierStatus.health.colorHex)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          querierStatus.health == QuerierHealth.active
                              ? Icons.check_circle
                              : (querierStatus.health == QuerierHealth.warning
                                  ? Icons.warning_amber
                                  : Icons.info_outline),
                          size: 15,
                          color: Color(querierStatus.health.colorHex),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          querierStatus.health.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(querierStatus.health.colorHex),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  if (querierStatus.querierIp != null) ...[
                    const Text('Querier IP: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      querierStatus.querierIp!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                  ],
                  if (querierStatus.secondsSinceLastQuery != null) ...[
                    const Text('Last Query: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      '${querierStatus.secondsSinceLastQuery}s ago',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF4FC1FF),
                      ),
                    ),
                  ],
                  const Spacer(),

                  // TShark Sniffer Toggle
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vm.isSnifferRunning ? const Color(0xFF8B0000) : const Color(0xFF007ACC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: Icon(vm.isSnifferRunning ? Icons.stop : Icons.radar, size: 14),
                    label: Text(
                      vm.isSnifferRunning ? 'Stop IGMP Sniffer' : 'Start IGMP Sniffer',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => vm.toggleSniffer(),
                  ),
                  const SizedBox(width: 8),

                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Color(0xFF3E3E42)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Clear Log', style: TextStyle(fontSize: 12)),
                    onPressed: events.isEmpty ? null : () => vm.clearIgmpLogs(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                querierStatus.statusMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: querierStatus.health == QuerierHealth.critical
                      ? const Color(0xFFFF8B8B)
                      : Colors.grey.shade400,
                ),
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
              SizedBox(width: 110, child: Text('Timestamp', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Querier / Sender IP', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Destination IP', style: _headerStyle)),
              Expanded(flex: 3, child: Text('IGMP Message Type', style: _headerStyle)),
              Expanded(flex: 3, child: Text('Group Address', style: _headerStyle)),
              SizedBox(width: 100, child: Text('Max Resp Time', style: _headerStyle)),
              SizedBox(width: 60, child: Text('Ver', style: _headerStyle)),
            ],
          ),
        ),

        // Table List
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.radar, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'No IGMP Packets Logged Yet',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vm.isSnifferRunning
                            ? 'Listening for periodic IGMP Membership Queries (sent every 60s–125s by your switch/router)...'
                            : (vm.hasTShark
                                ? 'Click "Start IGMP Sniffer" above to start live packet capture.'
                                : 'Wireshark/TShark not found on PATH. Install Wireshark to enable raw IGMP capture.'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFF282828)),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return _IgmpTableRow(event: event, timeFormat: timeFormat);
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

class _IgmpTableRow extends StatelessWidget {
  final IgmpQueryEvent event;
  final DateFormat timeFormat;

  const _IgmpTableRow({
    required this.event,
    required this.timeFormat,
  });

  @override
  Widget build(BuildContext context) {
    Color typeColor = const Color(0xFF4FC1FF);
    if (event.isGeneralQuery) {
      typeColor = const Color(0xFF4CAF50);
    } else if (event.typeName.contains('Leave')) {
      typeColor = const Color(0xFFFF9800);
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              timeFormat.format(event.timestamp),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              event.querierIp,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              event.destinationIp,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: typeColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event.typeName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              event.groupAddress,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              event.isQuery ? '${event.maxRespTimeSeconds.toStringAsFixed(1)} s' : '—',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              event.version,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
