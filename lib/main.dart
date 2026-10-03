import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart'; // your Firebase project settings
import 'screens/auth_gate.dart';
import 'services/update_check.dart';
import 'theme.dart';

final _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const UtsavApp());
}

class UtsavApp extends StatefulWidget {
  const UtsavApp({super.key});

  @override
  State<UtsavApp> createState() => _UtsavAppState();
}

class _UtsavAppState extends State<UtsavApp> {
  @override
  void initState() {
    super.initState();
    // Check for a newer version a moment after the app opens.
    Future.delayed(const Duration(seconds: 2), () {
      final ctx = _navKey.currentState?.overlay?.context;
      if (ctx != null && ctx.mounted) checkForUpdate(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Vinayaka Utsav',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}
