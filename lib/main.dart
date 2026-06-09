import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio.dart';
import 'home_screen.dart';
import 'theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ThemeService.load();      // resolve the board theme before first paint
  AudioService.instance.init();   // fire-and-forget; fails silently if unavailable
  runApp(const CollapseApp());
}

class CollapseApp extends StatelessWidget {
  const CollapseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Singularity: Collapse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DefaultTextStyle(
        style: TextStyle(decoration: TextDecoration.none),
        child: HomeScreen(),
      ),
    );
  }
}
