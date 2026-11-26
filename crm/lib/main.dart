import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/crm_shell.dart';
import 'src/push.dart';
import 'src/web_view_touch.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On an iPhone the web view takes its touches straight from iOS
  // (web_view_touch.dart, the same fix as the student app's).
  useUnblockedWebViewTouches();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  // A tapped notification that launched the app opens on its page.
  final initialRoute = await CrmPush.instance.start();
  runApp(FoorsaCrmApp(initialRoute: initialRoute));
}

class FoorsaCrmApp extends StatelessWidget {
  const FoorsaCrmApp({super.key, this.initialRoute});

  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foorsa CRM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(CrmConfig.navy)),
        useMaterial3: true,
      ),
      home: CrmShell(initialRoute: initialRoute),
    );
  }
}
