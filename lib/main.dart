import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const FiveStonesApp());
}

class FiveStonesApp extends StatelessWidget {
  const FiveStonesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8B5A2B); // warm wood tone
    return MaterialApp(
      title: '5Stones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
