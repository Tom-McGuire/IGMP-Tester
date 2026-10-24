import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/features/dashboard/view_models/igmp_tester_view_model.dart';
import 'ui/features/dashboard/views/igmp_tester_home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IgmpTesterApp());
}

class IgmpTesterApp extends StatelessWidget {
  const IgmpTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => IgmpTesterViewModel(),
      child: MaterialApp(
        title: 'IGMP & Multicast Tester',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const IgmpTesterHomeScreen(),
      ),
    );
  }
}
