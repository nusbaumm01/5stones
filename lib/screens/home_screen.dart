import 'package:flutter/material.dart';

import 'game_screen.dart';

/// Who the second player is.
enum Opponent { human, computer }

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _start(BuildContext context, Opponent opponent) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(opponent: opponent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '5Stones',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Five in a row, or five captures, wins.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    key: const Key('play-two-players'),
                    onPressed: () => _start(context, Opponent.human),
                    icon: const Icon(Icons.people),
                    label: const Text('Two players'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const Key('play-computer'),
                    onPressed: () => _start(context, Opponent.computer),
                    icon: const Icon(Icons.computer),
                    label: const Text('Play the computer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
