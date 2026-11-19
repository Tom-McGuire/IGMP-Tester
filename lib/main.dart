import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

import 'data/services/storage/suite_theme_sync_service.dart';
import 'domain/models/launch_adapter_config.dart';
import 'ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'ui/features/dashboard/views/igmp_tester_home_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (_) {}
  final initialMode = await SuiteThemeSyncService.getThemeMode();
  AppTheme.applyThemeMode(initialMode);
  final launchAdapterConfig = LaunchAdapterConfig.fromArgs(args);
  runApp(IgmpTesterApp(launchAdapterConfig: launchAdapterConfig));
}

class IgmpTesterApp extends StatefulWidget {
  final IgmpTesterViewModel? viewModel;
  final LaunchAdapterConfig? launchAdapterConfig;
  final Future<String> Function()? themeModeLoader;
  final Stream<void>? themeChangeStream;
  final bool enableExternalThemeWatch;

  const IgmpTesterApp({
    super.key,
    this.viewModel,
    this.launchAdapterConfig,
    this.themeModeLoader,
    this.themeChangeStream,
    this.enableExternalThemeWatch = true,
  });

  @override
  State<IgmpTesterApp> createState() => _IgmpTesterAppState();
}

class _IgmpTesterAppState extends State<IgmpTesterApp> {
  late String _themeMode;
  StreamSubscription<void>? _dbSub;
  StreamSubscription<void>? _externalWatchSub;

  @override
  void initState() {
    super.initState();
    _themeMode = AppTheme.themeMode;
    _syncTheme();
    _dbSub = (widget.themeChangeStream ??
            SharedDeviceDatabase.instance.onDatabaseChanged)
        .listen((_) => _syncTheme());
    if (widget.enableExternalThemeWatch && widget.themeChangeStream == null) {
      try {
        _externalWatchSub =
            SuiteThemeSyncService.watchExternalChanges().listen((_) => _syncTheme());
      } catch (_) {}
    }
  }

  Future<void> _syncTheme() async {
    final mode =
        await (widget.themeModeLoader ?? SuiteThemeSyncService.getThemeMode)();
    if (mounted && mode != _themeMode) {
      setState(() {
        _themeMode = mode;
        AppTheme.applyThemeMode(mode);
      });
    }
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    _externalWatchSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'IGMP & Multicast Tester',
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeAnimationDuration: Duration.zero,
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const IgmpTesterHomeScreen(),
      ),
    );

    if (widget.viewModel != null) {
      return ChangeNotifierProvider<IgmpTesterViewModel>.value(
        value: widget.viewModel!,
        child: app,
      );
    }

    return ChangeNotifierProvider(
      create: (_) =>
          IgmpTesterViewModel(launchAdapterConfig: widget.launchAdapterConfig),
      child: app,
    );
  }
}
