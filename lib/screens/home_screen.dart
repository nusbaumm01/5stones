import 'package:flutter/material.dart';

import '../game/ai.dart';
import '../game/game_controller.dart';
import '../online/online_game.dart';
import 'game_screen.dart';
import 'online_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Difficulty _difficulty = Difficulty.medium;
  bool _humanFirst = true;
  bool _tournamentRule = false;

  void _start(bool vsComputer) {
    final settings = GameSettings(
      vsComputer: vsComputer,
      difficulty: _difficulty,
      humanPlaysFirst: _humanFirst,
      tournamentRule: _tournamentRule,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(settings: settings)),
    );
  }

  void _playOnline() {
    final service = OnlineService.instance;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => service == null
            ? const OnlineUnavailableScreen()
            : OnlineLobbyScreen(
                service: service,
                tournamentRule: _tournamentRule,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
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
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const Key('play-two-players'),
                    onPressed: () => _start(false),
                    icon: const Icon(Icons.people),
                    label: const Text('Two players'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('play-online'),
                    onPressed: _playOnline,
                    icon: const Icon(Icons.public),
                    label: const Text('Play online'),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Play the computer',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<Difficulty>(
                            key: const Key('difficulty'),
                            segments: [
                              for (final d in Difficulty.values)
                                ButtonSegment(value: d, label: Text(d.label)),
                            ],
                            selected: {_difficulty},
                            onSelectionChanged: (s) =>
                                setState(() => _difficulty = s.first),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('I go first'),
                            subtitle: Text(
                              _humanFirst ? 'You play white' : 'You play black',
                            ),
                            value: _humanFirst,
                            onChanged: (v) => setState(() => _humanFirst = v),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            key: const Key('play-computer'),
                            onPressed: () => _start(true),
                            icon: const Icon(Icons.computer),
                            label: const Text('Start'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Tournament rule'),
                    subtitle: const Text(
                      "First player's second stone must be at least "
                      '3 points from the center.',
                    ),
                    value: _tournamentRule,
                    onChanged: (v) => setState(() => _tournamentRule = v),
                  ),
                  TextButton.icon(
                    onPressed: () => showRules(context),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('How to play'),
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

void showRules(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How to play'),
      content: const SingleChildScrollView(
        child: Text(
          'Players take turns placing a stone on an empty intersection. '
          'White goes first, on the center point.\n\n'
          'Capture: if you place a stone so that exactly two of your '
          "opponent's stones sit between two of yours in a straight line "
          '(across, down or diagonal), those two stones are removed.\n\n'
          "It's safe to place a stone into a spot that would look "
          "captured. Only the player who closes the trap captures.\n\n"
          'Win by getting five or more stones in a row, or by capturing '
          'five pairs.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
