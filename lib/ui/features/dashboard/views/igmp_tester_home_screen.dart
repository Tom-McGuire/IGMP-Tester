import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../gaps/views/gap_analysis_table.dart';
import '../../igmp_monitor/views/igmp_query_log_table.dart';
import '../../receiver/views/receiver_panel.dart';
import '../../sender/views/sender_panel.dart';
import '../view_models/igmp_tester_view_model.dart';
import 'global_error_banner.dart';
import 'status_bottom_bar.dart';
import 'top_control_bar.dart';

class IgmpTesterHomeScreen extends StatefulWidget {
  const IgmpTesterHomeScreen({super.key});

  @override
  State<IgmpTesterHomeScreen> createState() => _IgmpTesterHomeScreenState();
}

class _IgmpTesterHomeScreenState extends State<IgmpTesterHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final vm = Provider.of<IgmpTesterViewModel>(context, listen: false);
    await vm.stopAll();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final errorMsg = vm.errorMessage;

    return Scaffold(
      body: Column(
        children: [
          // Top Control Bar
          const TopControlBar(),

          // Socket Error Banner if present
          if (errorMsg != null)
            GlobalErrorBanner(
              errorMessage: errorMsg,
              onDismiss: () => vm.dismissError(),
            ),

          // Navigation Tab Bar
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: Theme.of(context).colorScheme.primary,
              indicatorWeight: 3,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.send_rounded, size: 14),
                      const SizedBox(width: 8),
                      const Text('Transmitter (Tx)'),
                      if (vm.isSenderRunning) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.call_received_rounded, size: 14),
                      const SizedBox(width: 8),
                      const Text('Receiver (Rx)'),
                      if (vm.isReceiverRunning) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: vm.receiverStats.lossRatePercent > 0
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF2196F3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timeline, size: 14),
                      const SizedBox(width: 8),
                      Text('Gap Analysis (${vm.gaps.length})'),
                      if (vm.gaps.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF44336),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            vm.gaps.length.toString(),
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radar, size: 14),
                      const SizedBox(width: 8),
                      Text('IGMP Query Monitor (${vm.igmpEvents.length})'),
                      if (vm.isSnifferRunning) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Screen Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SenderPanel(),
                ReceiverPanel(),
                GapAnalysisTable(),
                IgmpQueryLogTable(),
              ],
            ),
          ),

          // Bottom Telemetry Bar
          const StatusBottomBar(),
        ],
      ),
    );
  }
}
