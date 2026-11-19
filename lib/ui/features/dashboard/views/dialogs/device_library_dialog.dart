import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:igmp_tester/data/services/igmp/igmp_querier_watchdog.dart';
import 'package:igmp_tester/domain/models/multicast_config.dart';
import 'package:provider/provider.dart';
import '../../../../theme/app_theme.dart';
import '../../view_models/igmp_tester_view_model.dart';

class DeviceLibraryDialog extends StatefulWidget {
  const DeviceLibraryDialog({super.key});

  static Future<void> show(BuildContext context) async {
    final vm = Provider.of<IgmpTesterViewModel>(context, listen: false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => ChangeNotifierProvider<IgmpTesterViewModel>.value(
        value: vm,
        child: const DeviceLibraryDialog(),
      ),
    );
  }

  @override
  State<DeviceLibraryDialog> createState() => _DeviceLibraryDialogState();
}

class _DeviceLibraryDialogState extends State<DeviceLibraryDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Lighting':
        return Icons.lightbulb_outline;
      case 'Audio':
        return Icons.volume_up_outlined;
      case 'Video':
        return Icons.videocam_outlined;
      case 'Timing':
        return Icons.schedule_outlined;
      default:
        return Icons.hub_outlined;
    }
  }

  Color _querierHealthColor(QuerierHealth health) {
    switch (health) {
      case QuerierHealth.active:
        return AppTheme.success;
      case QuerierHealth.warning:
        return AppTheme.warning;
      case QuerierHealth.critical:
        return AppTheme.error;
      case QuerierHealth.idle:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IgmpTesterViewModel>();
    final accentHighlight = AppTheme.isDark ? const Color(0xFF4FC1FF) : AppTheme.accent;

    // Extended reference library of standard multicast endpoints
    final allProfiles = [
      ...ProtocolPreset.all.where((p) => p != ProtocolPreset.custom),
      const ProtocolPreset(
        id: 'ptp',
        name: 'PTP (IEEE 1588 / AES67 Clock)',
        category: 'Timing',
        defaultGroup: '224.0.1.129',
        defaultPort: 319,
        packetsPerSecond: 128,
        packetSizeBytes: 64,
        description: 'Precision Time Protocol sync & event traffic (319/320, 224.0.1.129)',
      ),
      const ProtocolPreset(
        id: 'mdns',
        name: 'mDNS / Bonjour Discovery',
        category: 'General',
        defaultGroup: '224.0.0.251',
        defaultPort: 5353,
        packetsPerSecond: 10,
        packetSizeBytes: 200,
        description: 'Multicast DNS service discovery & zero-configuration networking (224.0.0.251)',
      ),
      const ProtocolPreset(
        id: 'qlan',
        name: 'Q-SYS Q-LAN Audio',
        category: 'Audio',
        defaultGroup: '239.255.0.1',
        defaultPort: 5004,
        packetsPerSecond: 1000,
        packetSizeBytes: 256,
        description: 'Q-SYS network audio streaming (32-bit floating point, 1ms packet time)',
      ),
    ];

    final filteredProfiles = allProfiles.where((p) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.defaultGroup.contains(q) ||
          p.defaultPort.toString().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: AppTheme.isDark ? 0.15 : 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.devices, color: accentHighlight, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEVICE & MULTICAST REGISTRY',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Known Network Suite devices, AV multicast profiles, and switch querier endpoints',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Input
              TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textSecondary),
                  hintText: 'Search multicast protocols, groups, ports, or hardware...',
                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppTheme.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppTheme.borderStrong),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppTheme.borderStrong),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 14, color: AppTheme.textSecondary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
              const SizedBox(height: 12),

              // Tab Selector
              TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.accent,
                indicatorWeight: 2,
                labelColor: AppTheme.textPrimary,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Multicast Profiles & Presets'),
                  Tab(text: 'Network Interfaces & Querier'),
                ],
              ),
              const SizedBox(height: 10),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Profiles
                    filteredProfiles.isEmpty
                        ? Center(
                            child: Text(
                              'No matching multicast profiles found.',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredProfiles.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: AppTheme.border),
                            itemBuilder: (context, index) {
                              final profile = filteredProfiles[index];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceHigh,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.borderStrong),
                                  ),
                                  child: Icon(
                                    _getCategoryIcon(profile.category),
                                    size: 16,
                                    color: accentHighlight,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      profile.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: AppTheme.isDark ? 0.2 : 0.10),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${profile.defaultGroup}:${profile.defaultPort}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          color: accentHighlight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${profile.description} • ${profile.packetsPerSecond} pps (${profile.packetSizeBytes}B)',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                                trailing: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accent.withValues(alpha: AppTheme.isDark ? 0.2 : 0.10),
                                    foregroundColor: accentHighlight,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    side: BorderSide(color: AppTheme.accent),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add, size: 12),
                                  label: const Text('Apply', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    vm.batchGenerateSenderStreams(
                                      count: 5,
                                      startingIp: profile.defaultGroup,
                                      basePort: profile.defaultPort,
                                      pps: profile.packetsPerSecond,
                                      packetSize: profile.packetSizeBytes,
                                    );
                                    vm.batchGenerateReceiverStreams(
                                      count: 5,
                                      startingIp: profile.defaultGroup,
                                      basePort: profile.defaultPort,
                                    );
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Applied "${profile.name}" (5 streams) to Tx & Rx test rig',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),

                    // Tab 2: Interfaces & Querier
                    ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Active Network Interfaces',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: accentHighlight,
                            ),
                          ),
                        ),
                        ...vm.interfaces.map(
                          (iface) => ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            leading: Icon(Icons.settings_ethernet, size: 16, color: AppTheme.textSecondary),
                            title: Text(
                              iface.displayName,
                              style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              'IP: ${iface.ip} • Subnet: ${iface.subnetMask} • Interface: ${iface.name}',
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.copy, size: 14, color: AppTheme.textSecondary),
                              tooltip: 'Copy IP',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: iface.ip));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Copied ${iface.ip} to clipboard')),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(height: 1, color: AppTheme.border),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'IGMP Querier Status',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: accentHighlight,
                            ),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(
                            Icons.router,
                            size: 16,
                            color: _querierHealthColor(vm.querierStatus.health),
                          ),
                          title: Text(
                            'Querier IP: ${vm.querierStatus.querierIp ?? 'Unknown / Not Detected'}',
                            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            'State: ${vm.querierStatus.health.label} • Last Query: ${vm.querierStatus.secondsSinceLastQuery != null ? '${vm.querierStatus.secondsSinceLastQuery}s ago' : 'No queries observed yet'}',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
