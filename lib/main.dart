import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'achievement_service.dart';
import 'audio.dart';
import 'home_screen.dart';
import 'quantum_service.dart';
import 'theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ThemeService.load();      // resolve the board theme before first paint
  await QuantumService.load();    // remember the Quantum-mode picker config
  AudioService.instance.init();   // fire-and-forget; fails silently if unavailable
  // Resolve which music tracks are unlocked (free + achievement-earned) and hand
  // them to the audio rotation. Async + fire-and-forget — music only plays inside a
  // gameplay/settings context, reached well after this resolves.
  AchievementService.unlockedTracks().then(AudioService.instance.setUnlockedMusic);
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
