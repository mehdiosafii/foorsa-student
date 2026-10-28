import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/student_calls.dart';
import 'src/shell_appearance.dart';
import 'src/shell_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  // The theme the student chose, before the first frame: the loading screen
  // opens in it rather than in the phone's. One small file, a few ms.
  final appearance = await ShellAppearanceStore().read();
  await StudentCalls.instance.start();
  runApp(FoorsaStudentApp(appearance: appearance));
}

class FoorsaStudentApp extends StatelessWidget {
  const FoorsaStudentApp({super.key, this.appearance});

  final ShellAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foorsa Student',
      builder: (context, child) =>
          StudentCallOverlay(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(AppConfig.brandColorValue)),
      ),
      home: ShellPage(appearance: appearance),
    );
  }
}
