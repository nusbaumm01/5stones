import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Placeholder game screen. The board and rules arrive in later steps.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.opponent});

  final Opponent opponent;

  @override
  Widget build(BuildContext context) {
    final title = opponent == Opponent.human
        ? 'Two players'
        : 'Versus computer';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('The board is coming soon.')),
    );
  }
}
