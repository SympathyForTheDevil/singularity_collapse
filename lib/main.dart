import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
