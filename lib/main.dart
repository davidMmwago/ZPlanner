import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'data/app_files.dart';
import 'google/google_auth.dart';
import 'notify/notifier.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await AppFiles.init();
  await Notifier.init();
  await GoogleAuth.instance.load();
  runApp(const ZeeApp());
  Notifier.rescheduleAllTodos(); // keeps reminders correct after updates/reboots
}

class ZeeApp extends StatelessWidget {
  const ZeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zee',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeShell(),
    );
  }
}
