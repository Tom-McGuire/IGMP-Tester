import 'dart:ui' show AppExitResponse;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/guided_tour_overlay.dart';
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
  final GlobalKey _zone2InterfaceKey = GlobalKey();
  final GlobalKey _zone3StartStopKey = GlobalKey();
  final GlobalKey _streamConfigPanelKey = GlobalKey();
  final GlobalKey _activeStreamsTableKey = GlobalKey();
  final GlobalKey _igmpMonitorKey = GlobalKey();
  late final List<GuidedTourStep> _tourSteps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 4,
      vsync: this,
      animationDuration: Duration.zero,
    );
    _tourSteps = [
      GuidedTourStep(
        targetKey: _zone2InterfaceKey,
        title: 'Zone 2: Multicast Bind Interface',
        description:
            'Select the physical network interface used for IGMP group joins and UDP multicast transmission.',
      ),
      GuidedTourStep(
        targetKey: _zone3StartStopKey,
        title: 'Zone 3: Master Multicast Start/Stop',
        description:
            'Start and stop all configured multicast transmitters, receivers, and active group tests together.',
      ),
      GuidedTourStep(
        targetKey: _streamConfigPanelKey,
        title: 'Multicast Stream Configuration Panel',
        description:
            'Configure UDP multicast transmitters with custom group IPs (239.x.x.x), ports, packet rates, TTL, and DSCP QoS tags.',
        onStepEnter: () {
          _tabController.index = 0;
        },
      ),
      GuidedTourStep(
        targetKey: _activeStreamsTableKey,
        title: 'Active Streams & Telemetry Table',
        description:
            'Join IGMPv2/v3 groups (ASM or SSM), monitor per-group packet rates, bitrate, jitter, and probe Fast-Leave latency.',
        onStepEnter: () {
          _tabController.index = 1;
        },
      ),
      GuidedTourStep(
        targetKey: _igmpMonitorKey,
        title: 'IGMP Query Sniffer & Event Log',
        description:
            'Verify whether an IGMP querier is active on your VLAN and inspect captured membership queries, reports, and leaves.',
        onStepEnter: () {
          _tabController.index = 3;
        },
      ),
    ];
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
    final warningMsg = vm.diagnosticWarning;

    return GuidedTourOverlay(
      isActive: vm.isDemoMode,
      steps: _tourSteps,
      onFinish: () => vm.endDemoWalkthrough(),
      child: Scaffold(
        body: Column(
          children: [
            // Top Control Bar
            TopControlBar(
              interfaceSelectorKey: _zone2InterfaceKey,
              masterStartStopKey: _zone3StartStopKey,
            ),

            // Socket Error Banner if present
            if (errorMsg != null)
              GlobalErrorBanner(
                errorMessage: errorMsg,
                onDismiss: () => vm.dismissError(),
              ),

            // Non-blocking Diagnostic Compatibility / QoS Warning Banner
            if (warningMsg != null)
              GlobalErrorBanner(
                errorMessage: warningMsg,
                isWarning: true,
                onDismiss: () => vm.dismissDiagnosticWarning(),
              ),

            // Navigation Tab Bar
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppTheme.accent,
                indicatorWeight: 3,
                labelColor: AppTheme.accent,
                unselectedLabelColor: AppTheme.textSecondary,
                dividerColor: Colors.transparent,
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
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.success,
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
                                  ? AppTheme.warning
                                  : AppTheme.info,
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
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              vm.gaps.length.toString(),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.success,
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
                children: [
                  KeyedSubtree(
                    key: _streamConfigPanelKey,
                    child: const SenderPanel(),
                  ),
                  KeyedSubtree(
                    key: _activeStreamsTableKey,
                    child: const ReceiverPanel(),
                  ),
                  const GapAnalysisTable(),
                  KeyedSubtree(
                    key: _igmpMonitorKey,
                    child: const IgmpQueryLogTable(),
                  ),
                ],
              ),
            ),

            // Bottom Telemetry Bar
            const StatusBottomBar(),
          ],
        ),
      ),
    );
  }
}
